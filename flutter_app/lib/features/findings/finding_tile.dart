import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';

/// Pill describing a finding's state (Open / Fix by … / Overdue / Solved).
Widget findingStatusPill(BuildContext context, Finding f) {
  final p = context.palette;
  final now = DateTime.now();
  return switch (f.status) {
    FindingStatus.resolved => Pill('Solved', color: p.success, icon: Icons.check_rounded),
    FindingStatus.open => Pill('Open', color: p.warning),
    FindingStatus.scheduled => f.isOverdue(now) ? Pill('Overdue', color: p.danger, icon: Icons.schedule_rounded) : Pill('Fix by ${formatDayShort(f.scheduledFor!)}', color: p.primary),
  };
}

class FindingTile extends ConsumerWidget {
  const FindingTile({super.key, required this.finding, this.showEquipment = true, this.onChanged});
  final Finding finding;
  final bool showEquipment;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = finding;
    final p = context.palette;
    final open = f.status != FindingStatus.resolved;
    final lines = <String>[
      'Reported ${timeAgo(f.reportedAt)} by ${f.reporterName ?? 'someone'}',
      if (f.status == FindingStatus.scheduled && f.scheduledFor != null) 'Fix scheduled for ${formatDateTime(f.scheduledFor!)}',
      if (f.status == FindingStatus.resolved && f.resolvedAt != null) 'Solved ${timeAgo(f.resolvedAt)}${f.resolverName != null ? ' by ${f.resolverName}' : ''}',
    ];
    return InkWell(
      onTap: open ? () => _showActions(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: open ? (f.isOverdue(DateTime.now()) ? p.dangerSoft : p.warningSoft) : p.successSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(open ? Icons.report_problem_outlined : Icons.task_alt_rounded, size: 18, color: open ? (f.isOverdue(DateTime.now()) ? p.danger : p.warning) : p.success),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showEquipment && f.equipmentName != null)
                Text('${f.equipmentName} · ${f.equipmentCode ?? ''}', style: context.text.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(f.description, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: Space.xs),
              findingStatusPill(context, f),
              const SizedBox(height: Space.xs),
              for (final l in lines) Text(l, style: context.text.bodySmall),
              if (f.resolutionNote != null && f.resolutionNote!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: Space.xs),
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                  decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: Radii.inputAll),
                  child: Text(f.resolutionNote!, style: context.text.bodySmall?.copyWith(color: p.foreground)),
                ),
            ]),
          ),
          if (open) Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(finding.description, style: ctx.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          ListTile(leading: const Icon(Icons.task_alt_rounded), title: const Text('Mark as solved'), onTap: () => Navigator.pop(ctx, 'resolve')),
          ListTile(leading: const Icon(Icons.schedule_rounded), title: const Text('Change fix time'), onTap: () => Navigator.pop(ctx, 'reschedule')),
          const SizedBox(height: Space.sm),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    final repo = ref.read(checksRepositoryProvider);
    try {
      if (action == 'resolve') {
        final note = await _askNote(context);
        if (note == null) return;
        await repo.updateFinding(finding.id, status: FindingStatus.resolved, resolutionNote: note.isEmpty ? null : note);
        if (context.mounted) showToast(context, 'Marked as solved');
      } else {
        final now = DateTime.now();
        final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)), initialDate: now);
        if (d == null || !context.mounted) return;
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
        if (t == null) return;
        await repo.updateFinding(finding.id, status: FindingStatus.scheduled, scheduledFor: DateTime(d.year, d.month, d.day, t.hour, t.minute));
        if (context.mounted) showToast(context, 'Fix time updated');
      }
      ref.invalidate(findingsProvider);
      ref.invalidate(findingStatsProvider);
      onChanged?.call();
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not save — check your connection');
    }
  }

  Future<String?> _askNote(BuildContext context) {
    final c = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('What was done?', style: ctx.text.titleMedium),
              const SizedBox(height: Space.md),
              TextField(
                controller: c,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Optional, e.g. Replaced the seal'),
              ),
              const SizedBox(height: Space.lg),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Mark as solved')),
            ]),
          ),
        ),
      ),
    );
  }
}
