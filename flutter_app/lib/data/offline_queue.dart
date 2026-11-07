import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

/// Kinds of work that can be saved while offline and sent later.
enum QueuedKind { statusReport, taskTick, finding }

/// One queued action. Each carries a client id so retries never create duplicates on the server.
class QueuedAction {
  QueuedAction({required this.id, required this.userId, required this.kind, required this.payload, this.photo});

  final String id;
  final String userId;
  final QueuedKind kind;
  final Map<String, dynamic> payload;
  final Uint8List? photo;

  String encode() => jsonEncode({
        'id': id,
        'userId': userId,
        'kind': kind.name,
        'payload': payload,
        if (photo != null) 'photo': base64Encode(photo!),
      });

  static QueuedAction decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return QueuedAction(
      id: j['id'] as String,
      userId: j['userId'] as String,
      kind: QueuedKind.values.byName(j['kind'] as String),
      payload: (j['payload'] as Map).cast<String, dynamic>(),
      photo: j['photo'] == null ? null : base64Decode(j['photo'] as String),
    );
  }
}

enum SendResult { sent, offline, rejected }

bool isNetworkError(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException') ||
      s.contains('XMLHttpRequest error') ||
      s.contains('Connection refused') ||
      s.contains('Network is unreachable') ||
      s.contains('TimeoutException') ||
      s.contains('Failed to fetch');
}

/// Persistent outbox (Hive). Flushes every 30 s and whenever something new is queued.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(SupabaseClient client, this._userId) : _clientOrNull = client {
    _init();
  }

  /// No storage, no network (tests / previews).
  OfflineQueue.disabled()
      : _clientOrNull = null,
        _userId = '';

  static const _boxName = 'outbox';
  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;
  final String _userId;
  Box<String>? _box;
  Timer? _timer;
  bool _flushing = false;
  int _pending = 0;

  int get pending => _pending;

  static Future<void> initStorage() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_boxName);
  }

  Future<void> _init() async {
    _box = Hive.isBoxOpen(_boxName) ? Hive.box<String>(_boxName) : await Hive.openBox<String>(_boxName);
    _recount();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    unawaited(flush());
  }

  void _recount() {
    final n = _box?.values.where((s) => QueuedAction.decode(s).userId == _userId).length ?? 0;
    if (n != _pending) {
      _pending = n;
      notifyListeners();
    }
  }

  /// Try to send now; if offline, keep it for later. Returns what happened.
  Future<SendResult> submit(QueuedAction a) async {
    final r = await _send(a);
    if (r == SendResult.offline) {
      await _box?.put(a.id, a.encode());
      _recount();
    }
    return r;
  }

  Future<int> flush() async {
    final box = _box;
    if (box == null || _flushing || _userId.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final items = box.values.map(QueuedAction.decode).where((a) => a.userId == _userId).toList();
      for (final a in items) {
        final r = await _send(a);
        if (r == SendResult.offline) break;
        await box.delete(a.id); // "rejected" can never succeed (e.g. access removed): drop it
        if (r == SendResult.sent) sent++;
      }
    } finally {
      _flushing = false;
      _recount();
    }
    return sent;
  }

  Future<SendResult> _send(QueuedAction a) async {
    try {
      switch (a.kind) {
        case QueuedKind.statusReport:
          String? photoPath;
          if (a.photo != null) {
            photoPath = '${a.payload['equipment_id']}/${a.id}.jpg';
            try {
              await _client.storage.from('failure-photos').uploadBinary(photoPath, a.photo!, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
            } catch (e) {
              if (isNetworkError(e)) return SendResult.offline;
              photoPath = null; // don't lose the report because of the photo
            }
          }
          await _client.from('status_events').insert({...a.payload, 'client_event_id': a.id, 'photo_path': ?photoPath});
        case QueuedKind.taskTick:
          await _client.from('check_tasks').update({'status': a.payload['status']}).eq('id', a.payload['task_id'] as String);
        case QueuedKind.finding:
          String? photoPath;
          if (a.photo != null) {
            photoPath = '${a.payload['equipment_id']}/finding-${a.id}.jpg';
            try {
              await _client.storage.from('failure-photos').uploadBinary(photoPath, a.photo!, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
            } catch (e) {
              if (isNetworkError(e)) return SendResult.offline;
              photoPath = null;
            }
          }
          await _client.from('findings').upsert({...a.payload, 'client_id': a.id, 'photo_path': ?photoPath}, onConflict: 'client_id', ignoreDuplicates: true);
      }
      return SendResult.sent;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return SendResult.sent; // already delivered earlier
      return isNetworkError(e) ? SendResult.offline : SendResult.rejected;
    } catch (e) {
      return isNetworkError(e) ? SendResult.offline : SendResult.rejected;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final offlineQueueProvider = ChangeNotifierProvider<OfflineQueue>((ref) {
  final profile = ref.watch(profileProvider);
  return OfflineQueue(ref.watch(supabaseProvider), profile.id);
});
