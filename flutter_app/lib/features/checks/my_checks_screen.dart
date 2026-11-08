import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/offline_queue.dart';
import '../../data/session.dart';
import '../findings/report_finding_sheet.dart';
import 'progress_ring.dart';

enum ChecksTab { today, overdue, upcoming, verify }

/// Worker checklist: today's checks grouped by equipment, overdue ones still in their window,
/// and what's coming up this week. Tick or swipe to complete; report problems inline.
class MyChecksScreen extends ConsumerStatefulWidget {
  const MyChecksScreen({super.key, this.initialTab = ChecksTab.today});
  final ChecksTab initialTab;

  @override
  ConsumerState<MyChecksScreen> createState() => _MyChecksScreenState();
}

class _MyChecksScreenState extends ConsumerState<MyChecksScreen> {
  /// Null until the user picks a tab: workers start on Today, supervisors on Verify.
  ChecksTab? _picked;

  /// Optimistic local state while a tick is being saved.
  final Map<String, TaskStatus> _pending = {};

  List<CheckTask> _apply(List<CheckTask> tasks) => [
        for (final t in tasks)
          _pending.containsKey(t.id)
              ? (_pending[t.id] == TaskStatus.done ? t.copyWith(status: TaskStatus.done, completedAt: DateTime.now()) : t.copyWith(status: TaskStatus.pending, clearCompletion: true))
              : t,
      ];

  Future<void> _toggle(CheckTask t, {bool fromSwipe = false}) async {
    if (t.isPm) {
      // PM sheets are completed point by point on their own screen.
      await context.push('/checks/task/${t.id}');
      return;
    }
    final done = !t.isDone;
    HapticFeedback.selectionClick();
    setState(() => _pending[t.id] = done ? TaskStatus.done : TaskStatus.pending);
    final result = await ref.read(checksRepositoryProvider).setTaskDone(t.id, done);
    if (!mounted) return;
    switch (result) {
      case SendResult.sent:
        if (done) {
          showToast(context, '“${t.title}” done', action: SnackBarAction(label: 'Undo', onPressed: () => _toggle(t.copyWith(status: TaskStatus.done))));
        }
        ref.invalidate(checkTasksProvider);
        await ref.read(checkTasksProvider(null).future).catchError((_) => <CheckTask>[]);
        if (mounted) setState(() => _pending.remove(t.id));
      case SendResult.offline:
        // Keep the optimistic tick; it syncs automatically when back online.
        showToast(context, 'Saved on this device — will sync when you are back online');
      case SendResult.rejected:
        setState(() => _pending.remove(t.id));
        showToast(context, 'Could not save this check. It may have been closed already.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(checkTasksProvider(null));
    // Managers and admins supervise: they see every check read-only and verify; only workers complete checks.
    final canVerify = ref.watch(profileProvider).role.isManagerOrAdmin;
    final tab = _picked ?? (canVerify && widget.initialTab == ChecksTab.today ? ChecksTab.verify : widget.initialTab);
    final toVerify = canVerify ? (ref.watch(awaitingVerificationProvider).value ?? const <CheckTask>[]) : const <CheckTask>[];
    Future<void> refresh() async {
      ref.invalidate(awaitingVerificationProvider);
      ref.invalidate(checkTasksProvider(null));
      await ref.read(checkTasksProvider(null).future);
    }

    final t0 = today();
    return PageBody(
      maxWidth: 880,
      onRefresh: refresh,
      children: [
        AsyncBody<List<CheckTask>>(
          value: async,
          onRetry: refresh,
          loading: const _ChecksSkeleton(),
          data: (raw) {
            final all = _apply(raw);
            final todays = all.where((t) => t.dueDate == t0 && t.status != TaskStatus.missed).toList();
            final overdue = all.where((t) => t.isOverdue(t0)).toList();
            final upcoming = all.where((t) => t.dueDate.isAfter(t0)).toList();
            final doneToday = todays.where((t) => t.isDone).length;

            final list = switch (tab) {
              ChecksTab.today => todays,
              ChecksTab.overdue => overdue,
              ChecksTab.upcoming => upcoming,
              ChecksTab.verify => toVerify,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: canVerify ? 'Checks' : 'My checks',
                  subtitle: canVerify
                      ? '${DateFormat('EEEE, d MMMM').format(t0)} · workers complete checks, you verify them'
                      : DateFormat('EEEE, d MMMM').format(t0),
                ),
                _SummaryCard(done: doneToday, total: todays.length, overdue: overdue.length),
                const Gap(Space.xl),
                _Tabs(
                  tab: tab,
                  tabs: [ChecksTab.today, ChecksTab.overdue, ChecksTab.upcoming, if (canVerify) ChecksTab.verify],
                  counts: {ChecksTab.today: todays.length - doneToday, ChecksTab.overdue: overdue.length, ChecksTab.upcoming: upcoming.length, ChecksTab.verify: toVerify.length},
                  onChanged: (t) => setState(() => _picked = t),
                ),
                const Gap(Space.lg),
                if (list.isEmpty)
                  Card(
                    child: switch (tab) {
                      ChecksTab.today => EmptyState(
                          icon: Icons.task_alt_rounded,
                          title: todays.isEmpty ? 'No checks today' : 'All done for today 🎉',
                          message: todays.isEmpty ? 'Nothing is scheduled for today. Enjoy the calm.' : 'Every check scheduled for today is complete.',
                        ),
                      ChecksTab.overdue => const EmptyState(icon: Icons.verified_outlined, title: 'Nothing overdue', message: 'Weekly and monthly checks that slip past their day show up here until their window closes.'),
                      ChecksTab.upcoming => const EmptyState(icon: Icons.event_available_outlined, title: 'Nothing coming up', message: 'Checks for the next 7 days will appear here.'),
                      ChecksTab.verify => const EmptyState(icon: Icons.verified_outlined, title: 'Nothing to verify', message: 'PM check sheets submitted by workers appear here for your in-charge sign-off.'),
                    },
                  )
                else if (tab == ChecksTab.upcoming)
                  ..._byDay(context, upcoming)
                else if (tab == ChecksTab.verify)
                  ..._byEquipment(list, readOnly: true)
                else
                  ..._byEquipment(list, readOnly: canVerify),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _byEquipment(List<CheckTask> tasks, {required bool readOnly}) {
    final groups = <String, List<CheckTask>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.equipmentId, () => []).add(t);
    }
    // Unfinished equipment first, then alphabetical.
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final da = groups[a]!.every((t) => t.isDone), db = groups[b]!.every((t) => t.isDone);
        if (da != db) return da ? 1 : -1;
        return groups[a]!.first.equipmentName.compareTo(groups[b]!.first.equipmentName);
      });
    return [
      for (final k in keys) ...[
        _EquipmentGroup(tasks: groups[k]!, onToggle: readOnly ? null : _toggle),
        const Gap(Space.lg),
      ],
    ];
  }

  List<Widget> _byDay(BuildContext context, List<CheckTask> tasks) {
    final days = <DateTime, List<CheckTask>>{};
    for (final t in tasks) {
      days.putIfAbsent(t.dueDate, () => []).add(t);
    }
    final fmt = DateFormat('EEEE, d MMM');
    return [
      for (final d in days.keys.toList()..sort()) ...[
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text(
            d.difference(today()).inDays == 1 ? 'Tomorrow' : fmt.format(d),
            style: context.text.labelSmall,
          ),
        ),
        ..._byEquipment(days[d]!, readOnly: true),
      ],
    ];
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.done, required this.total, required this.overdue});
  final int done, total, overdue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final left = total - done;
    final value = total == 0 ? 0.0 : done / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(children: [
          ProgressRing(value: value, size: 64, stroke: 7, color: total > 0 && left == 0 ? p.success : p.primary, label: total == 0 ? '—' : '${(value * 100).round()}%'),
          const Gap(Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                total == 0 ? 'No checks scheduled today' : (left == 0 ? 'All $total checks done' : '$left of $total checks left today'),
                style: context.text.titleMedium,
              ),
              const SizedBox(height: Space.xs),
              Text(
                overdue > 0 ? '$overdue overdue from earlier this week' : 'You are up to date',
                style: context.text.bodySmall?.copyWith(color: overdue > 0 ? p.warning : null, fontWeight: overdue > 0 ? FontWeight.w600 : null),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.tabs, required this.counts, required this.onChanged});
  final ChecksTab tab;
  final List<ChecksTab> tabs;
  final Map<ChecksTab, int> counts;
  final ValueChanged<ChecksTab> onChanged;

  @override
  Widget build(BuildContext context) {
    String label(ChecksTab t) => switch (t) { ChecksTab.today => 'Today', ChecksTab.overdue => 'Overdue', ChecksTab.upcoming => 'Upcoming', ChecksTab.verify => 'Verify' };
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ChecksTab>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(minimumSize: const Size(0, 44)),
        segments: [
          for (final t in tabs)
            ButtonSegment(
              value: t,
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label(t)),
                if ((counts[t] ?? 0) > 0) ...[
                  const SizedBox(width: 6),
                  _CountBadge(count: counts[t]!, warn: t == ChecksTab.overdue),
                ],
              ]),
            ),
        ],
        selected: {tab},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.warn = false});
  final int count;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: warn ? p.warning : p.surfaceMuted, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: warn ? Colors.white : p.muted)),
    );
  }
}

class _EquipmentGroup extends StatelessWidget {
  const _EquipmentGroup({required this.tasks, this.onToggle});
  final List<CheckTask> tasks;
  final Future<void> Function(CheckTask, {bool fromSwipe})? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = tasks.first;
    final done = tasks.where((t) => t.isDone).length;
    final sorted = [...tasks]..sort((a, b) => a.isDone == b.isDone ? a.title.compareTo(b.title) : (a.isDone ? 1 : -1));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/equipment/${first.equipmentId}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.precision_manufacturing_rounded, size: 19, color: p.primary),
                ),
                const Gap(Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(first.equipmentName, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(first.equipmentCode, style: context.text.bodySmall?.copyWith(fontSize: 11, letterSpacing: 0.4, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
                if (onToggle != null) ...[
                  Text('$done/${tasks.length}', style: context.text.labelMedium),
                  const Gap(Space.sm),
                  ProgressRing(value: done / tasks.length, size: 26, stroke: 3.5, color: done == tasks.length ? p.success : p.primary),
                ],
              ]),
            ),
          ),
          Divider(height: 1, color: p.border),
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: p.border),
            _CheckTile(task: sorted[i], onToggle: onToggle),
          ],
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.task, this.onToggle});
  final CheckTask task;
  final Future<void> Function(CheckTask, {bool fromSwipe})? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = task;
    final overdue = t.isOverdue(today());
    final meta = <String>[
      t.frequencyText,
      if (t.isPm) '${t.pointCount} points${t.pmType != null ? ' · ${t.pmType!.trim().toLowerCase()}' : ''}',
      if (overdue) 'due ${formatDayShort(t.dueDate)} · until ${formatDayShort(t.windowEnd)}',
      if (t.isDone && t.completedAt != null) 'done ${DateFormat.Hm().format(t.completedAt!)}${t.completedByName != null ? ' by ${t.completedByName}' : ''}',
    ];

    final tile = InkWell(
      onTap: t.isPm ? () => context.push('/checks/task/${t.id}') : (onToggle == null ? null : () => onToggle!(t)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, Space.sm),
          child: Row(children: [
            if (onToggle != null || (t.isPm && t.isDone))
              _CheckCircle(done: t.isDone)
            else
              Icon(t.isPm ? Icons.fact_check_outlined : Icons.schedule_rounded, size: 22, color: p.muted),
            const Gap(Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: context.text.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w500,
                    color: t.isDone ? p.muted : p.foreground,
                    decoration: t.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: p.muted,
                  ),
                  child: Text(t.title),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  if (overdue) ...[Icon(Icons.error_outline_rounded, size: 13, color: p.warning), const SizedBox(width: 3)],
                  Flexible(
                    child: Text(
                      meta.join(' · '),
                      style: context.text.bodySmall?.copyWith(color: overdue ? p.warning : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                if (t.description != null && !t.isDone) ...[
                  const SizedBox(height: 2),
                  Text(t.description!, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (t.isPm && t.isDone)
              Padding(
                padding: const EdgeInsets.only(left: Space.xs),
                child: t.isVerified ? Pill('Verified', color: p.success, icon: Icons.verified_rounded) : Pill('To verify', color: p.primary),
              ),
            if (t.isPm)
              Icon(Icons.chevron_right_rounded, color: p.muted)
            else
              IconButton(
                tooltip: 'Report a problem',
                icon: Icon(Icons.report_gmailerrorred_rounded, color: p.muted, size: 22),
                onPressed: () async {
                  final ok = await showReportFindingSheet(context, equipmentId: t.equipmentId, equipmentName: t.equipmentName, checkTaskId: t.id, checkTitle: t.title);
                  if (ok && context.mounted) showToast(context, 'Finding saved');
                },
              ),
          ]),
        ),
      ),
    );

    if (onToggle == null || t.isDone || t.isPm) return tile;
    return Dismissible(
      key: ValueKey('swipe-${t.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onToggle!(t, fromSwipe: true);
        return false; // the list re-renders it as done
      },
      background: Container(
        color: p.success,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Space.xl),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, color: Colors.white),
          SizedBox(width: Space.sm),
          Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
      child: tile,
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? p.success : Colors.transparent,
        border: Border.all(color: done ? p.success : p.muted.withValues(alpha: 0.6), width: 2),
      ),
      child: done ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
    );
  }
}

class _ChecksSkeleton extends StatelessWidget {
  const _ChecksSkeleton();
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SkeletonBox(height: 28, width: 180),
        Gap(Space.sm),
        SkeletonBox(height: 16, width: 140),
        Gap(Space.xl),
        SkeletonBox(height: 96, radius: Radii.card),
        Gap(Space.xl),
        SkeletonBox(height: 44),
        Gap(Space.lg),
        SkeletonBox(height: 220, radius: Radii.card),
      ]);
}

/// Small helper used by other screens to show a status pill for a task.
Widget taskStatusPill(BuildContext context, CheckTask t) {
  final p = context.palette;
  return switch (t.status) {
    TaskStatus.done => Pill('Done', color: p.success, icon: Icons.check_rounded),
    TaskStatus.missed => Pill('Missed', color: p.danger),
    TaskStatus.pending => t.isOverdue(today()) ? Pill('Overdue', color: p.warning) : const Pill('To do'),
  };
}
