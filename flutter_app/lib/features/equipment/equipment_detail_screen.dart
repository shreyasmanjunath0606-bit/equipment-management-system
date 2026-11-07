import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/equipment_repo.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../checks/my_checks_screen.dart' show taskStatusPill;
import '../findings/finding_tile.dart';
import '../findings/report_finding_sheet.dart';

enum _Tab { timeline, checks, findings, details }

class EquipmentDetailScreen extends ConsumerStatefulWidget {
  const EquipmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends ConsumerState<EquipmentDetailScreen> {
  _Tab _tab = _Tab.timeline;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(equipmentDetailProvider(widget.id));
    Future<void> refresh() async {
      ref.invalidate(equipmentDetailProvider(widget.id));
      ref.invalidate(equipmentEventsProvider(widget.id));
      ref.invalidate(checkTasksProvider(widget.id));
      ref.invalidate(findingsProvider(widget.id));
      await ref.read(equipmentDetailProvider(widget.id).future);
    }

    return PageBody(
      onRefresh: refresh,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: context.palette.muted, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => context.canPop() ? context.pop() : context.go('/equipment'),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Equipment'),
          ),
        ),
        const Gap(Space.sm),
        AsyncBody<EquipmentDetail?>(
          value: detail,
          onRetry: refresh,
          data: (d) => d == null
              ? const Card(child: EmptyState(icon: Icons.search_off_rounded, title: 'Equipment not found', message: 'It may not exist, or you do not have access to its plant.'))
              : _body(context, d),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, EquipmentDetail d) {
    final e = d.equipment;
    final role = ref.watch(profileProvider).role;
    final events = ref.watch(equipmentEventsProvider(e.id));
    final types = ref.watch(statusTypesProvider).value ?? const <StatusType>[];
    final byId = {for (final t in types) t.id: t};
    final latest = events.value?.events.firstOrNull;
    final p = context.palette;
    final wide = isDesktop(context);

    final header = Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(e.name, style: context.text.headlineSmall),
            if (!e.isActive) Pill('Retired', color: p.danger),
          ]),
          const Gap(Space.xs),
          Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              borderRadius: Radii.inputAll,
              onTap: () {
                Clipboard.setData(ClipboardData(text: e.tagCode));
                showToast(context, 'Code ${e.tagCode} copied');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(e.tagCode, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(width: 4),
                  Icon(Icons.copy_rounded, size: 14, color: p.muted),
                ]),
              ),
            ),
            Flexible(child: Text('  ·  ${[d.plantName, d.areaName].whereType<String>().join(' · ')}', style: context.text.bodyMedium?.copyWith(color: p.muted), overflow: TextOverflow.ellipsis)),
          ]),
          const Gap(Space.lg),
          Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusChip(status: latest == null ? null : byId[latest.statusTypeId]),
            if (latest != null) Text('updated ${timeAgo(latest.reportedAt)} by ${latest.reporterName ?? 'unknown'}', style: context.text.bodySmall),
          ]),
          const Gap(Space.xl),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            if (e.isActive)
              FilledButton.icon(onPressed: () => context.push('/equipment/${e.id}/report'), icon: const Icon(Icons.edit_note_rounded, size: 20), label: const Text('Report status')),
            if (e.isActive)
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showReportFindingSheet(context, equipmentId: e.id, equipmentName: e.name);
                  if (ok) {
                    ref.invalidate(findingsProvider(e.id));
                    setState(() => _tab = _Tab.findings);
                  }
                },
                icon: const Icon(Icons.report_gmailerrorred_rounded, size: 20),
                label: const Text('Report problem'),
              ),
            if (role.isManagerOrAdmin)
              OutlinedButton.icon(onPressed: () => context.push('/equipment/${e.id}/qr'), icon: const Icon(Icons.qr_code_2_rounded, size: 20), label: const Text('QR label')),
          ]),
        ]),
      ),
    );

    final details = SectionCard(
      title: 'Details',
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      child: Column(children: [
        for (final (k, v) in [
          ('Code', e.tagCode),
          ('Type', e.type),
          ('Plant', d.plantName),
          ('Area', d.areaName),
          ('Manufacturer', e.manufacturer),
          ('Model', e.model),
          ('Serial no.', e.serialNo),
          ('Installed', e.installDate == null ? null : formatDate(e.installDate!)),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Expanded(child: Text(k, style: context.text.bodyMedium?.copyWith(color: p.muted))),
              Flexible(
                child: Text(v ?? '—', textAlign: TextAlign.right, style: context.text.bodyMedium?.copyWith(fontWeight: v == null ? null : FontWeight.w500, color: v == null ? p.muted : null)),
              ),
            ]),
          ),
      ]),
    );

    final tabs = [_Tab.timeline, _Tab.checks, _Tab.findings, if (!wide) _Tab.details];
    String label(_Tab t) => switch (t) { _Tab.timeline => 'History', _Tab.checks => 'Checks', _Tab.findings => 'Findings', _Tab.details => 'Details' };
    final tab = tabs.contains(_tab) ? _tab : _Tab.timeline;

    final tabBody = switch (tab) {
      _Tab.timeline => _Timeline(id: e.id, byId: byId),
      _Tab.checks => _ChecksTab(id: e.id),
      _Tab.findings => _FindingsTab(id: e.id),
      _Tab.details => details,
    };

    final tabbed = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<_Tab>(
        showSelectedIcon: false,
        segments: [for (final t in tabs) ButtonSegment(value: t, label: Text(label(t)))],
        selected: {tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
      const Gap(Space.lg),
      tabBody,
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const Gap(Space.xl),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 340, child: details),
          const Gap(Space.xl),
          Expanded(child: tabbed),
        ])
      else
        tabbed,
    ]);
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.id, required this.byId});
  final String id;
  final Map<String, StatusType> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return AsyncBody(
      value: ref.watch(equipmentEventsProvider(id)),
      onRetry: () => ref.invalidate(equipmentEventsProvider(id)),
      data: (d) => d.events.isEmpty
          ? const Card(child: EmptyState(icon: Icons.timeline_rounded, title: 'No reports yet', message: "Be the first to report this machine's status."))
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(children: [
                  for (var i = 0; i < d.events.length; i++)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: 18,
                          child: Column(children: [
                            const SizedBox(height: 4),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: byId[d.events[i].statusTypeId]?.color ?? p.muted,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.surface, width: 2),
                              ),
                            ),
                            if (i < d.events.length - 1) Expanded(child: Container(width: 1.5, color: p.border)),
                          ]),
                        ),
                        const Gap(Space.md),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: i < d.events.length - 1 ? Space.xl : 0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Wrap(spacing: Space.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                StatusChip(status: byId[d.events[i].statusTypeId], dense: true),
                                Text(d.events[i].reporterName ?? 'Unknown', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                Text(formatDateTime(d.events[i].reportedAt), style: context.text.bodySmall),
                              ]),
                              if (d.events[i].note != null) ...[
                                const Gap(Space.sm),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                                  decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: Radii.inputAll),
                                  child: Text(d.events[i].note!, style: context.text.bodyMedium),
                                ),
                              ],
                              if (d.photos[d.events[i].photoPath] != null) ...[
                                const Gap(Space.sm),
                                _PhotoThumb(url: d.photos[d.events[i].photoPath]!),
                              ],
                            ]),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Radii.inputAll,
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(Space.lg),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
        ),
      ),
      child: ClipRRect(borderRadius: Radii.inputAll, child: Image.network(url, height: 120, fit: BoxFit.cover)),
    );
  }
}

class _ChecksTab extends ConsumerWidget {
  const _ChecksTab({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return AsyncBody<List<CheckTask>>(
      value: ref.watch(checkTasksProvider(id)),
      onRetry: () => ref.invalidate(checkTasksProvider(id)),
      data: (tasks) {
        if (tasks.isEmpty) {
          return const Card(child: EmptyState(icon: Icons.checklist_rounded, title: 'No scheduled checks', message: 'Checks appear here once a check sheet that includes this machine is uploaded.'));
        }
        final sorted = [...tasks]..sort((a, b) => b.dueDate.compareTo(a.dueDate));
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < sorted.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.border),
              ListTile(
                minTileHeight: 60,
                title: Text(sorted[i].title),
                subtitle: Text('${sorted[i].frequency.label} · due ${formatDayShort(sorted[i].dueDate)}${sorted[i].completedByName != null ? ' · ${sorted[i].completedByName}' : ''}'),
                trailing: taskStatusPill(context, sorted[i]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _FindingsTab extends ConsumerWidget {
  const _FindingsTab({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return AsyncBody<List<Finding>>(
      value: ref.watch(findingsProvider(id)),
      onRetry: () => ref.invalidate(findingsProvider(id)),
      data: (list) => list.isEmpty
          ? const Card(child: EmptyState(icon: Icons.verified_outlined, title: 'No problems reported', message: 'Problems found during checks on this machine will appear here.'))
          : Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  FindingTile(finding: list[i], showEquipment: false),
                ],
              ]),
            ),
    );
  }
}
