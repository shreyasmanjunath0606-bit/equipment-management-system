import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../data/models.dart';
import '../../data/offline_queue.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import 'nav_items.dart';

/// Signed-in frame: sidebar on laptops, top bar + bottom tabs on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final pending = ref.watch(offlineQueueProvider).pending;
    final child = Column(
      children: [
        if (pending > 0) _OfflineBanner(pending: pending, onRetry: () => ref.read(offlineQueueProvider).flush()),
        Expanded(child: this.child),
      ],
    );
    if (isDesktop(context)) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(location: location, profile: profile),
            VerticalDivider(width: 1, color: context.palette.border),
            Expanded(
              child: Column(
                children: [
                  _TopBar(profile: profile, showLogo: false),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final tabs = mobileTabsFor(profile.role);
    final idx = tabs.indexWhere((t) => isActivePath(location, t.path));
    final selected = idx >= 0 ? idx : tabs.length; // "More" for everything else
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(_TopBar.height + MediaQuery.paddingOf(context).top),
        child: _TopBar(profile: profile, showLogo: true),
      ),
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) => context.go(i < tabs.length ? tabs[i].path : '/more'),
          destinations: [
            for (final t in tabs)
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label == 'My checks' ? 'Checks' : t.label),
            const NavigationDestination(icon: Icon(Icons.menu_rounded), selectedIcon: Icon(Icons.menu_open_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.pending, required this.onRetry});
  final int pending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.warningSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: p.warning),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                '$pending update${pending == 1 ? '' : 's'} saved on this device — will sync when you are back online',
                style: TextStyle(fontSize: 13, color: p.foreground),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.subtitle = true});
  final bool subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.factory_rounded, color: Colors.white, size: 19),
        ),
        const SizedBox(width: Space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Equipment Portal', style: context.text.titleSmall),
            if (subtitle) Text('Plant operations', style: context.text.bodySmall?.copyWith(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, required this.profile});
  final String location;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = itemsFor(profile.role);
    Widget group(String? label, List<NavItem> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
                    child: Text(label.toUpperCase(), style: context.text.labelSmall),
                  ),
                for (final i in list) _SidebarTile(item: i, active: isActivePath(location, i.path)),
              ],
            ),
          );

    return Container(
      width: Breakpoints.sidebarWidth,
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: InkWell(onTap: () => context.go(homeFor(profile.role)), child: const AppLogo()),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.xl, Space.md, Space.lg),
              children: [
                group(null, items.where((i) => i.group == NavGroup.main).toList()),
                group('Administration', items.where((i) => i.group == NavGroup.admin).toList()),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Text('v1.0 · Signed in as ${profile.role.label}', style: context.text.bodySmall?.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.item, required this.active});
  final NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? p.primarySoft : Colors.transparent,
        borderRadius: Radii.inputAll,
        child: InkWell(
          borderRadius: Radii.inputAll,
          onTap: () => context.go(item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
            child: Row(
              children: [
                Icon(active ? item.selectedIcon : item.icon, size: 20, color: active ? p.primary : p.muted),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(fontSize: 14, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? p.primary : p.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.profile, required this.showLogo});
  final Profile profile;
  final bool showLogo;

  static const double height = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final unread = ref.watch(unreadCountProvider);
    // The phone status bar sits above the 64px bar, not inside it.
    final topInset = MediaQuery.paddingOf(context).top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
      child: Material(
        color: p.surface,
        child: Container(
          height: _TopBar.height + topInset,
          padding: EdgeInsets.fromLTRB(isDesktop(context) ? Space.xl : Space.lg, topInset, isDesktop(context) ? Space.xl : Space.md, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: SizedBox(
            height: _TopBar.height,
            child: Row(
              children: [
                if (showLogo) InkWell(onTap: () => context.go(homeFor(profile.role)), child: const AppLogo(subtitle: false)),
                const Spacer(),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.push('/notifications'),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    backgroundColor: p.danger,
                    child: Icon(Icons.notifications_none_rounded, color: p.muted),
                  ),
                ),
                const SizedBox(width: Space.xs),
                _UserMenu(profile: profile),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: BorderSide(color: p.border),
      ),
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      onSelected: (v) async {
        if (v == 'signout') await ref.read(sessionControllerProvider).signOut();
        if (v == 'password' && context.mounted) context.push('/set-password');
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: context.text.titleSmall),
              Text(profile.email, style: context.text.bodySmall),
              const SizedBox(height: Space.xs),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(leading: Icon(Icons.lock_reset_rounded), title: Text('Change password'), contentPadding: EdgeInsets.zero),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Sign out'), contentPadding: EdgeInsets.zero),
        ),
      ],
      child: CircleAvatar(
        radius: 17,
        backgroundColor: p.primary,
        child: Text(
          profile.initials,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
