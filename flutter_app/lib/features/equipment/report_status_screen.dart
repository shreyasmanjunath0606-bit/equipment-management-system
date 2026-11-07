import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/photo_picker.dart';
import '../../data/equipment_repo.dart';
import '../../data/models.dart';
import '../../data/offline_queue.dart';
import '../../data/providers.dart';

/// Fast mobile form (also the QR-scan target): pick a status, optional note and photo, submit.
class ReportStatusScreen extends ConsumerStatefulWidget {
  const ReportStatusScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ReportStatusScreen> createState() => _ReportStatusScreenState();
}

class _ReportStatusScreenState extends ConsumerState<ReportStatusScreen> {
  String? _statusId;
  final _note = TextEditingController();
  Uint8List? _photo;
  bool _busy = false;
  ({bool ok, bool queued, String text})? _message;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(Equipment e) async {
    if (_statusId == null) return;
    setState(() => _busy = true);
    final r = await ref.read(equipmentRepositoryProvider).reportStatus(equipmentId: e.id, statusTypeId: _statusId!, note: _note.text, photo: _photo);
    if (!mounted) return;
    switch (r) {
      case SendResult.sent:
        HapticFeedback.mediumImpact();
        ref.invalidate(equipmentEventsProvider(e.id));
        ref.invalidate(equipmentListProvider);
        ref.invalidate(currentStatusProvider);
        showToast(context, 'Reported. Managers have been notified.');
        context.canPop() ? context.pop() : context.go('/equipment/${e.id}');
      case SendResult.offline:
        setState(() {
          _busy = false;
          _message = (ok: true, queued: true, text: "No signal. Saved on this device — it will be sent automatically when you're back online.");
        });
      case SendResult.rejected:
        setState(() {
          _busy = false;
          _message = (ok: false, queued: false, text: 'Could not save this report. Check that you have access to this equipment.');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(equipmentDetailProvider(widget.id));
    final types = ref.watch(statusTypesProvider);
    return AsyncBody<EquipmentDetail?>(
      value: detail,
      onRetry: () => ref.invalidate(equipmentDetailProvider(widget.id)),
      data: (d) {
        if (d == null) {
          return const EmptyState(icon: Icons.search_off_rounded, title: 'Equipment not found', message: 'It may not exist, or you do not have access to its plant.');
        }
        final e = d.equipment;
        final list = types.value ?? const <StatusType>[];
        final selected = list.where((t) => t.id == _statusId).firstOrNull;
        final p = context.palette;

        return Column(children: [
          Expanded(
            child: PageBody(maxWidth: 640, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: p.muted, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => context.canPop() ? context.pop() : context.go('/equipment/${e.id}'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back'),
                ),
              ),
              const Gap(Space.sm),
              Text('REPORT STATUS', style: context.text.labelSmall?.copyWith(color: p.primary)),
              const Gap(Space.xs),
              Text(e.name, style: context.text.headlineSmall),
              Text('${e.tagCode} · ${d.plantName ?? ''}', style: context.text.bodyMedium?.copyWith(color: p.muted)),
              const Gap(Space.xl),
              if (!e.isActive)
                const Card(child: EmptyState(icon: Icons.archive_outlined, title: 'This machine is retired', message: 'Retired equipment cannot receive new reports.'))
              else ...[
                SectionCard(
                  title: 'What is the status now?',
                  child: LayoutBuilder(builder: (context, c) {
                    final w = (c.maxWidth - Space.md) / 2;
                    return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                      for (final t in list) SizedBox(width: w, child: _StatusOption(type: t, selected: _statusId == t.id, onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _statusId = t.id);
                      })),
                    ]);
                  }),
                ),
                const Gap(Space.lg),
                SectionCard(
                  title: 'What happened?',
                  subtitle: 'Optional',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _note,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'e.g. Belt snapped, strange noise from motor'),
                    ),
                    const Gap(Space.sm),
                    PhotoPickerField(photo: _photo, onChanged: (b) => setState(() => _photo = b)),
                  ]),
                ),
                if (_message != null) ...[
                  const Gap(Space.lg),
                  Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(color: _message!.queued ? p.warningSoft : p.dangerSoft, borderRadius: Radii.inputAll),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(_message!.queued ? Icons.cloud_off_rounded : Icons.error_outline_rounded, size: 18, color: _message!.queued ? p.warning : p.danger),
                      const Gap(Space.sm),
                      Expanded(child: Text(_message!.text, style: context.text.bodyMedium)),
                    ]),
                  ),
                ],
              ],
            ]),
          ),
          if (e.isActive)
            Container(
              decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: selected == null ? null : FilledButton.styleFrom(backgroundColor: selected.isFailure ? p.danger : p.primary),
                        onPressed: _statusId == null || _busy || (_message?.queued ?? false) ? null : () => _submit(e),
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(selected == null ? 'Select a status' : 'Submit — ${selected.label}', style: const TextStyle(fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({required this.type, required this.selected, required this.onTap});
  final StatusType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? type.color.withValues(alpha: 0.10) : p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: selected ? type.color : p.border, width: selected ? 2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.cardAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: SizedBox(
              height: 64,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Container(width: 14, height: 14, decoration: BoxDecoration(color: type.color, shape: BoxShape.circle)),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle_rounded, color: type.color, size: 22),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(type.label, style: context.text.titleSmall?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (type.isFailure) Text('Alerts managers', style: context.text.bodySmall?.copyWith(fontSize: 11)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
