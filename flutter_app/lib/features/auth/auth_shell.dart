import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../shell/app_shell.dart';

/// Centered card layout for sign-in style pages.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo()),
                  const SizedBox(height: Space.xxl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title, style: context.text.titleLarge),
                          if (subtitle != null) ...[
                            const SizedBox(height: Space.xs),
                            Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                          ],
                          const SizedBox(height: Space.xl),
                          child,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      margin: const EdgeInsets.only(bottom: Space.lg),
      decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.inputAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(message, style: TextStyle(color: p.danger, fontSize: 13))),
      ]),
    );
  }
}
