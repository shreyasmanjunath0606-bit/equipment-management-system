import 'dart:convert';
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

/// "Daily", "Weekly", "Every 2 weeks", "Monthly", "Every 4 months", "Half-yearly", "Yearly".
String frequencyLabel(CheckFrequency unit, int interval) {
  if (interval <= 1) return unit.label;
  return switch (unit) {
    CheckFrequency.daily => 'Every $interval days',
    CheckFrequency.weekly => 'Every $interval weeks',
    CheckFrequency.monthly => switch (interval) {
        3 => 'Quarterly',
        6 => 'Half-yearly',
        12 => 'Yearly',
        _ when interval % 12 == 0 => 'Every ${interval ~/ 12} years',
        _ => 'Every $interval months',
      },
  };
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
    this.interval = 1,
    this.pmType,
    this.pointCount = 0,
    this.verifiedAt,
    this.verifiedByName,
    this.assignedTo,
  });

  /// Worker who must do this check (the equipment's assigned worker); null = nobody assigned.
  final String? assignedTo;

  final String id, itemId, equipmentId, plantId, title, equipmentName, equipmentCode;
  final String? description, completedByName, note, pmType, verifiedByName;
  final DateTime dueDate, windowEnd;
  final DateTime? completedAt, verifiedAt;
  final TaskStatus status;
  final CheckFrequency frequency;
  final int interval;

  /// Check points from a PM sheet. Tasks with points are completed point by point, not with one tick.
  final int pointCount;

  bool get isDone => status == TaskStatus.done;
  bool get isPm => pointCount > 0;
  bool get isVerified => verifiedAt != null;
  String get frequencyText => frequencyLabel(frequency, interval);

  /// Pending, past its due day but still inside its completion window.
  bool isOverdue(DateTime today) => status == TaskStatus.pending && dueDate.isBefore(today) && !windowEnd.isBefore(today);

  static const select =
      'id,check_item_id,equipment_id,plant_id,due_date,window_end,status,completed_at,note,verified_at,assigned_to,'
      'check_items(title,description,frequency,interval_count,pm_type,check_points(count)),equipment(name,tag_code),'
      'completer:profiles!check_tasks_completed_by_fkey(name),verifier:profiles!check_tasks_verified_by_fkey(name)';

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
      interval: (item['interval_count'] as num?)?.toInt() ?? 1,
      pmType: item['pm_type'] as String?,
      pointCount: ((item['check_points'] as List?)?.firstOrNull as Json?)?['count'] as int? ?? 0,
      verifiedAt: j['verified_at'] == null ? null : DateTime.parse(j['verified_at'] as String).toLocal(),
      verifiedByName: (j['verifier'] as Json?)?['name'] as String?,
      assignedTo: j['assigned_to'] as String?,
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
        interval: interval,
        pmType: pmType,
        pointCount: pointCount,
        verifiedAt: verifiedAt,
        verifiedByName: verifiedByName,
        assignedTo: assignedTo,
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

/// ○ OK · ⊗ immediate correction · △ abnormal, correction pending (▲ once its finding is resolved).
enum PointResult {
  ok('○', 'OK'),
  corrected('⊗', 'Corrected now'),
  abnormalPending('△', 'Abnormal – pending');

  const PointResult(this.symbol, this.label);
  final String symbol, label;

  String get dbName => this == abnormalPending ? 'abnormal_pending' : name;
  static PointResult? parse(String? v) => PointResult.values.where((r) => r.dbName == v).firstOrNull;
}

/// One row of a PM sheet, with every column the paper sheet has.
class CheckPoint {
  const CheckPoint({
    required this.id,
    required this.position,
    required this.checkPoint,
    this.slNo,
    this.safetyPoint,
    this.keyPoints,
    this.ifNotDone,
    this.checkingMethod,
    this.stdValue,
    this.actionIfNg,
    this.pmRank,
    this.imagePaths = const [],
  });

  final String id, checkPoint;
  final int position;
  final String? slNo, safetyPoint, keyPoints, ifNotDone, checkingMethod, stdValue, actionIfNg, pmRank;
  final List<String> imagePaths;

  static const select = 'id,position,sl_no,check_point,safety_point,key_points,if_not_done,checking_method,std_value,action_if_ng,pm_rank,image_paths';

  factory CheckPoint.fromJson(Json j) => CheckPoint(
        id: j['id'] as String,
        position: (j['position'] as num).toInt(),
        checkPoint: j['check_point'] as String,
        slNo: j['sl_no'] as String?,
        safetyPoint: j['safety_point'] as String?,
        keyPoints: j['key_points'] as String?,
        ifNotDone: j['if_not_done'] as String?,
        checkingMethod: j['checking_method'] as String?,
        stdValue: j['std_value'] as String?,
        actionIfNg: j['action_if_ng'] as String?,
        pmRank: j['pm_rank'] as String?,
        imagePaths: ((j['image_paths'] as List?) ?? const []).cast<String>(),
      );
}

class RecordedResult {
  const RecordedResult({required this.pointId, required this.result, this.note, this.findingId, this.findingResolved = false});
  final String pointId;
  final PointResult result;
  final String? note, findingId;
  final bool findingResolved;

  /// ▲ pending completed: an abnormal point whose correction has since been done.
  bool get pendingCompleted => result == PointResult.abnormalPending && findingResolved;
  String get symbol => pendingCompleted ? '▲' : result.symbol;
  String get label => pendingCompleted ? 'Pending – completed' : result.label;
}

/// Everything the run screen shows for one PM task: the sheet's header block, its points and any results.
class PmTaskDetail {
  const PmTaskDetail({
    required this.task,
    required this.points,
    required this.results,
    this.frequencyText,
    this.sourceTab,
    this.pmRank,
    this.manPower,
    this.timeMinutes,
    this.kanbanNo,
    this.safetyNote,
    this.tools,
    this.imagePaths = const [],
    this.verifyNote,
    this.imageUrls = const {},
  });

  final CheckTask task;
  final List<CheckPoint> points;
  final Map<String, RecordedResult> results; // by point id
  final String? frequencyText, sourceTab, pmRank, manPower, timeMinutes, kanbanNo, safetyNote, tools, verifyNote;
  final List<String> imagePaths;

  /// Signed URLs for every picture path (sheet pictures are in the private `check-sheets` bucket).
  final Map<String, String> imageUrls;
}

final pmTaskDetailProvider = FutureProvider.family<PmTaskDetail, String>((ref, taskId) async {
  final db = ref.watch(supabaseProvider);
  final j = await db
      .from('check_tasks')
      .select('${CheckTask.select},verify_note,'
          'item:check_items!inner(frequency_text,source_tab,pm_rank,man_power,time_minutes,kanban_no,safety_note,tools,image_paths,'
          'check_points(${CheckPoint.select})),'
          'check_point_results(check_point_id,result,note,finding_id,findings(status))')
      .eq('id', taskId)
      .single();
  final item = j['item'] as Json;
  final points = ((item['check_points'] as List?) ?? const []).cast<Json>().map(CheckPoint.fromJson).toList()..sort((a, b) => a.position.compareTo(b.position));
  final results = <String, RecordedResult>{
    for (final r in ((j['check_point_results'] as List?) ?? const []).cast<Json>())
      if (PointResult.parse(r['result'] as String?) != null)
        r['check_point_id'] as String: RecordedResult(
          pointId: r['check_point_id'] as String,
          result: PointResult.parse(r['result'] as String?)!,
          note: r['note'] as String?,
          findingId: r['finding_id'] as String?,
          findingResolved: (r['findings'] as Json?)?['status'] == 'resolved',
        ),
  };
  final itemImages = ((item['image_paths'] as List?) ?? const []).cast<String>();
  final paths = {...itemImages, for (final p in points) ...p.imagePaths}.toList();
  final urls = <String, String>{};
  if (paths.isNotEmpty) {
    try {
      // ignore: deprecated_member_use
      for (final s in await db.storage.from('check-sheets').createSignedUrls(paths, 3600)) {
        urls[s.path] = s.signedUrl;
      }
    } catch (_) {} // pictures are a help, not a blocker (e.g. offline)
  }
  return PmTaskDetail(
    task: CheckTask.fromJson(j),
    points: points,
    results: results,
    frequencyText: item['frequency_text'] as String?,
    sourceTab: item['source_tab'] as String?,
    pmRank: item['pm_rank'] as String?,
    manPower: item['man_power'] as String?,
    timeMinutes: item['time_minutes'] as String?,
    kanbanNo: item['kanban_no'] as String?,
    safetyNote: item['safety_note'] as String?,
    tools: item['tools'] as String?,
    imagePaths: itemImages,
    verifyNote: j['verify_note'] as String?,
    imageUrls: urls,
  );
});

/// Completed PM checks the in-charge has not verified yet (managers / admins).
final awaitingVerificationProvider = FutureProvider<List<CheckTask>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('check_tasks')
      .select(CheckTask.select)
      .eq('status', 'done')
      .isFilter('verified_at', null)
      .order('completed_at', ascending: false)
      .limit(500);
  return rows.map(CheckTask.fromJson).where((t) => t.isPm).toList();
});

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

/// Checks for "My checks": the last 5 weeks plus anything whose window is still open (4-monthly and
/// half-yearly checks stay open for months), up to a week ahead.
final checkTasksProvider = FutureProvider.family<List<CheckTask>, String?>((ref, equipmentId) async {
  final client = ref.watch(supabaseProvider);
  final t = today();
  var q = client
      .from('check_tasks')
      .select(CheckTask.select)
      .or('due_date.gte.${isoDate(t.subtract(const Duration(days: 35)))},window_end.gte.${isoDate(t)}')
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

  /// Submit a PM check: one result per point (+ optional note, photo for △). Works offline.
  Future<SendResult> submitPmTask({
    required String taskId,
    required String equipmentId,
    required Map<String, ({PointResult result, String note, Uint8List? photo})> results,
  }) {
    return ref.read(offlineQueueProvider).submit(QueuedAction(
          id: const Uuid().v4(),
          userId: ref.read(profileProvider).id,
          kind: QueuedKind.taskSubmit,
          payload: {
            'task_id': taskId,
            'equipment_id': equipmentId,
            'results': [
              for (final e in results.entries) {'point_id': e.key, 'result': e.value.result.dbName, 'note': e.value.note.trim()},
            ],
            'photos': {
              for (final e in results.entries)
                if (e.value.photo != null && e.value.result == PointResult.abnormalPending) e.key: base64Encode(e.value.photo!),
            },
          },
        ));
  }

  /// In-charge sign-off of a completed PM check.
  Future<void> verifyTask(String taskId, {String? note}) async {
    await ref.read(supabaseProvider).rpc('verify_check_task', params: {'p_task': taskId, 'p_note': note});
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
