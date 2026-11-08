import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/models.dart';
import '../../data/pm_workbook.dart';
import '../../data/session.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Review of an uploaded PM workbook before importing. Frequencies come from each sheet's FREQUENCY
/// cell and are not editable; the manager only confirms which equipment the workbook belongs to.
class PmReviewPage extends ConsumerStatefulWidget {
  const PmReviewPage({super.key, required this.plant, required this.fileName, required this.bytes, required this.workbook, required this.equipment});
  final Plant plant;
  final String fileName;
  final Uint8List bytes;
  final PmWorkbook workbook;
  final List<EquipmentCandidate> equipment;

  @override
  ConsumerState<PmReviewPage> createState() => _PmReviewPageState();
}

class _PmReviewPageState extends ConsumerState<PmReviewPage> {
  late final _title = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), ''));
  /// Worked out once, before the manager touches the picker.
  late final String? _suggestion = suggestEquipment(
    fileName: widget.fileName,
    equipmentLabel: widget.workbook.equipmentLabel,
    equipmentNo: widget.workbook.equipmentNo,
    equipment: widget.equipment,
  );
  late String? _equipment = _suggestion;
  bool get _suggested => _suggestion != null && _equipment == _suggestion;

  /// "PSW ALP GUN NO C", as written on the sheets.
  String? get _sheetEquipment {
    final s = [wb.equipmentLabel, wb.equipmentNo].nonNulls.join(' ').trim();
    return s.isEmpty ? null : s;
  }
  bool _busy = false;
  String? _progress, _error;

  PmWorkbook get wb => widget.workbook;

  Future<void> _import() async {
    final ready = wb.ready;
    if (ready.isEmpty || _equipment == null || _title.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = ref.read(supabaseProvider);
    final folder = '${widget.plant.id}/${const Uuid().v4()}';
    try {
      String? stored = '$folder/workbook.xlsx';
      setState(() => _progress = 'Uploading workbook…');
      try {
        await db.storage.from('check-sheets').uploadBinary(stored, widget.bytes, fileOptions: const FileOptions(contentType: _xlsxMime));
      } catch (_) {
        stored = null; // the checks matter more than the archived file
      }

      // Pictures used by the sheets being imported.
      final used = {for (final c in ready) ...c.pictures, for (final c in ready) for (final p in c.points) ...p.pictures};
      final paths = <String, String>{};
      var i = 0;
      for (final key in used) {
        final pic = wb.pictures[key]!;
        final path = '$folder/img/${++i}.${pic.extension}';
        if (mounted) setState(() => _progress = 'Uploading pictures $i of ${used.length}…');
        try {
          await db.storage.from('check-sheets').uploadBinary(path, pic.bytes, fileOptions: FileOptions(contentType: pic.contentType));
          paths[key] = path;
        } catch (_) {} // a missing picture should not block the checks
      }

      if (mounted) setState(() => _progress = 'Creating checks…');
      final res = await db.rpc('import_pm_workbook', params: {
        'p_plant': widget.plant.id,
        'p_equipment': _equipment,
        'p_title': _title.text.trim(),
        'p_file_name': widget.fileName,
        'p_file_path': stored,
        'p_checks': [for (final c in ready) c.toJson(fallbackStart: today(), picturePaths: paths, isoDate: isoDate)],
      }) as Map;
      HapticFeedback.mediumImpact();
      final missingPics = used.length - paths.length;
      if (mounted) {
        Navigator.pop(
          context,
          '${res['items']} PM checks · ${res['points']} check points imported · ${res['tasks_created']} scheduled'
          '${missingPics > 0 ? ' · $missingPics pictures could not be uploaded' : ''}',
        );
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _progress = null;
        _error = e is PostgrestException ? e.message : 'Import failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready = wb.ready.length;
    final bad = wb.checks.length - ready;
    final points = wb.ready.fold(0, (n, c) => n + c.points.length);

    // Group by schedule: Daily, Weekly, Monthly, Every 4 months, Half-yearly, ...
    int rank(PmSchedule? s) => s == null ? 1 << 20 : s.unit.index * 1000 + s.interval;
    final groups = <PmSchedule?, List<PmCheck>>{};
    for (final c in wb.checks) {
      groups.putIfAbsent(c.schedule, () => []).add(c);
    }
    final keys = groups.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));

    return Scaffold(
      appBar: AppBar(title: const Text('Review PM check sheets')),
      body: PageBody(maxWidth: 880, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(bad == 0 ? Icons.check_circle_rounded : Icons.info_rounded, color: bad == 0 ? p.success : p.warning),
                const Gap(Space.sm),
                Expanded(
                  child: Text(
                    bad == 0 ? 'All ${wb.checks.length} sheets ready · $points check points' : '$ready of ${wb.checks.length} sheets ready · $bad need attention and will be skipped',
                    style: context.text.titleSmall,
                  ),
                ),
              ]),
              const Gap(Space.xs),
              Text(
                [
                  'Plant: ${widget.plant.name}',
                  'File: ${widget.fileName}',
                  if (wb.equipmentLabel != null) 'Sheet says: ${wb.equipmentLabel}${wb.equipmentNo != null ? ' ${wb.equipmentNo}' : ''}',
                ].join(' · '),
                style: context.text.bodySmall,
              ),
              if (wb.skippedTabs.isNotEmpty || wb.skippedPictures > 0) ...[
                const Gap(Space.xs),
                Text(
                  [
                    if (wb.skippedTabs.isNotEmpty) 'Not check sheets (ignored): ${wb.skippedTabs.join(', ')}',
                    if (wb.skippedPictures > 0) '${wb.skippedPictures} picture${wb.skippedPictures == 1 ? '' : 's'} in an unsupported format (EMF/WMF) left out',
                  ].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: p.warning),
                ),
              ],
              const Gap(Space.lg),
              LayoutBuilder(
                builder: (context, c) => DropdownMenu<String>(
                  width: c.maxWidth,
                  initialSelection: _equipment,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  label: const Text('Equipment this workbook is for'),
                  helperText: _suggested
                      ? 'Matched “${_sheetEquipment ?? widget.fileName}” from the sheet header — change it if wrong'
                      : (_suggestion == null && _sheetEquipment != null
                          ? 'No equipment here matches “$_sheetEquipment” — pick it, or add it under Equipment first'
                          : 'Every sheet in the workbook is scheduled for this equipment'),
                  errorText: widget.equipment.isEmpty ? 'No active equipment in this plant yet' : null,
                  dropdownMenuEntries: [for (final e in widget.equipment) DropdownMenuEntry(value: e.id, label: '${e.name} · ${e.code}')],
                  onSelected: (v) => setState(() => _equipment = v),
                ),
              ),
              const Gap(Space.md),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Workbook name', hintText: 'e.g. ALP C GUN')),
            ]),
          ),
        ),
        const Gap(Space.lg),
        for (final k in keys) ...[
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
            child: Text(
              k == null ? 'Frequency not recognised' : '${k.label} · ${groups[k]!.length} sheet${groups[k]!.length == 1 ? '' : 's'}',
              style: context.text.labelLarge?.copyWith(color: k == null ? p.danger : null),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < groups[k]!.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _CheckTile(check: groups[k]![i]),
              ],
            ]),
          ),
          const Gap(Space.lg),
        ],
        if (_error != null) ...[Text(_error!, style: TextStyle(color: p.danger)), const Gap(Space.lg)],
        const Gap(Space.xxl),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
        padding: const EdgeInsets.all(Space.md),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_progress != null) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text(_progress!, style: context.text.bodySmall, textAlign: TextAlign.center)),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy || ready == 0 || _equipment == null ? null : _import,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(_equipment == null ? 'Choose the equipment first' : 'Import $ready PM check${ready == 1 ? '' : 's'}'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});
  final PmCheck check;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = check;
    final facts = [
      c.schedule?.label ?? '“${c.frequencyText ?? ''}”',
      if (c.pmType != null) c.pmType!.trim(),
      '${c.points.length} points',
      if (c.pictureCount > 0) '${c.pictureCount} pictures',
      if (c.manPower != null) 'man power ${c.manPower!.replaceAll('\n', ', ')}',
      if (c.timeMinutes != null) '${c.timeMinutes!.replaceAll('\n', ', ')} min',
      if (c.startDate != null) 'from ${formatDate(c.startDate!)}',
    ];
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
      childrenPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(c.title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 2),
        Text('${c.tab} · ${facts.join(' · ')}', style: context.text.bodySmall),
        for (final pr in c.problems) _note(context, Icons.error_outline_rounded, pr, p.danger),
        for (final w in c.warnings) _note(context, Icons.info_outline_rounded, w, p.warning),
      ]),
      trailing: c.ok ? Pill('Ready', color: p.success) : Pill('Skip', color: p.danger),
      children: [
        if (c.safetyNote != null) _note(context, Icons.warning_amber_rounded, c.safetyNote!, p.danger),
        if (c.tools != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('Tools: ${c.tools}', style: context.text.bodySmall)),
        const Gap(Space.sm),
        for (final pt in c.points)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 28, child: Text(pt.slNo ?? '•', style: context.text.bodySmall)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pt.checkPoint, style: context.text.bodyMedium),
                  if (pt.stdValue != null) Text('Std: ${pt.stdValue}', style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (pt.pictures.isNotEmpty) Icon(Icons.image_outlined, size: 16, color: p.muted),
              if (pt.pmRank != null) ...[const Gap(Space.xs), Text(pt.pmRank!, style: context.text.labelSmall)],
            ]),
          ),
      ],
    );
  }

  Widget _note(BuildContext context, IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: context.text.bodySmall?.copyWith(color: color))),
        ]),
      );
}
