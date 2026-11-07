import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_picker.dart';
import '../../data/checks.dart';
import '../../data/offline_queue.dart';

/// Bottom sheet to report a problem found while checking: fixed now, or schedule the fix.
Future<bool> showReportFindingSheet(
  BuildContext context, {
  required String equipmentId,
  required String equipmentName,
  String? checkTaskId,
  String? checkTitle,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportFindingSheet(equipmentId: equipmentId, equipmentName: equipmentName, checkTaskId: checkTaskId, checkTitle: checkTitle),
  );
  return ok ?? false;
}

class _ReportFindingSheet extends ConsumerStatefulWidget {
  const _ReportFindingSheet({required this.equipmentId, required this.equipmentName, this.checkTaskId, this.checkTitle});
  final String equipmentId, equipmentName;
  final String? checkTaskId, checkTitle;

  @override
  ConsumerState<_ReportFindingSheet> createState() => _ReportFindingSheetState();
}

class _ReportFindingSheetState extends ConsumerState<_ReportFindingSheet> {
  final _desc = TextEditingController();
  final _clientId = const Uuid().v4();
  bool _fixedNow = false;
  Uint8List? _photo;
  DateTime? _when;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  List<(String, DateTime)> _quickTimes() {
    final now = DateTime.now();
    final endOfShift = DateTime(now.year, now.month, now.day, 17);
    final tomorrow9 = DateTime(now.year, now.month, now.day + 1, 9);
    return [
      ('In 1 hour', now.add(const Duration(hours: 1))),
      if (endOfShift.isAfter(now.add(const Duration(minutes: 30)))) ('Today 17:00', endOfShift),
      ('Tomorrow 09:00', tomorrow9),
    ];
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)), initialDate: _when ?? now);
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))));
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    final text = _desc.text.trim();
    if (text.isEmpty) return setState(() => _error = 'Describe the problem');
    if (!_fixedNow && _when == null) return setState(() => _error = 'Choose when it will be fixed');
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(checksRepositoryProvider).reportFinding(
          clientId: _clientId,
          equipmentId: widget.equipmentId,
          checkTaskId: widget.checkTaskId,
          description: text,
          status: _fixedNow ? FindingStatus.resolved : FindingStatus.scheduled,
          scheduledFor: _fixedNow ? null : _when,
          photo: _photo,
        );
    if (!mounted) return;
    if (r == SendResult.rejected) {
      setState(() {
        _saving = false;
        _error = 'Could not save this finding. Check that you still have access to this equipment.';
      });
      return;
    }
    ref.invalidate(findingsProvider);
    ref.invalidate(findingStatsProvider);
    HapticFeedback.mediumImpact();
    if (r == SendResult.offline) showToast(context, 'Saved on this device — will sync when you are back online');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Report a problem', style: context.text.titleMedium),
              const SizedBox(height: 2),
              Text(
                widget.checkTitle == null ? widget.equipmentName : '${widget.equipmentName} · ${widget.checkTitle}',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _desc,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'What did you find? e.g. Oil leak near the pump seal', counterText: ''),
              ),
              const SizedBox(height: Space.md),
              PhotoPickerField(photo: _photo, onChanged: (b) => setState(() => _photo = b), hint: 'Optional'),
              const SizedBox(height: Space.lg),
              Text('Can you fix it now?', style: context.text.titleSmall),
              const SizedBox(height: Space.sm),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, icon: Icon(Icons.check_circle_outline_rounded, size: 18), label: Text('Fixed now')),
                  ButtonSegment(value: false, icon: Icon(Icons.schedule_rounded, size: 18), label: Text('Fix later')),
                ],
                selected: {_fixedNow},
                onSelectionChanged: (s) => setState(() => _fixedNow = s.first),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _fixedNow
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: Space.lg),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Fix by', style: context.text.labelMedium),
                          const SizedBox(height: Space.sm),
                          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                            for (final (label, t) in _quickTimes())
                              ChoiceChip(
                                label: Text(label),
                                selected: _when == t,
                                onSelected: (_) => setState(() => _when = t),
                              ),
                            ActionChip(avatar: const Icon(Icons.event_rounded, size: 16), label: const Text('Pick…'), onPressed: _pickCustom),
                          ]),
                          if (_when != null) ...[
                            const SizedBox(height: Space.sm),
                            Text('Your manager is alerted if it is still open after ${formatDateTime(_when!)}.', style: context.text.bodySmall),
                          ],
                        ]),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
              ],
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Save finding'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showFindingSaved(BuildContext context) => showToast(context, 'Finding saved');
