import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Friendly empty state: soft icon, title, one-line explanation, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.compact = false});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Space.xl, vertical: compact ? Space.xl : Space.xxl + Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: p.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icon, color: p.muted, size: 26),
          ),
          const SizedBox(height: Space.lg),
          Text(title, style: context.text.titleSmall, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Space.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(message!, style: context.text.bodySmall, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: Space.lg), action!],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error.toString().contains('SocketException') || error.toString().contains('Failed host lookup');
    return EmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? "You're offline" : 'Something went wrong',
      message: offline ? 'Check your connection and try again.' : 'We could not load this. Please try again.',
      action: onRetry == null
          ? null
          : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry')),
    );
  }
}

/// Grey shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Shimmer.fromColors(
      baseColor: p.surfaceMuted,
      highlightColor: Color.lerp(p.surfaceMuted, p.surface, 0.6)!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5, this.rowHeight = 56});
  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: SkeletonBox(height: rowHeight, radius: Radii.input),
          ),
      ],
    );
  }
}

/// Renders an [AsyncValue] with consistent loading / error states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.loading, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => loading ?? const SkeletonList(),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry),
    );
  }
}

/// Bottom-sheet confirmation for destructive or important actions. Returns true if confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final p = context.palette;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: ctx.text.titleMedium),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              Text(message, style: ctx.text.bodyMedium?.copyWith(color: p.muted)),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(
              style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 4)));
}
