import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markRead(WidgetRef ref, List<String> ids) async {
    if (ids.isEmpty) return;
    await ref.read(supabaseProvider).from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final p = context.palette;
    final unread = (list.value ?? const <AppNotification>[]).where((n) => n.unread).map((n) => n.id).toList();

    return PageBody(maxWidth: 720, children: [
      PageHeader(
        title: 'Notifications',
        subtitle: unread.isEmpty ? 'You are all caught up' : '${unread.length} unread',
        actions: [
          if (unread.isNotEmpty) OutlinedButton.icon(onPressed: () => _markRead(ref, unread), icon: const Icon(Icons.done_all_rounded, size: 18), label: const Text('Mark all read')),
        ],
      ),
      AsyncBody<List<AppNotification>>(
        value: list,
        data: (items) => items.isEmpty
            ? const Card(child: EmptyState(icon: Icons.notifications_none_rounded, title: 'No notifications yet', message: 'Failures, recoveries, check reminders and overdue fixes will show up here.'))
            : Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border),
                    _NotificationTile(
                      n: items[i],
                      onTap: () {
                        _markRead(ref, [if (items[i].unread) items[i].id]);
                        final n = items[i];
                        if (n.kind == 'check_due' || n.kind == 'check_reminder') {
                          context.go('/checks');
                        } else if (n.kind == 'finding_overdue') {
                          context.go('/findings');
                        } else if (n.equipmentId != null) {
                          context.push('/equipment/${n.equipmentId}');
                        }
                      },
                    ),
                  ],
                ]),
              ),
      ),
    ]);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, tone) = switch (n.kind) {
      'failure' => (Icons.warning_amber_rounded, Tone.danger),
      'recovery' => (Icons.check_circle_outline_rounded, Tone.success),
      'finding_overdue' => (Icons.schedule_rounded, Tone.danger),
      'check_reminder' => (Icons.event_rounded, Tone.primary),
      _ => (Icons.checklist_rounded, Tone.primary),
    };
    final (fg, bg) = tone.colors(p);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.unread ? p.primarySoft.withValues(alpha: 0.45) : null,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 19, color: fg)),
          const Gap(Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.message, style: context.text.bodyMedium?.copyWith(fontWeight: n.unread ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(height: 2),
              Text(timeAgo(n.createdAt), style: context.text.bodySmall),
            ]),
          ),
          if (n.unread) Padding(padding: const EdgeInsets.only(top: 6, left: Space.sm), child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle))),
        ]),
      ),
    );
  }
}
