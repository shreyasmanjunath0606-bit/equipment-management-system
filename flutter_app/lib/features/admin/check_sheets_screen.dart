import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/plant_picker.dart';
import '../../data/assignments.dart';
import '../../data/checks.dart';
import '../../data/excel_sheets.dart';
import '../../data/models.dart';
import '../../data/pm_workbook.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import 'pm_review_page.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class CheckItem {
  CheckItem({required this.id, required this.title, required this.frequency, required this.startDate, required this.active, required this.equipmentName, required this.equipmentCode, this.description, this.interval = 1, this.points = 0, this.sourceTab});
  final String id, title, equipmentName, equipmentCode;
  final String? description, sourceTab;
  final CheckFrequency frequency;
  final int interval, points;
  final DateTime startDate;
  final bool active;
}

final checkItemsProvider = FutureProvider.family<List<CheckItem>, String>((ref, sheetId) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('check_items')
      .select('id,title,description,frequency,interval_count,source_tab,start_date,active,equipment(name,tag_code),check_points(count)')
      .eq('sheet_id', sheetId)
      .order('created_at');
  return [
    for (final r in rows)
      CheckItem(
        id: r['id'] as String,
        title: r['title'] as String,
        description: r['description'] as String?,
        frequency: CheckFrequency.tryParse(r['frequency'] as String?) ?? CheckFrequency.daily,
        startDate: DateTime.parse(r['start_date'] as String),
        active: r['active'] as bool,
        equipmentName: (r['equipment'] as Json?)?['name'] as String? ?? '',
        equipmentCode: (r['equipment'] as Json?)?['tag_code'] as String? ?? '',
        interval: (r['interval_count'] as num?)?.toInt() ?? 1,
        sourceTab: r['source_tab'] as String?,
        points: ((r['check_points'] as List?)?.firstOrNull as Json?)?['count'] as int? ?? 0,
      ),
  ];
});

Future<void> _shareBytes(List<int> bytes, String name, String mime) =>
    SharePlus.instance.share(ShareParams(files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mime, name: name)], fileNameOverrides: [name]));

/// Managers give each equipment one worker and its Daily / Weekly / Monthly check-sheet workbooks.
class CheckSheetsScreen extends ConsumerStatefulWidget {
  const CheckSheetsScreen({super.key});

  @override
  ConsumerState<CheckSheetsScreen> createState() => _CheckSheetsScreenState();
}

class _CheckSheetsScreenState extends ConsumerState<CheckSheetsScreen> {
  String? _plant;

  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final plans = ref.watch(equipmentPlansProvider);
    final plantById = {for (final p in plants) p.id: p};

    return PageBody(
      maxWidth: 960,
      onRefresh: () async {
        ref.invalidate(equipmentPlansProvider);
        ref.invalidate(plantWorkersProvider);
      },
      children: [
        PageHeader(
          title: 'Assignments',
          subtitle: 'Each equipment has one worker. Give it a Daily, a Weekly and a Monthly check-sheet workbook — the worker does those checks on that equipment, again and again.',
          actions: [if (plants.length > 1) PlantPicker(plants: plants, value: _plant, onChanged: (v) => setState(() => _plant = v))],
        ),
        const _HowItWorks(),
        const Gap(Space.xl),
        AsyncBody<List<EquipmentPlan>>(
          value: plans,
          onRetry: () => ref.invalidate(equipmentPlansProvider),
          data: (all) {
            final list = all.where((e) => _plant == null || e.plantId == _plant).toList()
              // Equipment that still needs a worker or sheets first.
              ..sort((a, b) {
                int need(EquipmentPlan e) => (e.workerId == null ? 0 : 2) + (SheetSlot.main.every((s) => e.sheetFor(s) != null) ? 1 : 0);
                final c = need(a).compareTo(need(b));
                return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
            if (list.isEmpty) {
              return const Card(
                child: EmptyState(
                  icon: Icons.precision_manufacturing_outlined,
                  title: 'No equipment yet',
                  message: 'Add equipment under Manage equipment, then assign a worker and its check sheets here.',
                ),
              );
            }
            return Column(children: [
              for (final e in list) ...[
                _EquipmentCard(plan: e, plant: plantById[e.plantId], showPlant: plants.length > 1),
                const Gap(Space.md),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget step(int n, String title, String body) => Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.primarySoft, shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const Gap(Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(body, style: context.text.bodySmall),
              ]),
            ),
          ]),
        );
    final steps = [
      step(1, 'Assign a worker', 'One worker per equipment. Change it on promotion or leave — open checks move to the new worker'),
      step(2, 'Upload 3 workbooks', 'Daily repeats every day, Weekly every Monday, Monthly on the day you pick. Every tab is one check'),
      step(3, 'Worker checks, you verify', 'The worker sees only their equipment. Uploading again replaces that workbook'),
    ];
    return Card(
      color: p.surface,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: isWide(context)
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final s in steps) ...[s, if (s != steps.last) const Gap(Space.lg)]])
            : Column(children: [for (final s in steps) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Row(children: [s]))]),
      ),
    );
  }
}

/// One equipment: its worker, its three main workbooks and any extra ones.
class _EquipmentCard extends ConsumerStatefulWidget {
  const _EquipmentCard({required this.plan, required this.plant, required this.showPlant});
  final EquipmentPlan plan;
  final Plant? plant;
  final bool showPlant;

  @override
  ConsumerState<_EquipmentCard> createState() => _EquipmentCardState();
}

class _EquipmentCardState extends ConsumerState<_EquipmentCard> {
  bool _busy = false;

  EquipmentPlan get plan => widget.plan;

  Future<void> _chooseWorker() async {
    final workers = await ref.read(plantWorkersProvider(plan.plantId).future).catchError((_) => const <PlantWorker>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final p = ctx.palette;
        return SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text('Who looks after ${plan.name}?', style: ctx.text.titleMedium),
            ),
            if (workers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Text('No workers in this plant yet. An admin can invite them under Users.'),
              ),
            for (final w in workers)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                leading: CircleAvatar(child: Text(w.name.isEmpty ? '?' : w.name[0].toUpperCase())),
                title: Text(w.name),
                subtitle: Text(w.equipmentId == null
                    ? 'Free · ${w.email}'
                    : w.equipmentId == plan.equipmentId
                        ? 'Looks after this equipment'
                        : 'Already looks after other equipment'),
                enabled: w.equipmentId == null,
                selected: w.id == plan.workerId,
                onTap: () => Navigator.pop(ctx, w.id),
              ),
            if (plan.workerId != null)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                leading: Icon(Icons.person_off_outlined, color: p.danger),
                title: Text('Remove ${plan.workerName ?? 'the worker'}', style: TextStyle(color: p.danger)),
                subtitle: const Text('Nobody will see this equipment’s checks until you assign someone'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
            const Gap(Space.md),
          ]),
        );
      },
    );
    if (picked == null || !mounted) return;
    await _run(() => ref.read(assignmentsRepositoryProvider).assign(plan.equipmentId, picked.isEmpty ? null : picked),
        picked.isEmpty ? 'Worker removed from ${plan.name}' : 'Assigned — open checks moved to the worker');
  }

  Future<void> _upload(SheetSlot slot) async {
    final plant = widget.plant;
    if (plant == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    PmWorkbook? wb;
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
      wb = parsePmWorkbook(bytes);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (wb == null || bytes == null) {
      showToast(context, 'Could not read that file as a PM check-sheet workbook (.xlsx, one tab per check).');
      return;
    }
    final freq = slot.frequency;
    if (freq != null) wb.useSchedule(PmSchedule(freq));
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PmReviewPage(
        plant: plant,
        fileName: file.name,
        bytes: bytes!,
        workbook: wb!,
        equipment: EquipmentCandidate(id: plan.equipmentId, name: plan.name, code: plan.code),
        slot: slot,
        replacing: plan.sheetFor(slot)?.title,
        workerName: plan.workerName,
      ),
    ));
    if (result != null && mounted) {
      ref.invalidate(equipmentPlansProvider);
      ref.invalidate(checkTasksProvider);
      ref.invalidate(checkStatsProvider);
      showToast(context, result);
    }
  }

  Future<void> _remove(CheckSheet sheet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove “${sheet.title}”?'),
        content: const Text('Its checks stop being scheduled and open ones disappear for the worker. Completed checks stay in the history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(assignmentsRepositoryProvider).removeSheet(sheet.id), 'Workbook removed');
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      HapticFeedback.lightImpact();
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    for (final m in ['already looks after', 'Only an active worker']) {
      if (s.contains(m)) return s.substring(s.indexOf(m)).split('\n').first.replaceAll(RegExp(r'[",)]+$'), '');
    }
    return 'Could not save — check your connection';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final noWorker = plan.workerId == null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.precision_manufacturing_outlined, color: p.primary, size: 22),
            ),
            const Gap(Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text([plan.code, if (widget.showPlant && widget.plant != null) widget.plant!.name].join(' · '), style: context.text.bodySmall),
              ]),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(Space.sm), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
        // Worker
        Material(
          color: noWorker ? p.warningSoft : p.surfaceMuted,
          child: InkWell(
            onTap: _busy ? null : _chooseWorker,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Row(children: [
                Icon(noWorker ? Icons.person_add_alt_1_outlined : Icons.person_rounded, size: 20, color: noWorker ? p.warning : p.foreground),
                const Gap(Space.sm),
                Expanded(
                  child: Text(
                    noWorker ? 'No worker assigned — nobody sees these checks' : 'Worker: ${plan.workerName ?? '—'}',
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: noWorker ? p.warning : null),
                  ),
                ),
                Text(noWorker ? 'Assign' : 'Change', style: context.text.labelLarge?.copyWith(color: p.primary)),
              ]),
            ),
          ),
        ),
        for (final slot in SheetSlot.main) ...[
          Divider(height: 1, color: p.border),
          _SlotRow(slot: slot, sheet: plan.sheetFor(slot), busy: _busy, onUpload: () => _upload(slot), onRemove: _remove),
        ],
        for (final s in plan.extras) ...[
          Divider(height: 1, color: p.border),
          _SlotRow(slot: SheetSlot.extra, sheet: s, busy: _busy, onUpload: () => _upload(SheetSlot.extra), onRemove: _remove),
        ],
        Divider(height: 1, color: p.border),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            child: TextButton.icon(
              onPressed: _busy ? null : () => _upload(SheetSlot.extra),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add a longer-interval workbook (4-monthly, half-yearly…)'),
            ),
          ),
        ),
      ]),
    );
  }
}

/// "Daily · Every day · ALP C GUN daily · 6 checks   [Replace] [⋮]" or an Upload button when empty.
class _SlotRow extends ConsumerWidget {
  const _SlotRow({required this.slot, required this.sheet, required this.busy, required this.onUpload, required this.onRemove});
  final SheetSlot slot;
  final CheckSheet? sheet;
  final bool busy;
  final VoidCallback onUpload;
  final ValueChanged<CheckSheet> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = sheet;
    final title = slot == SheetSlot.extra ? (s?.title ?? 'Other intervals') : slot.label;
    return InkWell(
      onTap: s == null ? (busy ? null : onUpload) : () => _showItems(context, s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, Space.sm),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: s == null ? p.surfaceMuted : p.successSoft, borderRadius: BorderRadius.circular(8)),
            child: Icon(s == null ? Icons.upload_file_outlined : Icons.table_chart_outlined, size: 18, color: s == null ? p.muted : p.success),
          ),
          const Gap(Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                s == null
                    ? '${slot.schedule()} · no workbook yet'
                    : [
                        if (slot != SheetSlot.extra) s.schedule,
                        if (slot != SheetSlot.extra) '“${s.title}”',
                        '${s.activeItems} check${s.activeItems == 1 ? '' : 's'}',
                        'uploaded ${formatDate(s.createdAt)}',
                      ].join(' · '),
                style: context.text.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (s == null)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: OutlinedButton(onPressed: busy ? null : onUpload, child: const Text('Upload')),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !busy,
              onSelected: (v) => switch (v) {
                'items' => _showItems(context, s),
                'replace' => onUpload(),
                'download' => _download(context, ref, s),
                'remove' => onRemove(s),
                _ => _exportCompletions(context, ref, s),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'items', child: Text('View checks')),
                if (slot != SheetSlot.extra) PopupMenuItem(value: 'replace', child: Text('Replace ${slot.label.toLowerCase()} workbook')),
                const PopupMenuItem(value: 'export', child: Text('Export completions (Excel)')),
                if (s.filePath != null) const PopupMenuItem(value: 'download', child: Text('Download original')),
                const PopupMenuItem(value: 'remove', child: Text('Remove workbook')),
              ],
            ),
        ]),
      ),
    );
  }

  void _showItems(BuildContext context, CheckSheet sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _ItemsSheet(sheet: sheet, scroll: scroll),
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref, CheckSheet sheet) async {
    if (sheet.filePath == null) return;
    try {
      final bytes = await ref.read(supabaseProvider).storage.from('check-sheets').download(sheet.filePath!);
      await _shareBytes(bytes, sheet.fileName, _xlsxMime);
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not download the original file');
    }
  }

  Future<void> _exportCompletions(BuildContext context, WidgetRef ref, CheckSheet sheet) async {
    try {
      final itemIds = (await ref.read(supabaseProvider).from('check_items').select('id').eq('sheet_id', sheet.id)).map((r) => r['id'] as String).toList();
      if (itemIds.isEmpty) return;
      final rows = await ref
          .read(supabaseProvider)
          .from('check_tasks')
          .select(CheckTask.select)
          .inFilter('check_item_id', itemIds)
          .lte('due_date', isoDate(today()))
          .order('due_date', ascending: false)
          .limit(10000);
      final tasks = rows.map(CheckTask.fromJson).toList();
      final points = <PointResultRow>[];
      final done = [for (final t in tasks) if (t.isPm && t.isDone) t.id];
      for (var i = 0; i < done.length; i += 200) {
        final res = await ref
            .read(supabaseProvider)
            .from('check_point_results')
            .select('check_task_id,check_point_id,result,note,finding_id,findings(status),check_points(position,sl_no,check_point)')
            .inFilter('check_task_id', done.sublist(i, (i + 200).clamp(0, done.length)));
        for (final r in res) {
          final cp = r['check_points'] as Json?;
          final result = PointResult.parse(r['result'] as String?);
          if (cp == null || result == null) continue;
          points.add((
            taskId: r['check_task_id'] as String,
            position: (cp['position'] as num).toInt(),
            slNo: cp['sl_no'] as String?,
            checkPoint: cp['check_point'] as String,
            result: RecordedResult(
              pointId: r['check_point_id'] as String,
              result: result,
              note: r['note'] as String?,
              findingId: r['finding_id'] as String?,
              findingResolved: (r['findings'] as Json?)?['status'] == 'resolved',
            ),
          ));
        }
      }
      await _shareBytes(buildCompletionsReport(tasks, points: points), '${sheet.title}-completions-${isoDate(today())}.xlsx', _xlsxMime);
    } catch (_) {
      if (context.mounted) showToast(context, 'Export failed — check your connection');
    }
  }
}

class _ItemsSheet extends ConsumerWidget {
  const _ItemsSheet({required this.sheet, required this.scroll});
  final CheckSheet sheet;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(checkItemsProvider(sheet.id));
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sheet.title, style: context.text.titleMedium),
          Text('${sheet.schedule}. Switch a check off to stop scheduling it — it disappears for the worker. Past results are kept.', style: context.text.bodySmall),
        ]),
      ),
      Expanded(
        child: AsyncBody<List<CheckItem>>(
          value: items,
          data: (list) => ListView.separated(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: Space.xl),
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: p.border, indent: Space.xl),
            itemBuilder: (_, i) {
              final it = list[i];
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                value: it.active,
                title: Text(it.title),
                subtitle: Text([
                  if (sheet.slot == SheetSlot.extra) '${frequencyLabel(it.frequency, it.interval)} from ${formatDate(it.startDate)}',
                  if (it.points > 0) '${it.points} points',
                  if (it.sourceTab != null) 'sheet “${it.sourceTab}”',
                ].join(' · ')),
                onChanged: (v) async {
                  try {
                    await ref.read(supabaseProvider).from('check_items').update({'active': v}).eq('id', it.id);
                    ref.invalidate(checkItemsProvider(sheet.id));
                    ref.invalidate(equipmentPlansProvider);
                    ref.invalidate(checkTasksProvider);
                  } catch (_) {
                    if (context.mounted) showToast(context, 'Could not save — check your connection');
                  }
                },
              );
            },
          ),
        ),
      ),
    ]);
  }
}
