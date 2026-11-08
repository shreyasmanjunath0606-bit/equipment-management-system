import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/photo_picker.dart';
import '../../core/widgets/status.dart';
import '../../data/checks.dart';
import '../../data/models.dart';
import '../../data/offline_queue.dart';
import '../../data/session.dart';

/// Runs one PM check sheet: the sheet's header (frequency, PM type, man power, time, safety warning,
/// tools), then every check point with all its columns and pictures, and a ○ / ⊗ / △ result for each.
/// Submitting = the worker's "TM sign"; an in-charge then verifies ("Incharge sign").
class CheckRunScreen extends ConsumerStatefulWidget {
  const CheckRunScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<CheckRunScreen> createState() => _CheckRunScreenState();
}

class _Draft {
  PointResult? result;
  final note = TextEditingController();
  Uint8List? photo;
}

class _CheckRunScreenState extends ConsumerState<CheckRunScreen> {
  final Map<String, _Draft> _drafts = {};
  bool _editing = false;
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final d in _drafts.values) {
      d.note.dispose();
    }
    super.dispose();
  }

  _Draft _draft(String pointId) => _drafts.putIfAbsent(pointId, _Draft.new);

  /// Pre-fill from saved results (re-opening a submitted, not yet verified check).
  void _seed(PmTaskDetail d) {
    if (_seeded) return;
    _seeded = true;
    for (final r in d.results.values) {
      _draft(r.pointId)
        ..result = r.result
        ..note.text = r.note ?? '';
    }
  }

  void _refreshLists() {
    ref.invalidate(pmTaskDetailProvider(widget.taskId));
    ref.invalidate(checkTasksProvider);
    ref.invalidate(awaitingVerificationProvider);
    ref.invalidate(findingsProvider);
  }

  Future<void> _submit(PmTaskDetail d) async {
    final missing = d.points.where((p) => _draft(p.id).result == null).length;
    if (missing > 0) {
      showToast(context, '$missing check point${missing == 1 ? '' : 's'} still need a result');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final result = await ref.read(checksRepositoryProvider).submitPmTask(
      taskId: d.task.id,
      equipmentId: d.task.equipmentId,
      results: {
        for (final p in d.points) p.id: (result: _draft(p.id).result!, note: _draft(p.id).note.text, photo: _draft(p.id).photo),
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final abnormal = d.points.where((p) => _draft(p.id).result == PointResult.abnormalPending).length;
    switch (result) {
      case SendResult.sent:
        _refreshLists();
        showToast(context, abnormal == 0 ? '“${d.task.title}” submitted' : '“${d.task.title}” submitted · $abnormal finding${abnormal == 1 ? '' : 's'} raised');
        Navigator.of(context).maybePop();
      case SendResult.offline:
        showToast(context, 'Saved on this device — will sync when you are back online');
        Navigator.of(context).maybePop();
      case SendResult.rejected:
        showToast(context, 'Could not submit this check. It may have been verified or closed already.');
    }
  }

  Future<void> _verify(PmTaskDetail d) async {
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, MediaQuery.viewInsetsOf(ctx).bottom + Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Verify check (in-charge sign)', style: ctx.text.titleMedium),
          const Gap(Space.xs),
          Text('${d.task.title} · done by ${d.task.completedByName ?? 'worker'}', style: ctx.text.bodySmall),
          const Gap(Space.lg),
          TextField(controller: note, maxLength: 1000, decoration: const InputDecoration(labelText: 'Remark (optional)')),
          const Gap(Space.md),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify')),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(checksRepositoryProvider).verifyTask(d.task.id, note: note.text.trim().isEmpty ? null : note.text.trim());
      _refreshLists();
      if (mounted) showToast(context, 'Check verified');
    } catch (_) {
      if (mounted) showToast(context, 'Could not verify — check your connection');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pmTaskDetailProvider(widget.taskId));
    final role = ref.watch(profileProvider).role;
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.task.title ?? 'Check sheet', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: AsyncBody<PmTaskDetail>(
        value: async,
        onRetry: () => ref.invalidate(pmTaskDetailProvider(widget.taskId)),
        data: (d) {
          _seed(d);
          final t = d.task;
          final future = t.dueDate.isAfter(today());
          // Only workers record results; managers / admins (the in-charge) only verify.
          final editable = role == Role.worker && !t.isVerified && !future && (!t.isDone || _editing);
          return PageBody(
            maxWidth: 880,
            onRefresh: () async => ref.invalidate(pmTaskDetailProvider(widget.taskId)),
            children: [
              _HeaderCard(d: d),
              const Gap(Space.md),
              _StatusBanner(task: t, verifyNote: d.verifyNote, future: future, supervisor: role != Role.worker),
              const Gap(Space.md),
              const _Legend(),
              const Gap(Space.md),
              for (final p in d.points) ...[
                _PointCard(
                  point: p,
                  total: d.points.length,
                  urls: d.imageUrls,
                  draft: _draft(p.id),
                  saved: d.results[p.id],
                  editable: editable,
                  onChanged: () => setState(() {}),
                ),
                const Gap(Space.md),
              ],
              const Gap(Space.xxl),
            ],
          );
        },
      ),
      bottomNavigationBar: async.value == null ? null : _bottomBar(context, async.value!, role),
    );
  }

  Widget? _bottomBar(BuildContext context, PmTaskDetail d, Role role) {
    final p = context.palette;
    final t = d.task;
    final answered = d.points.where((pt) => _draft(pt.id).result != null).length;
    Widget? action;
    String? info;
    if (t.dueDate.isAfter(today())) {
      return null;
    } else if (role != Role.worker && !t.isDone) {
      info = 'Waiting for a worker to complete this check';
    } else if (role == Role.worker && (!t.isDone || _editing)) {
      info = '$answered of ${d.points.length} points checked';
      action = FilledButton(
        onPressed: _busy || answered < d.points.length ? null : () => _submit(d),
        child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : Text(t.isDone ? 'Resubmit' : 'Submit check'),
      );
    } else if (!t.isVerified && role.isManagerOrAdmin) {
      info = 'Awaiting in-charge verification';
      action = FilledButton.icon(onPressed: _busy ? null : () => _verify(d), icon: const Icon(Icons.verified_rounded, size: 20), label: const Text('Verify'));
    } else if (!t.isVerified && role == Role.worker) {
      info = 'Submitted · awaiting verification';
      action = OutlinedButton(onPressed: () => setState(() => _editing = true), child: const Text('Edit results'));
    } else {
      return null;
    }
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      padding: const EdgeInsets.all(Space.md),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Row(children: [
              Expanded(child: Text(info, style: context.text.bodyMedium)),
              const Gap(Space.md),
              SizedBox(height: 48, child: action),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.d});
  final PmTaskDetail d;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = d.task;
    Widget fact(IconData icon, String label, String value) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: p.muted),
          const SizedBox(width: 4),
          Text('$label ', style: context.text.bodySmall),
          Text(value.replaceAll('\n', ' · '), style: context.text.bodySmall?.copyWith(color: p.foreground, fontWeight: FontWeight.w600)),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.title, style: context.text.titleMedium),
          const Gap(Space.xs),
          Text('${t.equipmentName} · ${t.equipmentCode}${d.sourceTab != null ? ' · sheet “${d.sourceTab}”' : ''}', style: context.text.bodySmall),
          const Gap(Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            Pill(t.frequencyText, color: p.primary, icon: Icons.repeat_rounded),
            if (t.pmType != null) Pill(t.pmType!.trim(), color: t.pmType!.toUpperCase().contains('ONLINE') ? p.success : p.warning),
            if (d.pmRank != null) Pill('Equipment rank ${d.pmRank}'),
          ]),
          const Gap(Space.md),
          Wrap(spacing: Space.lg, runSpacing: Space.sm, children: [
            fact(Icons.event_rounded, 'Due', formatDayShort(t.dueDate)),
            fact(Icons.hourglass_bottom_rounded, 'Until', formatDayShort(t.windowEnd)),
            if (d.manPower != null) fact(Icons.groups_rounded, 'Man power', d.manPower!),
            if (d.timeMinutes != null) fact(Icons.timer_outlined, 'Time', '${d.timeMinutes} min'),
            if (d.kanbanNo != null) fact(Icons.tag_rounded, 'Kanban', d.kanbanNo!),
          ]),
          if (d.safetyNote != null) ...[
            const Gap(Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.inputAll),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, color: p.danger, size: 20),
                const Gap(Space.sm),
                Expanded(child: Text(d.safetyNote!, style: context.text.bodyMedium?.copyWith(color: p.danger, fontWeight: FontWeight.w700))),
              ]),
            ),
          ],
          if (d.tools != null) ...[
            const Gap(Space.md),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.handyman_outlined, size: 18, color: p.muted),
              const Gap(Space.sm),
              Expanded(child: Text('Tools: ${d.tools}', style: context.text.bodySmall?.copyWith(color: p.foreground))),
            ]),
          ],
          if (d.imagePaths.isNotEmpty) ...[
            const Gap(Space.md),
            _Pictures(paths: d.imagePaths, urls: d.imageUrls),
          ],
        ]),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.task, required this.future, this.verifyNote, this.supervisor = false});
  final bool supervisor;
  final CheckTask task;
  final bool future;
  final String? verifyNote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = task;
    final fmt = DateFormat('d MMM, HH:mm');
    final (IconData icon, Color color, String text) = switch (t) {
      _ when t.isVerified => (
          Icons.verified_rounded,
          p.success,
          'Done by ${t.completedByName ?? '—'} ${t.completedAt != null ? fmt.format(t.completedAt!) : ''} · verified by ${t.verifiedByName ?? 'in-charge'} ${fmt.format(t.verifiedAt!)}${verifyNote != null ? ' — “$verifyNote”' : ''}'
        ),
      _ when t.isDone => (Icons.task_alt_rounded, p.primary, 'Done by ${t.completedByName ?? '—'} ${t.completedAt != null ? fmt.format(t.completedAt!) : ''} · awaiting in-charge verification'),
      _ when future => (Icons.schedule_rounded, p.muted, 'Opens on ${formatDate(t.dueDate)}'),
      _ when t.status == TaskStatus.missed => (Icons.error_outline_rounded, p.danger, 'Missed — the window closed ${formatDate(t.windowEnd)}. You can still record it late.'),
      _ when t.isOverdue(today()) => (Icons.error_outline_rounded, p.warning, 'Overdue — complete by ${formatDate(t.windowEnd)}'),
      _ when supervisor => (Icons.hourglass_empty_rounded, p.muted, 'Not completed yet — a worker records the results, then you verify'),
      _ => (Icons.play_circle_outline_rounded, p.primary, 'Record a result for every check point, then submit'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: Radii.cardAll),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const Gap(Space.sm),
        Expanded(child: Text(text.trim(), style: context.text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

enum SheetSymbol { circle, circleX, triangle, triangleFilled }

/// The paper sheet's result marks, drawn (not font glyphs, which many fonts lack): ○ ⊗ △ ▲.
class ResultSymbol extends StatelessWidget {
  const ResultSymbol(this.symbol, {super.key, this.color, this.size = 16});
  final SheetSymbol symbol;
  final Color? color;
  final double size;

  static SheetSymbol of(PointResult r, {bool pendingCompleted = false}) => switch (r) {
        PointResult.ok => SheetSymbol.circle,
        PointResult.corrected => SheetSymbol.circleX,
        PointResult.abnormalPending => pendingCompleted ? SheetSymbol.triangleFilled : SheetSymbol.triangle,
      };

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SymbolPainter(symbol, color ?? DefaultTextStyle.of(context).style.color ?? Colors.black));
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.symbol, this.color);
  final SheetSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, stroke = w * 0.11;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(w / 2, w / 2), r = w / 2 - stroke;
    switch (symbol) {
      case SheetSymbol.circle:
        canvas.drawCircle(c, r, line);
      case SheetSymbol.circleX:
        canvas.drawCircle(c, r, line);
        final d = r * 0.7071;
        canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), line);
        canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), line);
      case SheetSymbol.triangle:
      case SheetSymbol.triangleFilled:
        final path = Path()
          ..moveTo(w / 2, stroke)
          ..lineTo(w - stroke, w - stroke * 1.5)
          ..lineTo(stroke, w - stroke * 1.5)
          ..close();
        canvas.drawPath(path, symbol == SheetSymbol.triangleFilled ? (Paint()..color = color) : line);
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.symbol != symbol || old.color != color;
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
      for (final (s, l) in const [
        (SheetSymbol.circle, 'OK'),
        (SheetSymbol.circleX, 'Immediate correction'),
        (SheetSymbol.triangle, 'Abnormal – pending'),
        (SheetSymbol.triangleFilled, 'Pending – completed'),
      ])
        Row(mainAxisSize: MainAxisSize.min, children: [ResultSymbol(s, color: muted, size: 13), const SizedBox(width: 4), Text(l, style: context.text.bodySmall)]),
    ]);
  }
}

Color _resultColor(BuildContext context, PointResult r) {
  final p = context.palette;
  return switch (r) { PointResult.ok => p.success, PointResult.corrected => p.primary, PointResult.abnormalPending => p.warning };
}

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.point,
    required this.total,
    required this.urls,
    required this.draft,
    required this.saved,
    required this.editable,
    required this.onChanged,
  });

  final CheckPoint point;
  final int total;
  final Map<String, String> urls;
  final _Draft draft;
  final RecordedResult? saved;
  final bool editable;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pt = point;
    Widget field(String label, String? value, {Color? tint}) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Container(
          width: double.infinity,
          padding: tint == null ? EdgeInsets.zero : const EdgeInsets.all(Space.sm),
          decoration: tint == null ? null : BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: Radii.inputAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: tint ?? p.muted, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value.trim(), style: context.text.bodyMedium),
          ]),
        ),
      );
    }

    final chosen = draft.result;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: BorderSide(color: chosen == null ? p.border : _resultColor(context, chosen).withValues(alpha: 0.6), width: chosen == null ? 1 : 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.primarySoft, shape: BoxShape.circle),
              child: Text(pt.slNo ?? '${pt.position}', style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const Gap(Space.md),
            Expanded(child: Text(pt.checkPoint, style: context.text.titleSmall)),
            if (pt.pmRank != null) ...[const Gap(Space.sm), Pill('Rank ${pt.pmRank}')],
          ]),
          if (pt.imagePaths.isNotEmpty) ...[const Gap(Space.md), _Pictures(paths: pt.imagePaths, urls: urls)],
          field('Standard value', pt.stdValue, tint: p.success),
          field('Checking method', pt.checkingMethod),
          field('Safety point', pt.safetyPoint, tint: p.danger),
          field('Key points', pt.keyPoints),
          field('Action if NG', pt.actionIfNg, tint: p.warning),
          field('If PM not done', pt.ifNotDone),
          const Gap(Space.md),
          if (editable) ...[
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final r in PointResult.values)
                ChoiceChip(
                  avatar: ResultSymbol(ResultSymbol.of(r), color: chosen == r ? _resultColor(context, r) : p.foreground),
                  label: Text(r.label),
                  selected: chosen == r,
                  selectedColor: _resultColor(context, r).withValues(alpha: 0.18),
                  side: BorderSide(color: chosen == r ? _resultColor(context, r) : p.border),
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: chosen == r ? _resultColor(context, r) : p.foreground),
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    draft.result = r;
                    onChanged();
                  },
                ),
            ]),
            const Gap(Space.sm),
            TextField(
              controller: draft.note,
              maxLength: 1000,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText: chosen == PointResult.abnormalPending ? 'What is wrong? (goes into the finding)' : 'Reading / remark (optional)',
                hintText: chosen == PointResult.abnormalPending ? 'e.g. hose cracked near fitting' : 'e.g. 57 °C',
              ),
              onChanged: (_) {},
            ),
            if (chosen == PointResult.abnormalPending && saved?.findingId == null) ...[
              const Gap(Space.sm),
              PhotoPickerField(
                photo: draft.photo,
                hint: 'Photo of the problem (optional)',
                onChanged: (b) {
                  draft.photo = b;
                  onChanged();
                },
              ),
            ],
          ] else if (saved != null)
            Row(children: [
              Builder(builder: (context) {
                final color = saved!.pendingCompleted ? p.success : _resultColor(context, saved!.result);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.pill)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ResultSymbol(ResultSymbol.of(saved!.result, pendingCompleted: saved!.pendingCompleted), color: color, size: 13),
                    const SizedBox(width: 6),
                    Text(saved!.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ]),
                );
              }),
              if (saved!.note != null) ...[const Gap(Space.sm), Expanded(child: Text(saved!.note!, style: context.text.bodySmall))],
            ])
          else
            Text('Not checked yet', style: context.text.bodySmall),
        ]),
      ),
    );
  }
}

/// Thumbnails of sheet pictures; tap to zoom.
class _Pictures extends StatelessWidget {
  const _Pictures({required this.paths, required this.urls});
  final List<String> paths;
  final Map<String, String> urls;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const Gap(Space.sm),
        itemBuilder: (_, i) {
          final url = urls[paths[i]];
          final placeholder = Container(
            width: 120,
            color: p.surfaceMuted,
            alignment: Alignment.center,
            child: Icon(Icons.image_not_supported_outlined, color: p.muted),
          );
          return ClipRRect(
            borderRadius: Radii.inputAll,
            child: url == null
                ? placeholder
                : InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog.fullscreen(
                        backgroundColor: Colors.black,
                        child: Stack(children: [
                          Positioned.fill(child: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(url, fit: BoxFit.contain)))),
                          Positioned(
                            top: Space.md,
                            right: Space.md,
                            child: SafeArea(child: IconButton.filledTonal(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded))),
                          ),
                        ]),
                      ),
                    ),
                    child: Image.network(url, width: 160, height: 120, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
                  ),
          );
        },
      ),
    );
  }
}
