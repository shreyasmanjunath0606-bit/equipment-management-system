import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Soft-tinted pill with a coloured dot. Status colours come from the database.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});
  final StatusType? status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = status?.color ?? p.muted;
    final label = status?.label ?? 'No status yet';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: status == null ? p.surfaceMuted : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: status == null ? p.border : color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w500, color: status == null ? p.muted : p.foreground),
          ),
        ],
      ),
    );
  }
}

/// Generic small pill (e.g. "Active", "Retired", role names).
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color == null ? p.surfaceMuted : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

enum Tone { primary, success, warning, danger, muted }

extension ToneColors on Tone {
  (Color fg, Color bg) colors(AppPalette p) => switch (this) {
        Tone.primary => (p.primary, p.primarySoft),
        Tone.success => (p.success, p.successSoft),
        Tone.warning => (p.warning, p.warningSoft),
        Tone.danger => (p.danger, p.dangerSoft),
        Tone.muted => (p.muted, p.surfaceMuted),
      };
}

/// Dashboard KPI tile: label, big number, hint, tinted icon.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.hint, required this.icon, this.tone = Tone.primary, this.onTap});

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fg, bg) = tone.colors(p);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: context.text.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: fg),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(value, style: context.text.displaySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text(hint ?? ' ', style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal stacked bar of status counts.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.segments, this.height = 12});
  final List<({StatusType? status, int count})> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = segments.fold<int>(0, (a, s) => a + s.count);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: SizedBox(
        height: height,
        child: total == 0
            ? Container(color: p.surfaceMuted)
            : Row(
                children: [
                  for (final s in segments.where((s) => s.count > 0))
                    Expanded(
                      flex: s.count,
                      child: Container(
                        margin: const EdgeInsets.only(right: 1.5),
                        color: s.status?.color ?? p.border,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
