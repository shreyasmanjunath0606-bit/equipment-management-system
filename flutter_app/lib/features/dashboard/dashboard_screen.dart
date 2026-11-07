import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/plant_picker.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'checks_charts_section.dart';

/// Manager / admin overview. Mirrors the web dashboard, plus the checks & findings charts.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.plantId});
  final String? plantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live refresh when new reports arrive.
    ref.listen(statusEventsTickProvider, (_, _) {
      ref.invalidate(currentStatusProvider(plantId));
      ref.invalidate(recentEventsProvider(plantId));
    });

    final plants = ref.watch(plantsProvider);
    final types = ref.watch(statusTypesProvider);
    final current = ref.watch(currentStatusProvider(plantId));
    final recent = ref.watch(recentEventsProvider(plantId));

    Future<void> refresh() async {
      ref.invalidate(currentStatusProvider(plantId));
      ref.invalidate(recentEventsProvider(plantId));
      ref.invalidate(checkStatsProvider);
      ref.invalidate(findingStatsProvider);
      await ref.read(currentStatusProvider(plantId).future);
    }

    final plantList = plants.value ?? const <Plant>[];
    final plantName = plantId == null ? null : plantList.where((p) => p.id == plantId).firstOrNull?.name;

    return PageBody(
      onRefresh: refresh,
      children: [
        PageHeader(
          title: 'Dashboard',
          subtitle: plantName != null ? 'Live status for $plantName' : 'Live equipment status across your plants',
          actions: [
            if (plantList.length > 1)
              PlantPicker(
                plants: plantList,
                value: plantId,
                onChanged: (id) => context.go(id == null ? '/dashboard' : '/dashboard?plant=$id'),
              ),
          ],
        ),
        AsyncBody<List<CurrentStatus>>(
          value: current,
          onRetry: refresh,
          loading: const _DashboardSkeleton(),
          data: (rows) => _Overview(
            rows: rows,
            types: types.value ?? const [],
            plants: plantList,
            plantId: plantId,
            recent: recent.value ?? const [],
          ),
        ),
        const Gap(Space.xl),
        ChecksChartsSection(plantId: plantId),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.rows, required this.types, required this.plants, required this.plantId, required this.recent});

  final List<CurrentStatus> rows;
  final List<StatusType> types;
  final List<Plant> plants;
  final String? plantId;
  final List<StatusEvent> recent;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final t in types) t.id: t};
    bool failing(CurrentStatus r) => r.statusTypeId != null && (byId[r.statusTypeId]?.isFailure ?? false);

    final down = rows.where(failing).toList()..sort((a, b) => (a.reportedAt ?? DateTime(0)).compareTo(b.reportedAt ?? DateTime(0)));
    final unknown = rows.where((r) => r.statusTypeId == null).length;
    final operational = rows.length - down.length - unknown;
    final availability = rows.isEmpty ? 0 : (operational * 100 / rows.length).round();

    List<({StatusType? status, int count})> segmentsFor(Iterable<CurrentStatus> list) {
      final counts = <String, int>{};
      var none = 0;
      for (final r in list) {
        if (r.statusTypeId == null) {
          none++;
        } else {
          counts[r.statusTypeId!] = (counts[r.statusTypeId!] ?? 0) + 1;
        }
      }
      return [
        for (final t in types) (status: t, count: counts[t.id] ?? 0),
        (status: null, count: none),
      ];
    }

    final segments = segmentsFor(rows);
    final wide = isDesktop(context);
    final plantCount = plantId != null ? 1 : plants.length;

    final kpis = ResponsiveGrid(
      minItemWidth: 160,
      spacing: Space.md,
      children: [
        KpiTile(label: 'Total equipment', value: '${rows.length}', hint: '$plantCount plant${plantCount == 1 ? '' : 's'}', icon: Icons.precision_manufacturing_rounded, onTap: () => context.go('/equipment')),
        KpiTile(label: 'Availability', value: '$availability%', hint: '$operational operational', icon: Icons.speed_rounded, tone: Tone.success),
        KpiTile(
          label: 'Down / failing',
          value: '${down.length}',
          hint: down.isEmpty ? 'All clear' : 'Oldest ${timeAgo(down.first.reportedAt)}',
          icon: Icons.warning_amber_rounded,
          tone: Tone.danger,
          onTap: () => context.go('/equipment?status=failing'),
        ),
        KpiTile(label: 'No status yet', value: '$unknown', hint: 'Never reported', icon: Icons.help_outline_rounded, tone: Tone.muted),
      ],
    );

    final distribution = SectionCard(
      title: 'Status distribution',
      subtitle: 'Tap a status to see that equipment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusBar(segments: segments, height: 14),
          const Gap(Space.lg),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final s in segments.where((s) => s.count > 0 || s.status != null))
                _LegendLink(
                  color: s.status?.color ?? context.palette.border,
                  label: s.status?.label ?? 'No status',
                  count: s.count,
                  onTap: () => context.go('/equipment?status=${s.status?.id ?? 'none'}${plantId != null ? '&plant=$plantId' : ''}'),
                ),
            ],
          ),
        ],
      ),
    );

    final plantRows = plantId != null
        ? const <({Plant plant, int total, int down, List<({StatusType? status, int count})> segs})>[]
        : (plants
            .map((p) {
              final list = rows.where((r) => r.plantId == p.id).toList();
              return (plant: p, total: list.length, down: list.where(failing).length, segs: segmentsFor(list));
            })
            .where((x) => x.total > 0)
            .toList()
          ..sort((a, b) => b.down.compareTo(a.down)));

    final byPlant = SectionCard(
      title: 'By plant',
      subtitle: plantId != null ? 'Filtered to one plant' : 'Sorted by equipment down',
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
      child: plantRows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(plantId != null ? 'Clear the plant filter to compare plants.' : 'No equipment yet.', style: context.text.bodySmall),
            )
          : Column(
              children: [
                for (final r in plantRows)
                  InkWell(
                    onTap: () => context.go('/dashboard?plant=${r.plant.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(child: Text(r.plant.name, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
                            Text(
                              r.down > 0 ? '${r.down} down · ${r.total}' : 'All up · ${r.total}',
                              style: context.text.bodySmall?.copyWith(color: r.down > 0 ? context.palette.danger : null, fontWeight: r.down > 0 ? FontWeight.w600 : null),
                            ),
                          ]),
                          const Gap(Space.sm),
                          StatusBar(segments: r.segs, height: 8),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );

    final attention = SectionCard(
      title: 'Needs attention',
      subtitle: 'Failing equipment, longest-down first',
      trailing: down.isEmpty ? null : Pill('${down.length}', color: context.palette.danger),
      padding: EdgeInsets.zero,
      child: down.isEmpty
          ? const EmptyState(icon: Icons.celebration_outlined, title: 'Nothing is down right now', message: 'All reported equipment is operational.', compact: true)
          : Column(
              children: [
                const Gap(Space.sm),
                for (final r in down.take(8))
                  ListTile(
                    minTileHeight: 60,
                    onTap: () => context.push('/equipment/${r.equipmentId}'),
                    title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [r.tagCode, if (plantId == null) plants.where((p) => p.id == r.plantId).firstOrNull?.name, timeAgo(r.reportedAt)].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: StatusChip(status: byId[r.statusTypeId], dense: true),
                  ),
                if (down.length > 8)
                  TextButton(onPressed: () => context.go('/equipment?status=failing'), child: Text('View all ${down.length}')),
                const Gap(Space.sm),
              ],
            ),
    );

    final activity = SectionCard(
      title: 'Recent activity',
      trailing: TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: Space.sm), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () => context.go('/history'),
        child: const Text('Full history'),
      ),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
      child: recent.isEmpty
          ? const EmptyState(icon: Icons.timeline_rounded, title: 'No reports yet', compact: true)
          : Column(
              children: [
                for (final e in recent.take(wide ? 8 : 5))
                  InkWell(
                    onTap: () => context.push('/equipment/${e.equipmentId}'),
                    borderRadius: Radii.inputAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: byId[e.statusTypeId]?.color ?? context.palette.muted, shape: BoxShape.circle),
                            ),
                          ),
                          const Gap(Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.equipmentName ?? 'Equipment', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text('${byId[e.statusTypeId]?.label ?? 'Status'} · ${e.reporterName ?? 'Unknown'}', style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Text(timeAgo(e.reportedAt), style: context.text.bodySmall?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        kpis,
        const Gap(Space.lg),
        if (wide) ...[
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: distribution),
              const Gap(Space.lg),
              Expanded(flex: 2, child: byPlant),
            ]),
          ),
          const Gap(Space.lg),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: attention),
            const Gap(Space.lg),
            Expanded(flex: 2, child: activity),
          ]),
        ] else ...[
          attention,
          const Gap(Space.lg),
          distribution,
          if (plantRows.isNotEmpty) ...[const Gap(Space.lg), byPlant],
          const Gap(Space.lg),
          activity,
        ],
      ],
    );
  }
}

/// Compact tappable legend entry: ● Running 10
class _LegendLink extends StatelessWidget {
  const _LegendLink({required this.color, required this.label, required this.count, required this.onTap});
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.inputAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: context.text.bodySmall?.copyWith(color: context.palette.foreground)),
          const SizedBox(width: 4),
          Text('$count', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: context.palette.foreground)),
        ]),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(minItemWidth: 200, spacing: Space.md, children: List.generate(4, (_) => const SkeletonBox(height: 112, radius: Radii.card))),
        const Gap(Space.lg),
        const SkeletonBox(height: 200, radius: Radii.card),
        const Gap(Space.lg),
        const SkeletonBox(height: 260, radius: Radii.card),
      ],
    );
  }
}
