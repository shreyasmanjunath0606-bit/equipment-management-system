import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/equipment_repo.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _pageSize = 30;

class EquipmentListScreen extends ConsumerStatefulWidget {
  const EquipmentListScreen({super.key, this.initialPlant, this.initialStatus, this.initialQuery});
  final String? initialPlant, initialStatus, initialQuery;

  @override
  ConsumerState<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends ConsumerState<EquipmentListScreen> {
  late final _search = TextEditingController(text: widget.initialQuery ?? '');
  late String _q = widget.initialQuery ?? '';
  late String? _plant = widget.initialPlant;
  late String? _status = widget.initialStatus;
  int _limit = _pageSize;
  Timer? _debounce;

  @override
  void didUpdateWidget(EquipmentListScreen old) {
    super.didUpdateWidget(old);
    // Links like /equipment?status=failing from the dashboard re-use this screen.
    if (old.initialStatus != widget.initialStatus || old.initialPlant != widget.initialPlant) {
      setState(() {
        _status = widget.initialStatus;
        _plant = widget.initialPlant;
        _limit = _pageSize;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() {
          _q = v;
          _limit = _pageSize;
        }));
  }

  Future<void> _openFilters(List<Plant> plants, List<StatusType> types) async {
    final result = await showModalBottomSheet<({String? plant, String? status})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(plants: plants, types: types, plant: _plant, status: _status),
    );
    if (result != null) {
      setState(() {
        _plant = result.plant;
        _status = result.status;
        _limit = _pageSize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = (q: _q, plantId: _plant, status: _status, limit: _limit);
    final list = ref.watch(equipmentListProvider(query));
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final types = ref.watch(statusTypesProvider).value ?? const <StatusType>[];
    final typeById = {for (final t in types) t.id: t};
    final plantById = {for (final p in plants) p.id: p};
    final p = context.palette;

    String statusLabel(String s) => switch (s) { 'none' => 'No status yet', 'failing' => 'Failing (any)', _ => typeById[s]?.label ?? 'Status' };
    final chips = <(String, VoidCallback)>[
      if (_plant != null) (plantById[_plant]?.name ?? 'Plant', () => setState(() => _plant = null)),
      if (_status != null) (statusLabel(_status!), () => setState(() => _status = null)),
    ];
    final filterCount = chips.length;

    Future<void> refresh() async {
      ref.invalidate(equipmentListProvider);
      await ref.read(equipmentListProvider(query).future);
    }

    return PageBody(
      maxWidth: 960,
      onRefresh: refresh,
      children: [
        PageHeader(
          title: 'Equipment',
          subtitle: 'Find a machine by name or code and report its status.',
          // Phones already have a Scan tab in the bottom bar.
          actions: [
            if (isDesktop(context))
              OutlinedButton.icon(onPressed: () => context.go('/scan'), icon: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('Scan QR')),
          ],
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name or code…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                        },
                      ),
              ),
            ),
          ),
          const Gap(Space.sm),
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () => _openFilters(plants, types),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.md), backgroundColor: filterCount > 0 ? p.primarySoft : p.surface),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.tune_rounded, size: 20, color: filterCount > 0 ? p.primary : p.muted),
                if (isWide(context) || filterCount > 0) ...[
                  const SizedBox(width: Space.sm),
                  Text(filterCount > 0 ? 'Filters · $filterCount' : 'Filters', style: TextStyle(color: filterCount > 0 ? p.primary : p.foreground)),
                ],
              ]),
            ),
          ),
        ]),
        if (chips.isNotEmpty) ...[
          const Gap(Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (label, onRemove) in chips) InputChip(label: Text(label), onDeleted: onRemove, deleteIcon: const Icon(Icons.close_rounded, size: 16)),
            TextButton(onPressed: () => setState(() => _plant = _status = null), child: const Text('Clear all')),
          ]),
        ],
        const Gap(Space.lg),
        AsyncBody<({List<CurrentStatus> rows, int total})>(
          value: list,
          onRetry: refresh,
          data: (d) {
            if (d.rows.isEmpty) {
              return Card(
                child: EmptyState(
                  icon: Icons.precision_manufacturing_outlined,
                  title: 'No equipment found',
                  message: plants.isEmpty ? 'You are not assigned to any plant yet. Ask an administrator for access.' : 'Try a different search or clear the filters.',
                ),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
                child: Text('${d.total} machine${d.total == 1 ? '' : 's'}', style: context.text.labelMedium),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < d.rows.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border),
                    _EquipmentRow(row: d.rows[i], status: typeById[d.rows[i].statusTypeId], plantName: plants.length > 1 ? plantById[d.rows[i].plantId]?.name : null),
                  ],
                ]),
              ),
              if (d.rows.length < d.total) ...[
                const Gap(Space.lg),
                Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _limit += _pageSize),
                    child: Text('Show more (${d.total - d.rows.length} left)'),
                  ),
                ),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({required this.row, this.status, this.plantName});
  final CurrentStatus row;
  final StatusType? status;
  final String? plantName;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final meta = [row.tagCode, ?plantName, if (row.reportedAt != null) timeAgo(row.reportedAt)].join(' · ');
    return InkWell(
      onTap: () => context.push('/equipment/${row.equipmentId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(meta, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!isWide(context)) ...[const SizedBox(height: Space.sm), StatusChip(status: status, dense: true)],
            ]),
          ),
          if (isWide(context)) ...[StatusChip(status: status), const Gap(Space.lg)],
          if (isWide(context))
            OutlinedButton.icon(
              onPressed: () => context.push('/equipment/${row.equipmentId}/report'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Report'),
            )
          else
            IconButton.filledTonal(
              tooltip: 'Report status',
              onPressed: () => context.push('/equipment/${row.equipmentId}/report'),
              style: IconButton.styleFrom(backgroundColor: p.primarySoft, foregroundColor: p.primary),
              icon: const Icon(Icons.edit_note_rounded),
            ),
        ]),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.plants, required this.types, this.plant, this.status});
  final List<Plant> plants;
  final List<StatusType> types;
  final String? plant, status;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _plant = widget.plant;
  late String? _status = widget.status;

  @override
  Widget build(BuildContext context) {
    Widget section(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: chips),
          ]),
        );
    ChoiceChip choice(String label, bool selected, VoidCallback onTap, {Color? dot}) => ChoiceChip(
          label: Text(label),
          avatar: dot == null ? null : Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(onTap),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Filter equipment', style: context.text.titleMedium),
          const Gap(Space.xl),
          if (widget.plants.length > 1)
            section('Plant', [
              choice('All plants', _plant == null, () => _plant = null),
              for (final p in widget.plants) choice(p.name, _plant == p.id, () => _plant = p.id),
            ]),
          section('Status', [
            choice('Any status', _status == null, () => _status = null),
            choice('Failing (any)', _status == 'failing', () => _status = 'failing', dot: context.palette.danger),
            for (final t in widget.types) choice(t.label, _status == t.id, () => _status = t.id, dot: t.color),
            choice('No status yet', _status == 'none', () => _status = 'none', dot: context.palette.border),
          ]),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _plant = _status = null), child: const Text('Reset'))),
            const Gap(Space.md),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, (plant: _plant, status: _status)), child: const Text('Show results'))),
          ]),
        ]),
      ),
    );
  }
}
