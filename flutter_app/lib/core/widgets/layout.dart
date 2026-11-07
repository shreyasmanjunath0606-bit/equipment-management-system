import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

/// Standard scrollable page body: max content width, consistent gutters, optional pull-to-refresh.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.padding, this.maxWidth = Breakpoints.contentMax});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsets? padding;

  /// Narrower for reading/list pages (e.g. 880), full content width for dashboards.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final pad = padding ??
        EdgeInsets.fromLTRB(
          desktop ? Space.xxl : Space.lg,
          desktop ? Space.xl : Space.lg,
          desktop ? Space.xxl : Space.lg,
          Space.xxl,
        );
    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pad,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    return list;
  }
}

/// Page title + one-line description + actions. Actions wrap under the title on phones.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: context.text.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: Space.xs),
          Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: isWide(context)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: titleBlock),
                if (actions.isNotEmpty) Wrap(spacing: Space.sm, runSpacing: Space.sm, children: actions),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Wrap(spacing: Space.sm, runSpacing: Space.sm, children: actions),
                ],
              ],
            ),
    );
  }
}

/// A bordered card with an optional header row (title, subtitle, trailing action).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.md, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: context.text.titleSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.text.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Lays children out in [columns] equal columns on wide screens and stacks them on phones.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 280, this.spacing = Space.lg});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minItemWidth).floor().clamp(1, children.length.clamp(1, 4));
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}
