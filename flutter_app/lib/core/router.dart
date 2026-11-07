import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/session.dart';
import '../features/admin/admin_equipment_screen.dart';
import '../features/admin/admin_plants_screen.dart';
import '../features/admin/admin_users_screen.dart';
import '../features/admin/check_sheets_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/equipment/equipment_detail_screen.dart';
import '../features/equipment/equipment_list_screen.dart';
import '../features/equipment/qr_label_screen.dart';
import '../features/equipment/report_status_screen.dart';
import '../features/equipment/scan_screen.dart';
import '../features/findings/findings_screen.dart';
import '../features/history/history_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/checks/my_checks_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/more_screen.dart';
import '../features/shell/nav_items.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';

/// Screens registered so far; the rest are added as they are ported.
typedef ScreenBuilder = Widget Function(BuildContext context, GoRouterState state);

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionControllerProvider.notifier);
  return buildRouter(session);
});

GoRouter buildRouter(SessionController session, {String initialLocation = '/'}) {
  // Paths only managers/admins may open; admin-only paths.
  const managerOnly = ['/dashboard', '/admin/equipment', '/admin/check-sheets'];
  const adminOnly = ['/admin/users', '/admin/plants'];

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: session,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final s = session.status;
      if (s == SessionStatus.loading) return loc == '/splash' ? null : '/splash';

      final atAuth = loc == '/login' || loc == '/splash';
      if (s == SessionStatus.signedOut || s == SessionStatus.deactivated) {
        if (loc == '/login') return null;
        // Remember where they were going (e.g. a scanned QR link) and come back after sign-in.
        final next = loc == '/' || loc == '/splash' ? null : state.uri.toString();
        return Uri(path: '/login', queryParameters: {'next': ?next}).toString();
      }
      if (s == SessionStatus.needsPassword) return loc == '/set-password' ? null : '/set-password';

      final role = session.role;
      if (atAuth || loc == '/') {
        final next = state.uri.queryParameters['next'];
        if (next != null && next.startsWith('/') && !next.startsWith('//')) return next;
        return homeFor(role);
      }
      bool under(String p) => loc == p || loc.startsWith('$p/');
      if (managerOnly.any(under) && !role.isManagerOrAdmin) return homeFor(role);
      if (adminOnly.any(under) && role != Role.admin) return homeFor(role);
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, s) => LoginScreen(reason: s.uri.queryParameters['reason'])),
      GoRoute(path: '/set-password', builder: (_, _) => const SetPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, s) => DashboardScreen(plantId: s.uri.queryParameters['plant'])),
          GoRoute(path: '/checks', builder: (_, _) => const MyChecksScreen()),
          GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
          GoRoute(
            path: '/equipment',
            builder: (_, s) => EquipmentListScreen(
              initialPlant: s.uri.queryParameters['plant'],
              initialStatus: s.uri.queryParameters['status'],
              initialQuery: s.uri.queryParameters['q'],
            ),
          ),
          GoRoute(path: '/equipment/:id', builder: (_, s) => EquipmentDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/equipment/:id/report', builder: (_, s) => ReportStatusScreen(id: s.pathParameters['id']!)),
          // Old QR labels from the web portal point here.
          GoRoute(path: '/equipment/:id/update', redirect: (_, s) => '/equipment/${s.pathParameters['id']}/report'),
          GoRoute(path: '/equipment/:id/qr', builder: (_, s) => QrLabelScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/e/:code', builder: (_, s) => CodeLinkScreen(code: s.pathParameters['code']!)),
          GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
          GoRoute(path: '/findings', builder: (_, _) => const FindingsScreen()),
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: '/admin/equipment', builder: (_, _) => const AdminEquipmentScreen()),
          GoRoute(path: '/admin/check-sheets', builder: (_, _) => const CheckSheetsScreen()),
          GoRoute(path: '/admin/users', builder: (_, _) => const AdminUsersScreen()),
          GoRoute(path: '/admin/plants', builder: (_, _) => const AdminPlantsScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: 'The page you are looking for does not exist.',
        action: FilledButton(onPressed: () => context.go('/'), child: const Text('Go home')),
      ),
    ),
  );
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AppLogo(),
            const SizedBox(height: 28),
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: context.palette.primary)),
          ]),
        ),
      );
}
