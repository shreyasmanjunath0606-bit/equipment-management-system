import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'layout.dart';

/// Opens a form: bottom sheet on phones, centred dialog on laptops. Returns the popped value.
Future<T?> showFormSheet<T>(BuildContext context, {required String title, String? subtitle, required Widget Function(BuildContext) builder}) {
  Widget content(BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: ctx.text.titleMedium),
        if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: ctx.text.bodySmall)],
        const SizedBox(height: Space.xl),
        builder(ctx),
      ]);

  if (isDesktop(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(padding: const EdgeInsets.all(Space.xl), child: content(ctx)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl), child: content(ctx)),
      ),
    ),
  );
}

/// Primary submit button with a spinner while busy.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.busy, required this.label, required this.onPressed, this.icon});
  final bool busy;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
            : Icon(icon ?? Icons.check_rounded, size: 20),
        label: Text(label),
      );
}
