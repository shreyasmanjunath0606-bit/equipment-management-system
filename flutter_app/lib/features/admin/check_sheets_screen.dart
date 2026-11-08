import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/plant_picker.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/excel_sheets.dart';
import '../../data/models.dart';
import '../../data/pm_workbook.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import 'pm_review_page.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class CheckSheet {
  CheckSheet({required this.id, required this.plantId, required this.title, required this.fileName, required this.rowCount, required this.createdAt, this.filePath, this.uploader, this.activeItems = 0});
  final String id, plantId, title, fileName;
  final String? filePath, uploader;
  final int rowCount, activeItems;
  final DateTime createdAt;
}

class CheckItem {
  CheckItem({required this.id, required this.title, required this.frequency, required this.startDate, required this.active, required this.equipmentName, required this.equipmentCode, this.description, this.interval = 1, this.points = 0, this.sourceTab});
  final String id, title, equipmentName, equipmentCode;
  final String? description, sourceTab;
  final CheckFrequency frequency;
  final int interval, points;
  final DateTime startDate;
  final bool active;
}

final checkSheetsProvider = FutureProvider<List<CheckSheet>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('check_sheets')
      .select('id,plant_id,title,file_name,file_path,row_count,created_at,uploader:profiles!check_sheets_uploaded_by_fkey(name),check_items(count)')
      .eq('check_items.active', true)
      .order('created_at', ascending: false);
  return [
    for (final r in rows)
      CheckSheet(
        id: r['id'] as String,
        plantId: r['plant_id'] as String,
        title: r['title'] as String,
        fileName: r['file_name'] as String,
        filePath: r['file_path'] as String?,
        rowCount: (r['row_count'] as num).toInt(),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        uploader: (r['uploader'] as Json?)?['name'] as String?,
        activeItems: ((r['check_items'] as List?)?.firstOrNull as Json?)?['count'] as int? ?? 0,
      ),
  ];
});

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

/// Managers upload Excel check sheets here; every row becomes a recurring check.
class CheckSheetsScreen extends ConsumerStatefulWidget {
  const CheckSheetsScreen({super.key});

  @override
  ConsumerState<CheckSheetsScreen> createState() => _CheckSheetsScreenState();
}

class _CheckSheetsScreenState extends ConsumerState<CheckSheetsScreen> {
  String? _plant;
  bool _loadingFile = false;

  Future<void> _upload(List<Plant> plants) async {
    final plant = _plant ?? (plants.length == 1 ? plants.first.id : null);
    if (plant == null) {
      showToast(context, 'Choose the plant this sheet is for first');
      return;
    }
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;
    setState(() => _loadingFile = true);
    try {
      final bytes = await file.readAsBytes();
      final plantObj = plants.firstWhere((p) => p.id == plant);

      // PM workbooks (one tab per check, FREQUENCY cell on each tab) get their own review page.
      PmWorkbook? pm;
      try {
        pm = parsePmWorkbook(bytes);
      } catch (_) {}
      if (pm != null) {
        final rows = await ref.read(supabaseProvider).from('equipment').select('id,name,tag_code').eq('plant_id', plant).eq('is_active', true).order('name');
        final equipment = [for (final r in rows) EquipmentCandidate(id: r['id'] as String, name: r['name'] as String, code: r['tag_code'] as String)];
        if (!mounted) return;
        setState(() => _loadingFile = false);
        final result = await Navigator.of(context).push<String>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PmReviewPage(plant: plantObj, fileName: file.name, bytes: bytes, workbook: pm!, equipment: equipment),
        ));
        if (result != null && mounted) {
          ref.invalidate(checkSheetsProvider);
          ref.invalidate(checkTasksProvider);
          ref.invalidate(checkStatsProvider);
          showToast(context, result);
        }
        return;
      }

      final codes = await ref.read(supabaseProvider).from('equipment').select('tag_code').eq('plant_id', plant).eq('is_active', true);
      final known = {for (final r in codes) (r['tag_code'] as String).toUpperCase()};
      final parsed = parseCheckSheet(bytes, knownCodes: known);
      if (!mounted) return;
      setState(() => _loadingFile = false);
      final result = await Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReviewSheetPage(plant: plantObj, fileName: file.name, bytes: bytes, parsed: parsed),
      ));
      if (result != null && mounted) {
        ref.invalidate(checkSheetsProvider);
        ref.invalidate(checkTasksProvider);
        ref.invalidate(checkStatsProvider);
        showToast(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingFile = false);
        showToast(context, 'Could not read that file. Make sure it is an .xlsx Excel workbook.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final sheets = ref.watch(checkSheetsProvider);
    final plantById = {for (final p in plants) p.id: p};

    return PageBody(
      maxWidth: 960,
      onRefresh: () async => ref.invalidate(checkSheetsProvider),
      children: [
        PageHeader(
          title: 'Check sheets',
          subtitle: 'Upload PM check sheet workbooks or simple check lists from Excel. The frequency on each sheet decides how often it repeats.',
          actions: [
            if (plants.length > 1) PlantPicker(plants: plants, value: _plant, onChanged: (v) => setState(() => _plant = v)),
            OutlinedButton.icon(
              onPressed: () => _shareBytes(buildTemplate(), 'check-sheet-template.xlsx', _xlsxMime),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Template'),
            ),
            FilledButton.icon(
              onPressed: _loadingFile || plants.isEmpty ? null : () => _upload(plants),
              icon: _loadingFile ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.upload_file_rounded, size: 20),
              label: const Text('Upload sheet'),
            ),
          ],
        ),
        const _HowItWorks(),
        const Gap(Space.xl),
        AsyncBody<List<CheckSheet>>(
          value: sheets,
          onRetry: () => ref.invalidate(checkSheetsProvider),
          data: (all) {
            final list = all.where((s) => _plant == null || s.plantId == _plant).toList();
            if (list.isEmpty) {
              return Card(
                child: EmptyState(
                  icon: Icons.upload_file_outlined,
                  title: 'No check sheets yet',
                  message: 'Download the template, fill in one row per check, then upload it here.',
                  action: FilledButton.icon(onPressed: () => _upload(plants), icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Upload sheet')),
                ),
              );
            }
            return Column(children: [
              for (final s in list) ...[
                _SheetCard(sheet: s, plantName: plants.length > 1 ? plantById[s.plantId]?.name : null),
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
      step(1, 'Upload the workbook', 'PM sheets as they are (one tab per check), or the simple template'),
      step(2, 'Review', "Each tab's FREQUENCY is read for you — daily, weekly, monthly, 4-monthly, half-yearly"),
      step(3, 'Checks repeat', 'Workers get every check point, picture and safety note; the in-charge verifies'),
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

class _SheetCard extends ConsumerWidget {
  const _SheetCard({required this.sheet, this.plantName});
  final CheckSheet sheet;
  final String? plantName;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    if (sheet.filePath == null) return;
    try {
      final bytes = await ref.read(supabaseProvider).storage.from('check-sheets').download(sheet.filePath!);
      await _shareBytes(bytes, sheet.fileName, _xlsxMime);
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not download the original file');
    }
  }

  Future<void> _exportCompletions(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showItems(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.md),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: p.successSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.table_chart_outlined, color: p.success, size: 22),
            ),
            const Gap(Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sheet.title, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  ['${sheet.activeItems} active check${sheet.activeItems == 1 ? '' : 's'}', ?plantName, 'uploaded ${formatDate(sheet.createdAt)}', if (sheet.uploader != null) 'by ${sheet.uploader}'].join(' · '),
                  style: context.text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => switch (v) {
                'items' => _showItems(context, ref),
                'download' => _download(context, ref),
                _ => _exportCompletions(context, ref),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'items', child: Text('View checks')),
                const PopupMenuItem(value: 'export', child: Text('Export completions (Excel)')),
                if (sheet.filePath != null) const PopupMenuItem(value: 'download', child: Text('Download original')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _showItems(BuildContext context, WidgetRef ref) {
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
          Text('Switch a check off to stop scheduling it. Past results are kept.', style: context.text.bodySmall),
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
                  '${it.equipmentName} (${it.equipmentCode})',
                  '${frequencyLabel(it.frequency, it.interval)} from ${formatDate(it.startDate)}',
                  if (it.points > 0) '${it.points} points',
                  if (it.sourceTab != null) 'sheet “${it.sourceTab}”',
                ].join(' · ')),
                onChanged: (v) async {
                  try {
                    await ref.read(supabaseProvider).from('check_items').update({'active': v}).eq('id', it.id);
                    ref.invalidate(checkItemsProvider(sheet.id));
                    ref.invalidate(checkSheetsProvider);
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

/// Full-screen review of a parsed sheet before importing.
class _ReviewSheetPage extends ConsumerStatefulWidget {
  const _ReviewSheetPage({required this.plant, required this.fileName, required this.bytes, required this.parsed});
  final Plant plant;
  final String fileName;
  final Uint8List bytes;
  final ParsedSheet parsed;

  @override
  ConsumerState<_ReviewSheetPage> createState() => _ReviewSheetPageState();
}

class _ReviewSheetPageState extends ConsumerState<_ReviewSheetPage> {
  late final _title = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), ''));
  bool _onlyProblems = false;
  bool _busy = false;
  String? _error;

  Future<void> _import() async {
    final valid = widget.parsed.rows.where((r) => r.ok).toList();
    if (valid.isEmpty || _title.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = ref.read(supabaseProvider);
    try {
      final path = '${widget.plant.id}/${const Uuid().v4()}.xlsx';
      String? stored = path;
      try {
        await db.storage.from('check-sheets').uploadBinary(path, widget.bytes, fileOptions: const FileOptions(contentType: _xlsxMime));
      } catch (_) {
        stored = null; // keep going: the checks matter more than the archived file
      }
      final res = await db.rpc('import_check_sheet', params: {
        'p_plant': widget.plant.id,
        'p_title': _title.text.trim(),
        'p_file_name': widget.fileName,
        'p_file_path': stored,
        'p_rows': [for (final r in valid) r.toJson()],
      }) as Map;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, '${res['items']} checks imported · ${res['tasks_created']} scheduled for the coming week');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e is PostgrestException ? e.message : 'Import failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = widget.parsed.rows;
    final bad = rows.where((r) => !r.ok).length;
    final shown = _onlyProblems ? rows.where((r) => !r.ok).toList() : rows;

    return Scaffold(
      appBar: AppBar(title: const Text('Review check sheet')),
      body: rows.isEmpty
          ? EmptyState(
              icon: Icons.table_chart_outlined,
              title: 'No checks found in this file',
              message: 'The first sheet needs a header row with Equipment Code, Check Item and Frequency columns. Download the template to see the format.',
              action: OutlinedButton(onPressed: () => _shareBytes(buildTemplate(), 'check-sheet-template.xlsx', _xlsxMime), child: const Text('Get template')),
            )
          : PageBody(maxWidth: 880, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(bad == 0 ? Icons.check_circle_rounded : Icons.info_rounded, color: bad == 0 ? p.success : p.warning),
                      const Gap(Space.sm),
                      Expanded(
                        child: Text(
                          bad == 0 ? 'All ${rows.length} rows are ready to import' : '${widget.parsed.valid} of ${rows.length} rows are ready · $bad need attention and will be skipped',
                          style: context.text.titleSmall,
                        ),
                      ),
                    ]),
                    const Gap(Space.xs),
                    Text('Plant: ${widget.plant.name} · File: ${widget.fileName}', style: context.text.bodySmall),
                    const Gap(Space.lg),
                    TextField(controller: _title, decoration: const InputDecoration(labelText: 'Sheet name', hintText: 'e.g. CNC section daily checks')),
                  ]),
                ),
              ),
              const Gap(Space.lg),
              if (bad > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(label: Text('Show only problems ($bad)'), selected: _onlyProblems, onSelected: (v) => setState(() => _onlyProblems = v)),
                ),
              const Gap(Space.md),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border),
                    _RowTile(row: shown[i]),
                  ],
                ]),
              ),
              if (_error != null) ...[const Gap(Space.lg), Text(_error!, style: TextStyle(color: p.danger))],
              const Gap(Space.xxl),
            ]),
      bottomNavigationBar: rows.isEmpty
          ? null
          : Container(
              decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
              padding: const EdgeInsets.all(Space.md),
              child: SafeArea(
                top: false,
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy || widget.parsed.valid == 0 ? null : _import,
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text('Import ${widget.parsed.valid} check${widget.parsed.valid == 1 ? '' : 's'}'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});
  final SheetRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 34, child: Text('${row.rowNumber}', style: context.text.bodySmall)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.title.isEmpty ? '(no check item)' : row.title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(
              [row.code.isEmpty ? '(no code)' : row.code, row.frequency?.label ?? '?', if (row.startDate != null) 'from ${formatDate(row.startDate!)}'].join(' · '),
              style: context.text.bodySmall,
            ),
            for (final pr in row.problems)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(Icons.error_outline_rounded, size: 14, color: p.danger),
                  const SizedBox(width: 4),
                  Flexible(child: Text(pr, style: context.text.bodySmall?.copyWith(color: p.danger))),
                ]),
              ),
          ]),
        ),
        row.ok ? Pill('Ready', color: p.success) : Pill('Skip', color: p.danger),
      ]),
    );
  }
}
