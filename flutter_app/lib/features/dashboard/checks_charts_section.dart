import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../data/checks.dart';

/// Dashboard section with the four daily KPI charts:
/// plan vs actual, cumulative completion, findings per day, findings solved vs total.
class ChecksChartsSection extends ConsumerStatefulWidget {
  const ChecksChartsSection({super.key, this.plantId});
  final String? plantId;

  @override
  ConsumerState<ChecksChartsSection> createState() => _ChecksChartsSectionState();
}

class _ChecksChartsSectionState extends ConsumerState<ChecksChartsSection> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final key = (plantId: widget.plantId, days: _days);
    final checks = ref.watch(checkStatsProvider(key));
    final findings = ref.watch(findingStatsProvider(key));
    void retry() {
      ref.invalidate(checkStatsProvider(key));
      ref.invalidate(findingStatsProvider(key));
    }

    final header = Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: Space.md,
        spacing: Space.lg,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Checks & findings', style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text('Daily progress of scheduled checks and problems found', style: context.text.bodySmall),
          ]),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
        ],
      ),
    );

    Widget chartCard({required String title, required String takeaway, required Widget legend, required Widget chart}) => SectionCard(
          title: title,
          subtitle: takeaway,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            legend,
            const SizedBox(height: Space.md),
            Padding(padding: const EdgeInsets.only(right: Space.md), child: SizedBox(height: 200, child: chart)),
          ]),
        );

    final p = context.palette;
    final planColor = p.muted.withValues(alpha: 0.35);
    final doneColor = p.primary;
    final foundColor = p.warning;
    final solvedColor = p.success;

    Widget body = AsyncBody<List<DailyCheckStat>>(
      value: checks,
      onRetry: retry,
      loading: ResponsiveGrid(minItemWidth: 420, children: List.generate(4, (_) => const SkeletonBox(height: 300, radius: Radii.card))),
      data: (c) {
        final f = findings.value ?? const <DailyFindingStat>[];
        final totPlanned = c.fold<int>(0, (a, s) => a + s.planned);
        final totDone = c.fold<int>(0, (a, s) => a + s.completed);
        final pct = totPlanned == 0 ? null : (totDone * 100 / totPlanned).round();
        final last = c.isEmpty ? null : c.last;
        final cumPct = (last == null || last.cumPlanned == 0) ? null : (last.cumCompleted * 100 / last.cumPlanned).round();
        final totFound = f.fold<int>(0, (a, s) => a + s.found);
        final lastF = f.isEmpty ? null : f.last;
        final open = lastF == null ? 0 : lastF.cumFound - lastF.cumResolved;

        return ResponsiveGrid(
          minItemWidth: 420,
          children: [
            chartCard(
              title: 'Plan vs actual',
              takeaway: pct == null ? 'No checks were scheduled in this period' : '$pct% of planned checks done ($totDone of $totPlanned)',
              legend: _Legend(items: [('Planned', planColor), ('Completed', doneColor)]),
              chart: _GroupedBars(days: c.map((s) => s.day).toList(), a: c.map((s) => s.planned).toList(), b: c.map((s) => s.completed).toList(), aColor: planColor, bColor: doneColor, aLabel: 'Planned', bLabel: 'Completed'),
            ),
            chartCard(
              title: 'Cumulative completion',
              takeaway: cumPct == null ? 'No checks yet' : '$cumPct% of all tasks to date are done (${last!.cumCompleted} of ${last.cumPlanned})',
              legend: _Legend(items: [('Total tasks', planColor), ('Done', doneColor)]),
              chart: _Lines(days: c.map((s) => s.day).toList(), a: c.map((s) => s.cumPlanned).toList(), b: c.map((s) => s.cumCompleted).toList(), aColor: p.muted, bColor: doneColor, aLabel: 'Total', bLabel: 'Done'),
            ),
            chartCard(
              title: 'Problems found',
              takeaway: totFound == 0 ? 'No problems reported in this period' : '$totFound problem${totFound == 1 ? '' : 's'} found while checking',
              legend: _Legend(items: [('Findings', foundColor)]),
              chart: _GroupedBars(days: f.map((s) => s.day).toList(), a: f.map((s) => s.found).toList(), aColor: foundColor, aLabel: 'Found'),
            ),
            chartCard(
              title: 'Findings solved',
              takeaway: lastF == null || lastF.cumFound == 0 ? 'No findings yet' : '${lastF.cumResolved} of ${lastF.cumFound} solved · $open still open',
              legend: _Legend(items: [('Total findings', foundColor), ('Solved', solvedColor)]),
              chart: _Lines(days: f.map((s) => s.day).toList(), a: f.map((s) => s.cumFound).toList(), b: f.map((s) => s.cumResolved).toList(), aColor: foundColor, bColor: solvedColor, aLabel: 'Total', bLabel: 'Solved'),
            ),
          ],
        );
      },
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, body]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
      for (final (label, color) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: context.text.labelMedium),
        ]),
    ]);
  }
}

/// Shared axis styling: a handful of date labels along the bottom, integer labels on the left.
FlTitlesData _titles(BuildContext context, List<DateTime> days, double maxY) {
  final style = context.text.bodySmall?.copyWith(fontSize: 10);
  final every = math.max(1, (days.length / 6).ceil());
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 14.0 + 7 * maxY.toInt().toString().length,
        interval: _niceInterval(maxY),
        getTitlesWidget: (v, meta) => v == meta.max && v != meta.min && v % _niceInterval(maxY) != 0
            ? const SizedBox.shrink()
            : SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: style)),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= days.length || v != i.toDouble()) return const SizedBox.shrink();
          final show = i == days.length - 1 || (i % every == 0 && days.length - 1 - i >= every / 2);
          return show ? SideTitleWidget(meta: meta, child: Text(formatDayShort(days[i]), style: style)) : const SizedBox.shrink();
        },
      ),
    ),
  );
}

double _niceInterval(double maxY) {
  if (maxY <= 5) return 1;
  final raw = maxY / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / mag;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * mag;
}

FlGridData _grid(BuildContext context, double maxY) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: _niceInterval(maxY),
      getDrawingHorizontalLine: (_) => FlLine(color: context.palette.border, strokeWidth: 1, dashArray: [3, 3]),
    );

class _GroupedBars extends StatelessWidget {
  const _GroupedBars({required this.days, required this.a, this.b, required this.aColor, this.bColor, required this.aLabel, this.bLabel});
  final List<DateTime> days;
  final List<int> a;
  final List<int>? b;
  final Color aColor;
  final Color? bColor;
  final String aLabel;
  final String? bLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxV = [...a, ...?b].fold<int>(0, math.max).toDouble();
    final maxY = maxV <= 0 ? 4.0 : maxV * 1.15;
    final pair = b != null;
    final rodW = (days.length <= 10 ? 12.0 : days.length <= 31 ? 5.0 : 2.0) * (pair ? 1 : 1.6);
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceBetween,
        gridData: _grid(context, maxY),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, days, maxY),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => p.foreground,
            tooltipBorderRadius: BorderRadius.circular(8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, _, _, _) {
              final i = group.x;
              final lines = '${formatDayShort(days[i])}\n$aLabel: ${a[i]}${pair ? '\n$bLabel: ${b![i]}' : ''}';
              return BarTooltipItem(lines, TextStyle(color: p.surface, fontSize: 12, fontWeight: FontWeight.w500, fontFamily: AppTheme.fontFamily));
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(toY: a[i].toDouble(), color: aColor, width: rodW, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                if (pair) BarChartRodData(toY: b![i].toDouble(), color: bColor, width: rodW, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.days, required this.a, required this.b, required this.aColor, required this.bColor, required this.aLabel, required this.bLabel});
  final List<DateTime> days;
  final List<int> a, b;
  final Color aColor, bColor;
  final String aLabel, bLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxV = [...a, ...b].fold<int>(0, math.max).toDouble();
    final maxY = maxV <= 0 ? 4.0 : maxV * 1.15;
    LineChartBarData line(List<int> v, Color c, {bool fill = false, bool dashed = false}) => LineChartBarData(
          spots: [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i].toDouble())],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 2.5,
          dashArray: dashed ? [5, 4] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: fill, color: c.withValues(alpha: 0.10)),
        );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: 0,
        maxX: math.max(0, days.length - 1).toDouble(),
        gridData: _grid(context, maxY),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, days, maxY),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.foreground,
            tooltipBorderRadius: BorderRadius.circular(8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? '${formatDayShort(days[s.x.toInt()])}\n' : ''}${s.barIndex == 0 ? aLabel : bLabel}: ${s.y.toInt()}',
                  TextStyle(color: p.surface, fontSize: 12, fontWeight: FontWeight.w500, fontFamily: AppTheme.fontFamily),
                ),
            ],
          ),
        ),
        lineBarsData: [line(a, aColor, dashed: true), line(b, bColor, fill: true)],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}
