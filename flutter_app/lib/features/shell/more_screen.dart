import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../data/session.dart';
import 'nav_items.dart';

/// Phone "More" tab: everything that isn't a bottom tab, plus account actions.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final tabs = mobileTabsFor(profile.role).map((t) => t.path).toSet();
    final rest = itemsFor(profile.role).where((i) => !tabs.contains(i.path)).toList();
    final main = rest.where((i) => i.group == NavGroup.main).toList();
    final admin = rest.where((i) => i.group == NavGroup.admin).toList();
    final p = context.palette;

    Widget section(String label, List<Widget> tiles) => Padding(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
                child: Text(label.toUpperCase(), style: context.text.labelSmall),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const Divider(indent: 56), tiles[i]],
                ]),
              ),
            ],
          ),
        );

    ListTile tile(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          minTileHeight: 56,
          leading: Icon(icon, color: color),
          title: Text(label, style: color == null ? null : TextStyle(color: color, fontWeight: FontWeight.w500)),
          trailing: color == null ? Icon(Icons.chevron_right_rounded, color: p.muted) : null,
          onTap: onTap,
        );

    return PageBody(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: p.primary,
              child: Text(profile.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.name, style: context.text.titleMedium),
                Text(profile.email, style: context.text.bodySmall),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Text(profile.role.label, style: TextStyle(color: p.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      const Gap(Space.xl),
      if (main.isNotEmpty) section('Workspace', [for (final i in main) tile(i.icon, i.label, () => context.go(i.path))]),
      if (admin.isNotEmpty) section('Administration', [for (final i in admin) tile(i.icon, i.label, () => context.go(i.path))]),
      section('Account', [
        tile(Icons.lock_reset_rounded, 'Change password', () => context.push('/set-password')),
        tile(Icons.logout_rounded, 'Sign out', () => ref.read(sessionControllerProvider).signOut(), color: p.danger),
      ]),
      Center(child: Text('Equipment Portal v1.0', style: context.text.bodySmall)),
    ]);
  }
}
