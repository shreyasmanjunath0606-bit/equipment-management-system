import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'offline_queue.dart';
import 'providers.dart';
import 'session.dart';

typedef EquipmentQuery = ({String q, String? plantId, String? status, int limit});

/// Equipment list page (current status view) with search / filters. `status` may be a status
/// type id, "failing" or "none".
final equipmentListProvider = FutureProvider.family<({List<CurrentStatus> rows, int total}), EquipmentQuery>((ref, f) async {
  final client = ref.watch(supabaseProvider);
  final types = await ref.watch(statusTypesProvider.future);
  var q = client.from('equipment_current_status').select();
  final term = f.q.trim().replaceAll(RegExp(r'[%,()]'), ' ');
  if (term.isNotEmpty) q = q.or('name.ilike.%$term%,tag_code.ilike.%$term%');
  if (f.plantId != null) q = q.eq('plant_id', f.plantId!);
  if (f.status == 'none') {
    q = q.isFilter('status_type_id', null);
  } else if (f.status == 'failing') {
    q = q.inFilter('status_type_id', types.where((t) => t.isFailure).map((t) => t.id).toList());
  } else if (f.status != null) {
    q = q.eq('status_type_id', f.status!);
  }
  final res = await q.order('name').range(0, f.limit - 1).count(CountOption.exact);
  return (rows: res.data.map(CurrentStatus.fromJson).toList(), total: res.count);
});

class EquipmentDetail {
  const EquipmentDetail({required this.equipment, this.plantName, this.plantTimezone, this.areaName});
  final Equipment equipment;
  final String? plantName, plantTimezone, areaName;
}

final equipmentDetailProvider = FutureProvider.family<EquipmentDetail?, String>((ref, id) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('equipment')
      .select('${Equipment.columns},plants(name,timezone),areas(name)')
      .eq('id', id)
      .maybeSingle();
  if (row == null) return null;
  return EquipmentDetail(
    equipment: Equipment.fromJson(row),
    plantName: (row['plants'] as Json?)?['name'] as String?,
    plantTimezone: (row['plants'] as Json?)?['timezone'] as String?,
    areaName: (row['areas'] as Json?)?['name'] as String?,
  );
});

/// Status timeline for one machine, with signed photo URLs (photos are private).
final equipmentEventsProvider = FutureProvider.family<({List<StatusEvent> events, Map<String, String> photos}), String>((ref, id) async {
  final client = ref.watch(supabaseProvider);
  final rows = await client
      .from('status_events')
      .select('id,equipment_id,status_type_id,plant_id,note,photo_path,reported_by,reported_at,profiles(name)')
      .eq('equipment_id', id)
      .order('reported_at', ascending: false)
      .limit(100);
  final events = rows.map(StatusEvent.fromJson).toList();
  final paths = events.map((e) => e.photoPath).whereType<String>().toList();
  final photos = <String, String>{};
  if (paths.isNotEmpty) {
    try {
      // ignore: deprecated_member_use
      final signed = await client.storage.from('failure-photos').createSignedUrls(paths, 3600);
      for (final s in signed) {
        photos[s.path] = s.signedUrl;
      }
    } catch (_) {}
  }
  return (events: events, photos: photos);
});

/// Find equipment by its unique code (case-insensitive). Null if not found / no access.
Future<Equipment?> findEquipmentByCode(SupabaseClient client, String code) async {
  final c = code.trim();
  if (c.isEmpty) return null;
  final rows = await client.from('equipment').select(Equipment.columns).ilike('tag_code', c.replaceAll(RegExp(r'[%_]'), '')).limit(1);
  return rows.isEmpty ? null : Equipment.fromJson(rows.first);
}

/// Pulls an equipment reference out of a scanned QR: our `/e/CODE` links, old
/// `/equipment/ID/update` links, or a bare code.
({String? id, String? code}) parseScannedValue(String raw) {
  final v = raw.trim();
  final uri = Uri.tryParse(v);
  if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) {
    final s = uri.pathSegments;
    if (s.length >= 2 && s[0] == 'e') return (id: null, code: Uri.decodeComponent(s[1]));
    if (s.length >= 2 && s[0] == 'equipment') return (id: s[1], code: null);
  }
  return (id: null, code: v);
}

class EquipmentRepository {
  EquipmentRepository(this.ref);
  final Ref ref;

  SupabaseClient get _db => ref.read(supabaseProvider);

  /// Report a status (offline-safe; the client id makes retries idempotent).
  Future<SendResult> reportStatus({required String equipmentId, required String statusTypeId, String? note, Uint8List? photo}) {
    return ref.read(offlineQueueProvider).submit(QueuedAction(
          id: const Uuid().v4(),
          userId: ref.read(profileProvider).id,
          kind: QueuedKind.statusReport,
          photo: photo,
          payload: {
            'equipment_id': equipmentId,
            'status_type_id': statusTypeId,
            'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
            'reported_at': DateTime.now().toUtc().toIso8601String(),
          },
        ));
  }

  Future<void> create({
    required String plantId,
    String? tagCode,
    required String name,
    String? type,
    String? manufacturer,
    String? model,
    String? serialNo,
  }) async {
    String? n(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    await _db.from('equipment').insert({
      'plant_id': plantId,
      'tag_code': n(tagCode) ?? '', // blank -> generated by the database, e.g. 101-CNC-0001
      'name': name.trim(),
      'type': n(type),
      'manufacturer': n(manufacturer),
      'model': n(model),
      'serial_no': n(serialNo),
    });
  }

  /// Bulk add: one machine per line "code,name,type" (code may be blank).
  Future<int> bulkImport(String plantId, String text) async {
    final rows = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.split(',').map((c) => c.trim()).toList())
        .where((c) => c.length >= 2 && c[1].isNotEmpty)
        .take(500)
        .map((c) => {'plant_id': plantId, 'tag_code': c[0], 'name': c[1], 'type': c.length > 2 && c[2].isNotEmpty ? c[2] : null})
        .toList();
    if (rows.isEmpty) return 0;
    await _db.from('equipment').insert(rows);
    return rows.length;
  }

  Future<void> setActive(String id, bool active) => _db.from('equipment').update({'is_active': active}).eq('id', id);
}

final equipmentRepositoryProvider = Provider<EquipmentRepository>(EquipmentRepository.new);
