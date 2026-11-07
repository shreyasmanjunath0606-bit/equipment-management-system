import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'session.dart';

/// Active plants visible to the current user (RLS limits to their plants; admins see all).
final plantsProvider = FutureProvider<List<Plant>>((ref) async {
  ref.watch(profileProvider);
  final rows = await ref.watch(supabaseProvider).from('plants').select('id,code,name,timezone,active').eq('active', true).order('name');
  return rows.map(Plant.fromJson).toList();
});

final statusTypesProvider = FutureProvider<List<StatusType>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('status_types')
      .select('id,key,label,color,is_failure,sort_order')
      .eq('active', true)
      .order('sort_order');
  return rows.map(StatusType.fromJson).toList();
});

/// Latest status per active machine, optionally limited to one plant.
final currentStatusProvider = FutureProvider.family<List<CurrentStatus>, String?>((ref, plantId) async {
  var q = ref.watch(supabaseProvider).from('equipment_current_status').select();
  if (plantId != null) q = q.eq('plant_id', plantId);
  final rows = await q.limit(5000);
  return rows.map(CurrentStatus.fromJson).toList();
});

/// Most recent status reports (activity feed).
final recentEventsProvider = FutureProvider.family<List<StatusEvent>, String?>((ref, plantId) async {
  var q = ref
      .watch(supabaseProvider)
      .from('status_events')
      .select('id,equipment_id,status_type_id,note,reported_at,plant_id,equipment(name,tag_code),profiles(name)');
  if (plantId != null) q = q.eq('plant_id', plantId);
  final rows = await q.order('reported_at', ascending: false).limit(12);
  return rows.map(StatusEvent.fromJson).toList();
});

/// Fires whenever a new status event is inserted (RLS limits which ones we hear about).
/// Screens watch this to refresh live, like the web portal's LiveRefresh.
final statusEventsTickProvider = StreamProvider<int>((ref) {
  final client = ref.watch(supabaseProvider);
  final controller = StreamController<int>();
  var n = 0;
  Timer? debounce;
  final channel = client
      .channel('status-events-live')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'status_events',
        callback: (_) {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 500), () => controller.add(++n));
        },
      )
      .subscribe();
  ref.onDispose(() {
    debounce?.cancel();
    client.removeChannel(channel);
    controller.close();
  });
  return controller.stream;
});

/// The user's notifications (newest first), kept live via Realtime.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final profile = ref.watch(profileProvider);
  final client = ref.watch(supabaseProvider);
  if (profile.id.isEmpty) return Stream.value(const []);
  return client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', profile.id)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromJson).toList());
});

final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? const [];
  return list.where((n) => n.unread).length;
});
