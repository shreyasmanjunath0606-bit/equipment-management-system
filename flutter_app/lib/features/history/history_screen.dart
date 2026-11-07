import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';

typedef HistoryFilter = ({String? plantId, String? statusId, DateTimeRange? range, int limit});

const _cols = 'id,equipment_id,status_type_id,plant_id,note,photo_path,reported_at,equipment(name,tag_code),profiles(name)';

dynamic _apply(dynamic q, HistoryFilter f) {
  if (f.plantId != null) q = q.eq('plant_id', f.plantId!);
  if (f.statusId != null) q = q.eq('status_type_id', f.statusId!);
  if (f.range != null) {
    q = q.gte('reported_at', f.range!.start.toUtc().toIso8601String());
    q = q.lt('reported_at', f.range!.end.add(const Duration(days: 1)).toUtc().toIso8601String());
  }
  return q;
}

final historyProvider = FutureProvider.family<List<StatusEvent>, HistoryFilter>((ref, f) async {
  final q = _apply(ref.watch(supabaseProvider).from('status_events').select(_cols), f);
  final rows = await q.order('reported_at', ascending: false).order('id', ascending: false).limit(f.limit) as List;
  return rows.cast<Json>().map(StatusEvent.fromJson).toList();
});

/// Full status history across equipment, with filters and CSV export (kept forever, append-only).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _plant;
  String? _status;
  DateTimeRange? _range;
  int _limit = 50;
  bool _exporting = false;

  HistoryFilter get _filter => (plantId: _plant, statusId: _status, range: _range, limit: _limit);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (r != null) setState(() { _range = r; _limit = 50; });
  }

  Future<void> _export(Map<String, StatusType> byId, Map<String, Plant> plants) async {
    setState(() => _exporting = true);
    try {
      final q = _apply(ref.read(supabaseProvider).from('status_events').select(_cols), _filter);
      final rows = (await q.order('reported_at', ascending: false).limit(10000) as List).cast<Json>().map(StatusEvent.fromJson);
      String esc(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
      final csv = StringBuffer('reported_at,plant,equipment_code,equipment,status,reported_by,note\n');
      for (final e in rows) {
        csv.writeln([
          esc(e.reportedAt.toIso8601String()),
          esc(plants[e.plantId]?.name),
          esc(e.equipmentTag),
          esc(e.equipmentName),
          esc(byId[e.statusTypeId]?.label),
          esc(e.reporterName),
          esc(e.note),
        ].join(','));
      }
      final name = 'status-history-${isoDate(DateTime.now())}.csv';
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(utf8.encode(csv.toString()), mimeType: 'text/csv', name: name)], fileNameOverrides: [name]));
    } catch (_) {
      if (mounted) showToast(context, 'Export failed — check your connection');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(historyProvider(_filter));
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final types = ref.watch(statusTypesProvider).value ?? const <StatusType>[];
    final byId = {for (final t in types) t.id: t};
    final plantById = {for (final p in plants) p.id: p};
    final p = context.palette;

    Widget filterChip({required String label, required bool active, required VoidCallback onTap, VoidCallback? onClear, IconData? icon}) => InputChip(
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(label),
          selected: active,
          showCheckmark: false,
          onPressed: onTap,
          onDeleted: active ? onClear : null,
          deleteIcon: const Icon(Icons.close_rounded, size: 16),
        );

    Future<String?> choose(String title, List<(String?, String)> options, String? current) => showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm), child: Text(title, style: ctx.text.titleMedium)),
              for (final (v, l) in options)
                ListTile(title: Text(l), trailing: v == current ? Icon(Icons.check_rounded, color: p.primary) : null, onTap: () => Navigator.pop(ctx, v ?? '')),
              const SizedBox(height: Space.sm),
            ]),
          ),
        );

    return PageBody(
      maxWidth: 960,
      onRefresh: () async => ref.invalidate(historyProvider),
      children: [
        PageHeader(
          title: 'History',
          subtitle: 'Every status report, kept permanently.',
          actions: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(byId, plantById),
              icon: _exporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          filterChip(
            icon: Icons.date_range_rounded,
            label: _range == null ? 'Any date' : '${formatDayShort(_range!.start)} – ${formatDayShort(_range!.end)}',
            active: _range != null,
            onTap: _pickRange,
            onClear: () => setState(() => _range = null),
          ),
          if (plants.length > 1)
            filterChip(
              icon: Icons.factory_outlined,
              label: plantById[_plant]?.name ?? 'All plants',
              active: _plant != null,
              onTap: () async {
                final v = await choose('Plant', [(null, 'All plants'), for (final x in plants) (x.id, x.name)], _plant);
                if (v != null) setState(() { _plant = v.isEmpty ? null : v; _limit = 50; });
              },
              onClear: () => setState(() => _plant = null),
            ),
          filterChip(
            icon: Icons.circle_outlined,
            label: byId[_status]?.label ?? 'Any status',
            active: _status != null,
            onTap: () async {
              final v = await choose('Status', [(null, 'Any status'), for (final t in types) (t.id, t.label)], _status);
              if (v != null) setState(() { _status = v.isEmpty ? null : v; _limit = 50; });
            },
            onClear: () => setState(() => _status = null),
          ),
        ]),
        const Gap(Space.lg),
        AsyncBody<List<StatusEvent>>(
          value: list,
          onRetry: () => ref.invalidate(historyProvider),
          data: (rows) => rows.isEmpty
              ? const Card(child: EmptyState(icon: Icons.history_rounded, title: 'No reports match', message: 'Try a wider date range or clear the filters.'))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.border),
                        InkWell(
                          onTap: () => context.push('/equipment/${rows[i].equipmentId}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(rows[i].equipmentName ?? 'Equipment', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [rows[i].equipmentTag, if (plants.length > 1) plantById[rows[i].plantId]?.name, rows[i].reporterName, formatDateTime(rows[i].reportedAt)].whereType<String>().join(' · '),
                                    style: context.text.bodySmall,
                                  ),
                                  if (rows[i].note != null) ...[
                                    const SizedBox(height: Space.xs),
                                    Text(rows[i].note!, style: context.text.bodySmall?.copyWith(color: p.foreground), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ]),
                              ),
                              const Gap(Space.md),
                              StatusChip(status: byId[rows[i].statusTypeId], dense: true),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  if (rows.length >= _limit) ...[
                    const Gap(Space.lg),
                    Center(child: OutlinedButton(onPressed: () => setState(() => _limit += 50), child: const Text('Show older reports'))),
                  ],
                ]),
        ),
      ],
    );
  }
}
