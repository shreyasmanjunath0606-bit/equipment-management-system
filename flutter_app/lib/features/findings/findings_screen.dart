import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../data/checks.dart';
import 'finding_tile.dart';

enum _FTab { open, overdue, solved }

/// All problems found while checking: open / overdue (scheduled fix time passed) / solved.
class FindingsScreen extends ConsumerStatefulWidget {
  const FindingsScreen({super.key});

  @override
  ConsumerState<FindingsScreen> createState() => _FindingsScreenState();
}

class _FindingsScreenState extends ConsumerState<FindingsScreen> {
  _FTab _tab = _FTab.open;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(findingsProvider(null));
    Future<void> refresh() async {
      ref.invalidate(findingsProvider);
      await ref.read(findingsProvider(null).future);
    }

    return PageBody(
      maxWidth: 880,
      onRefresh: refresh,
      children: [
        const PageHeader(title: 'Findings', subtitle: 'Problems found during checks, and whether they are fixed.'),
        AsyncBody<List<Finding>>(
          value: async,
          onRetry: refresh,
          data: (all) {
            final now = DateTime.now();
            final overdue = all.where((f) => f.isOverdue(now)).toList();
            final open = all.where((f) => f.status != FindingStatus.resolved && !f.isOverdue(now)).toList();
            final solved = all.where((f) => f.status == FindingStatus.resolved).toList();
            final list = switch (_tab) { _FTab.open => open, _FTab.overdue => overdue, _FTab.solved => solved };
            final p = context.palette;

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_FTab>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(minimumSize: const Size(0, 44)),
                  segments: [
                    ButtonSegment(value: _FTab.open, label: Text('Open · ${open.length}')),
                    ButtonSegment(value: _FTab.overdue, label: Text('Overdue · ${overdue.length}', style: overdue.isEmpty ? null : TextStyle(color: p.danger))),
                    ButtonSegment(value: _FTab.solved, label: Text('Solved · ${solved.length}')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              const Gap(Space.lg),
              if (list.isEmpty)
                Card(
                  child: switch (_tab) {
                    _FTab.open => const EmptyState(icon: Icons.verified_outlined, title: 'No open problems', message: 'Use "Report a problem" on any check or machine when something needs fixing.'),
                    _FTab.overdue => const EmptyState(icon: Icons.thumb_up_alt_outlined, title: 'Nothing overdue', message: 'Fixes that pass their scheduled time show up here, and managers are alerted.'),
                    _FTab.solved => const EmptyState(icon: Icons.history_rounded, title: 'Nothing solved yet'),
                  },
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      FindingTile(finding: list[i]),
                    ],
                  ]),
                ),
              if (_tab != _FTab.solved && list.isNotEmpty) ...[
                const Gap(Space.md),
                Text('Tap a finding to mark it solved or change its fix time.', textAlign: TextAlign.center, style: context.text.bodySmall),
              ],
            ]);
          },
        ),
      ],
    );
  }
}
