import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import 'models.dart';
import 'offline_queue.dart';
import 'session.dart';

enum CheckFrequency {
  daily,
  weekly,
  monthly;

  static CheckFrequency? tryParse(String? v) {
    final s = v?.trim().toLowerCase() ?? '';
    for (final f in CheckFrequency.values) {
      if (s == f.name || (s.length >= 3 && f.name.startsWith(s))) return f;
    }
    return null;
  }

  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

enum TaskStatus {
  pending,
  done,
  missed;

  static TaskStatus parse(String? v) => TaskStatus.values.firstWhere((s) => s.name == v, orElse: () => TaskStatus.pending);
}

DateTime _date(String s) {
  final d = DateTime.parse(s);
  return DateTime(d.year, d.month, d.day);
}

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// One due occurrence of a check item.
class CheckTask {
  const CheckTask({
    required this.id,
    required this.itemId,
    required this.equipmentId,
    required this.plantId,
    required this.dueDate,
    required this.windowEnd,
    required this.status,
    required this.title,
    required this.frequency,
    required this.equipmentName,
    required this.equipmentCode,
    this.description,
    this.completedAt,
    this.completedByName,
    this.note,
  });

  final String id, itemId, equipmentId, plantId, title, equipmentName, equipmentCode;
  final String? description, completedByName, note;
  final DateTime dueDate, windowEnd;
  final DateTime? completedAt;
  final TaskStatus status;
  final CheckFrequency frequency;

  bool get isDone => status == TaskStatus.done;

  /// Pending, past its due day but still inside its completion window.
  bool isOverdue(DateTime today) => status == TaskStatus.pending && dueDate.isBefore(today) && !windowEnd.isBefore(today);

  static const select =
      'id,check_item_id,equipment_id,plant_id,due_date,window_end,status,completed_at,note,'
      'check_items(title,description,frequency),equipment(name,tag_code),completer:profiles!check_tasks_completed_by_fkey(name)';

  factory CheckTask.fromJson(Json j) {
    final item = j['check_items'] as Json? ?? const {};
    final eq = j['equipment'] as Json? ?? const {};
    return CheckTask(
      id: j['id'] as String,
      itemId: j['check_item_id'] as String,
      equipmentId: j['equipment_id'] as String,
      plantId: j['plant_id'] as String,
      dueDate: _date(j['due_date'] as String),
      windowEnd: _date(j['window_end'] as String),
      status: TaskStatus.parse(j['status'] as String?),
      completedAt: j['completed_at'] == null ? null : DateTime.parse(j['completed_at'] as String).toLocal(),
      note: j['note'] as String?,
      title: item['title'] as String? ?? 'Check',
      description: item['description'] as String?,
      frequency: CheckFrequency.tryParse(item['frequency'] as String?) ?? CheckFrequency.daily,
      equipmentName: eq['name'] as String? ?? '',
      equipmentCode: eq['tag_code'] as String? ?? '',
      completedByName: (j['completer'] as Json?)?['name'] as String?,
    );
  }

  CheckTask copyWith({TaskStatus? status, DateTime? completedAt, String? completedByName, bool clearCompletion = false}) => CheckTask(
        id: id,
        itemId: itemId,
        equipmentId: equipmentId,
        plantId: plantId,
        dueDate: dueDate,
        windowEnd: windowEnd,
        status: status ?? this.status,
        title: title,
        frequency: frequency,
        equipmentName: equipmentName,
        equipmentCode: equipmentCode,
        description: description,
        completedAt: clearCompletion ? null : (completedAt ?? this.completedAt),
        completedByName: clearCompletion ? null : (completedByName ?? this.completedByName),
        note: note,
      );
}

enum FindingStatus {
  open,
  scheduled,
  resolved;

  static FindingStatus parse(String? v) => FindingStatus.values.firstWhere((s) => s.name == v, orElse: () => FindingStatus.open);
}

class Finding {
  const Finding({
    required this.id,
    required this.equipmentId,
    required this.plantId,
    required this.description,
    required this.status,
    required this.reportedAt,
    this.checkTaskId,
    this.photoPath,
    this.scheduledFor,
    this.reporterName,
    this.resolverName,
    this.resolvedAt,
    this.resolutionNote,
    this.equipmentName,
    this.equipmentCode,
  });

  final String id, equipmentId, plantId, description;
  final String? checkTaskId, photoPath, reporterName, resolverName, resolutionNote, equipmentName, equipmentCode;
  final FindingStatus status;
  final DateTime reportedAt;
  final DateTime? scheduledFor, resolvedAt;

  bool isOverdue(DateTime now) => status == FindingStatus.scheduled && scheduledFor != null && scheduledFor!.isBefore(now);

  static const select =
      'id,check_task_id,equipment_id,plant_id,description,photo_path,status,scheduled_for,reported_at,resolved_at,resolution_note,'
      'equipment(name,tag_code),reporter:profiles!findings_reported_by_fkey(name),resolver:profiles!findings_resolved_by_fkey(name)';

  factory Finding.fromJson(Json j) {
    DateTime? t(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    final eq = j['equipment'] as Json? ?? const {};
    return Finding(
      id: j['id'] as String,
      checkTaskId: j['check_task_id'] as String?,
      equipmentId: j['equipment_id'] as String,
      plantId: j['plant_id'] as String,
      description: j['description'] as String,
      photoPath: j['photo_path'] as String?,
      status: FindingStatus.parse(j['status'] as String?),
      scheduledFor: t('scheduled_for'),
      reportedAt: t('reported_at')!,
      resolvedAt: t('resolved_at'),
      resolutionNote: j['resolution_note'] as String?,
      equipmentName: eq['name'] as String?,
      equipmentCode: eq['tag_code'] as String?,
      reporterName: (j['reporter'] as Json?)?['name'] as String?,
      resolverName: (j['resolver'] as Json?)?['name'] as String?,
    );
  }
}

class DailyCheckStat {
  const DailyCheckStat({required this.day, required this.planned, required this.completed, required this.cumPlanned, required this.cumCompleted});
  final DateTime day;
  final int planned, completed, cumPlanned, cumCompleted;

  factory DailyCheckStat.fromJson(Json j) => DailyCheckStat(
        day: _date(j['day'] as String),
        planned: (j['planned'] as num).toInt(),
        completed: (j['completed'] as num).toInt(),
        cumPlanned: (j['cum_planned'] as num).toInt(),
        cumCompleted: (j['cum_completed'] as num).toInt(),
      );
}

class DailyFindingStat {
  const DailyFindingStat({required this.day, required this.found, required this.resolved, required this.cumFound, required this.cumResolved});
  final DateTime day;
  final int found, resolved, cumFound, cumResolved;

  factory DailyFindingStat.fromJson(Json j) => DailyFindingStat(
        day: _date(j['day'] as String),
        found: (j['found'] as num).toInt(),
        resolved: (j['resolved'] as num).toInt(),
        cumFound: (j['cum_found'] as num).toInt(),
        cumResolved: (j['cum_resolved'] as num).toInt(),
      );
}

typedef StatsKey = ({String? plantId, int days});

/// Checks for "My checks": the last 5 weeks (for overdue weekly/monthly windows) up to a week ahead.
final checkTasksProvider = FutureProvider.family<List<CheckTask>, String?>((ref, equipmentId) async {
  final client = ref.watch(supabaseProvider);
  final t = today();
  var q = client
      .from('check_tasks')
      .select(CheckTask.select)
      .gte('due_date', isoDate(t.subtract(const Duration(days: 35))))
      .lte('due_date', isoDate(t.add(const Duration(days: 7))));
  if (equipmentId != null) q = q.eq('equipment_id', equipmentId);
  final rows = await q.order('due_date').limit(3000);
  return rows.map(CheckTask.fromJson).toList();
});

final findingsProvider = FutureProvider.family<List<Finding>, String?>((ref, equipmentId) async {
  var q = ref.watch(supabaseProvider).from('findings').select(Finding.select);
  if (equipmentId != null) q = q.eq('equipment_id', equipmentId);
  final rows = await q.order('reported_at', ascending: false).limit(500);
  return rows.map(Finding.fromJson).toList();
});

final checkStatsProvider = FutureProvider.family<List<DailyCheckStat>, StatsKey>((ref, k) async {
  final t = today();
  final rows = await ref.watch(supabaseProvider).rpc('check_stats_daily', params: {
    'p_plant': k.plantId,
    'p_from': isoDate(t.subtract(Duration(days: k.days - 1))),
    'p_to': isoDate(t),
  }) as List;
  return rows.cast<Json>().map(DailyCheckStat.fromJson).toList();
});

final findingStatsProvider = FutureProvider.family<List<DailyFindingStat>, StatsKey>((ref, k) async {
  final t = today();
  final rows = await ref.watch(supabaseProvider).rpc('finding_stats_daily', params: {
    'p_plant': k.plantId,
    'p_from': isoDate(t.subtract(Duration(days: k.days - 1))),
    'p_to': isoDate(t),
  }) as List;
  return rows.cast<Json>().map(DailyFindingStat.fromJson).toList();
});

/// Write operations for checks and findings.
class ChecksRepository {
  ChecksRepository(this.ref);
  final Ref ref;

  /// Tick / untick. Works offline: queued and sent when the connection returns.
  Future<SendResult> setTaskDone(String taskId, bool done) {
    return ref.read(offlineQueueProvider).submit(QueuedAction(
          id: const Uuid().v4(),
          userId: ref.read(profileProvider).id,
          kind: QueuedKind.taskTick,
          payload: {'task_id': taskId, 'status': done ? 'done' : 'pending'},
        ));
  }

  Future<SendResult> reportFinding({
    required String clientId,
    required String equipmentId,
    String? checkTaskId,
    required String description,
    required FindingStatus status,
    DateTime? scheduledFor,
    Uint8List? photo,
  }) {
    return ref.read(offlineQueueProvider).submit(QueuedAction(
          id: clientId,
          userId: ref.read(profileProvider).id,
          kind: QueuedKind.finding,
          photo: photo,
          payload: {
            'equipment_id': equipmentId,
            'check_task_id': ?checkTaskId,
            'description': description,
            'status': status.name,
            'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
            'reported_by': ref.read(profileProvider).id,
          },
        ));
  }

  Future<void> updateFinding(String id, {required FindingStatus status, DateTime? scheduledFor, String? resolutionNote}) async {
    await ref.read(supabaseProvider).from('findings').update({
      'status': status.name,
      'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      'resolution_note': ?resolutionNote,
    }).eq('id', id);
  }
}

final checksRepositoryProvider = Provider<ChecksRepository>(ChecksRepository.new);
