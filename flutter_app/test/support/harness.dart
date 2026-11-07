import 'dart:io';

import 'package:equipment_portal/core/router.dart';
import 'package:equipment_portal/core/theme/app_theme.dart';
import 'package:equipment_portal/data/checks.dart';
import 'package:equipment_portal/data/equipment_repo.dart';
import 'package:equipment_portal/features/history/history_screen.dart';
import 'package:equipment_portal/data/models.dart';
import 'package:equipment_portal/data/offline_queue.dart';
import 'package:equipment_portal/data/providers.dart';
import 'package:equipment_portal/data/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_data.dart' as fake;

bool _fontsLoaded = false;

/// Loads Inter + Material Icons so golden screenshots show real text and icons.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Inter', ['Regular', 'Medium', 'SemiBold', 'Bold'].map((w) => 'assets/fonts/Inter-$w.ttf').toList());
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\Admin\develop\flutter';
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
  _fontsLoaded = true;
}

/// The real app (router, shell, theme) with every data provider swapped for sample data.
Widget testApp({required Profile profile, required String location, Brightness brightness = Brightness.light}) {
  final session = SessionController.fixed(profile);
  return ProviderScope(
    overrides: [
      sessionControllerProvider.overrideWith((ref) => session),
      offlineQueueProvider.overrideWith((ref) => OfflineQueue.disabled()),
      plantsProvider.overrideWith((ref) async => fake.plants),
      statusTypesProvider.overrideWith((ref) async => fake.statusTypes),
      currentStatusProvider.overrideWith((ref, plantId) async => fake.currentStatus.where((r) => plantId == null || r.plantId == plantId).toList()),
      recentEventsProvider.overrideWith((ref, plantId) async => fake.recentEvents),
      statusEventsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
      notificationsProvider.overrideWith(
        (ref) => Stream.value([
          AppNotification(id: 'n1', kind: 'failure', message: 'Hydraulic Press 1 is Down', createdAt: DateTime.now()),
          AppNotification(id: 'n2', kind: 'check_due', message: '18 checks due today', createdAt: DateTime.now()),
          AppNotification(id: 'n3', kind: 'finding_overdue', message: 'Overdue fix', createdAt: DateTime.now()),
        ]),
      ),
      checkTasksProvider.overrideWith((ref, equipmentId) async => fake.checkTasks),
      checkStatsProvider.overrideWith((ref, k) async => fake.checkStats(k.days)),
      findingStatsProvider.overrideWith((ref, k) async => fake.findingStats(k.days)),
      findingsProvider.overrideWith((ref, eq) async => fake.findings.where((f) => eq == null || f.equipmentId == eq).toList()),
      equipmentListProvider.overrideWith((ref, q) async {
        final rows = fake.currentStatus
            .where((r) => q.q.isEmpty || r.name.toLowerCase().contains(q.q.toLowerCase()))
            .where((r) => q.plantId == null || r.plantId == q.plantId)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return (rows: rows, total: rows.length);
      }),
      equipmentDetailProvider.overrideWith((ref, id) async => fake.equipmentDetail),
      equipmentEventsProvider.overrideWith((ref, id) async => (events: fake.equipmentEvents, photos: const <String, String>{})),
      historyProvider.overrideWith((ref, f) async => [...fake.equipmentEvents, ...fake.recentEvents]),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      routerConfig: buildRouter(session, initialLocation: location),
    ),
  );
}

enum Device {
  phone(Size(390, 844), 2),
  phoneTall(Size(390, 1900), 2),
  laptop(Size(1440, 960), 1),
  laptopTall(Size(1440, 1700), 1);

  const Device(this.size, this.dpr);
  final Size size;
  final double dpr;
}

Future<void> setDevice(WidgetTester tester, Device d) async {
  tester.view.physicalSize = d.size * d.dpr;
  tester.view.devicePixelRatio = d.dpr;
  // Phones have a status bar / camera cut-out at the top and a gesture bar at the bottom.
  if (d.size.width < 600) {
    tester.view.padding = FakeViewPadding(top: 32 * d.dpr, bottom: 16 * d.dpr);
    tester.view.viewPadding = FakeViewPadding(top: 32 * d.dpr, bottom: 16 * d.dpr);
  }
  addTearDown(tester.view.reset);
}

/// Pump until async providers resolve and entry animations finish (bounded: shimmers loop forever).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
