import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'checks.dart';
import 'models.dart';
import 'session.dart';

/// Where a workbook sits on an equipment. Daily / Weekly / Monthly decide how often every tab in the
/// workbook repeats; Extra workbooks keep each tab's own FREQUENCY (4-monthly, half-yearly, ...).
enum SheetSlot {
  daily,
  weekly,
  monthly,
  extra;

  static SheetSlot parse(String? v) => SheetSlot.values.firstWhere((s) => s.name == v, orElse: () => SheetSlot.extra);

  static const main = [daily, weekly, monthly];

  String get label => switch (this) {
        daily => 'Daily',
        weekly => 'Weekly',
        monthly => 'Monthly',
        extra => 'Other intervals',
      };

  CheckFrequency? get frequency => switch (this) {
        daily => CheckFrequency.daily,
        weekly => CheckFrequency.weekly,
        monthly => CheckFrequency.monthly,
        extra => null,
      };

  /// "Every day", "Every Monday", "Monthly on the 5th".
  String schedule({int? monthlyDay}) => switch (this) {
        daily => 'Every day',
        weekly => 'Every Monday',
        monthly => monthlyDay == null ? 'Once a month' : 'Monthly on the ${ordinal(monthlyDay)}',
        extra => 'Each tab’s own frequency',
      };
}

/// 1 -> "1st", 22 -> "22nd", 31 -> "31st".
String ordinal(int n) {
  final s = (n % 100 >= 11 && n % 100 <= 13) ? 'th' : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$s';
}

/// An uploaded workbook, as it sits on an equipment.
class CheckSheet {
  CheckSheet({
    required this.id,
    required this.plantId,
    required this.title,
    required this.fileName,
    required this.rowCount,
    required this.createdAt,
    required this.slot,
    this.equipmentId,
    this.monthlyDay,
    this.filePath,
    this.uploader,
    this.activeItems = 0,
  });
  final String id, plantId, title, fileName;
  final String? filePath, uploader, equipmentId;
  final int rowCount, activeItems;
  final int? monthlyDay;
  final SheetSlot slot;
  final DateTime createdAt;

  String get schedule => slot.schedule(monthlyDay: monthlyDay);

  static const select =
      'id,plant_id,equipment_id,slot,monthly_day,title,file_name,file_path,row_count,created_at,'
      'uploader:profiles!check_sheets_uploaded_by_fkey(name),check_items(count)';

  factory CheckSheet.fromJson(Json r) => CheckSheet(
        id: r['id'] as String,
        plantId: r['plant_id'] as String,
        equipmentId: r['equipment_id'] as String?,
        slot: SheetSlot.parse(r['slot'] as String?),
        monthlyDay: (r['monthly_day'] as num?)?.toInt(),
        title: r['title'] as String,
        fileName: r['file_name'] as String,
        filePath: r['file_path'] as String?,
        rowCount: (r['row_count'] as num).toInt(),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        uploader: (r['uploader'] as Json?)?['name'] as String?,
        activeItems: ((r['check_items'] as List?)?.firstOrNull as Json?)?['count'] as int? ?? 0,
      );
}

/// One equipment with its worker and its Daily / Weekly / Monthly (+ extra) workbooks.
class EquipmentPlan {
  EquipmentPlan({required this.equipmentId, required this.name, required this.code, required this.plantId, this.workerId, this.workerName, required this.sheets});
  final String equipmentId, name, code, plantId;
  final String? workerId, workerName;
  final List<CheckSheet> sheets;

  CheckSheet? sheetFor(SheetSlot slot) => sheets.where((s) => s.slot == slot).firstOrNull;
  List<CheckSheet> get extras => sheets.where((s) => s.slot == SheetSlot.extra).toList();
  bool get hasChecks => sheets.isNotEmpty;
}

/// A worker of a plant, and the equipment they already look after (if any).
class PlantWorker {
  const PlantWorker({required this.id, required this.name, required this.email, this.equipmentId});
  final String id, name, email;
  final String? equipmentId;
}

/// Every active equipment the manager can see, with its worker and live workbooks.
final equipmentPlansProvider = FutureProvider<List<EquipmentPlan>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final (eqRows, sheetRows) = await (
    db.from('equipment').select('id,name,tag_code,plant_id,assigned_worker,worker:profiles!equipment_assigned_worker_fkey(name)').eq('is_active', true).order('name'),
    db.from('check_sheets').select(CheckSheet.select).eq('active', true).eq('check_items.active', true).order('created_at'),
  ).wait;
  final sheets = [for (final r in sheetRows) CheckSheet.fromJson(r)];
  return [
    for (final e in eqRows)
      EquipmentPlan(
        equipmentId: e['id'] as String,
        name: e['name'] as String,
        code: e['tag_code'] as String,
        plantId: e['plant_id'] as String,
        workerId: e['assigned_worker'] as String?,
        workerName: (e['worker'] as Json?)?['name'] as String?,
        sheets: [for (final s in sheets) if (s.equipmentId == e['id']) s],
      ),
  ];
});

final plantWorkersProvider = FutureProvider.family<List<PlantWorker>, String>((ref, plantId) async {
  final rows = await ref.watch(supabaseProvider).rpc('plant_workers', params: {'p_plant': plantId}) as List;
  return [
    for (final r in rows.cast<Json>())
      PlantWorker(id: r['id'] as String, name: r['name'] as String, email: r['email'] as String, equipmentId: r['equipment_id'] as String?),
  ];
});

/// The equipment the signed-in worker looks after (null when none is assigned yet).
final myEquipmentProvider = FutureProvider<Equipment?>((ref) async {
  final uid = ref.watch(profileProvider).id;
  if (uid.isEmpty) return null;
  final row = await ref.watch(supabaseProvider).from('equipment').select(Equipment.columns).eq('assigned_worker', uid).maybeSingle();
  return row == null ? null : Equipment.fromJson(row);
});

class AssignmentsRepository {
  AssignmentsRepository(this.ref);
  final Ref ref;

  /// Give [equipmentId] to [workerId] (null = nobody). Their open checks move with it.
  Future<void> assign(String equipmentId, String? workerId) async {
    await ref.read(supabaseProvider).from('equipment').update({'assigned_worker': workerId}).eq('id', equipmentId);
    _refresh();
  }

  /// Take a workbook off the equipment: its checks stop being scheduled, history is kept.
  Future<void> removeSheet(String sheetId) async {
    await ref.read(supabaseProvider).from('check_sheets').update({'active': false}).eq('id', sheetId);
    _refresh();
  }

  void _refresh() {
    ref.invalidate(equipmentPlansProvider);
    ref.invalidate(plantWorkersProvider);
    ref.invalidate(checkTasksProvider);
    ref.invalidate(awaitingVerificationProvider);
  }
}

final assignmentsRepositoryProvider = Provider<AssignmentsRepository>(AssignmentsRepository.new);
