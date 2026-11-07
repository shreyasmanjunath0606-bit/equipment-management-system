// Design review screenshots. Generate / refresh with:
//   flutter test test/screenshots --update-goldens
// PNGs land in test/screenshots/goldens/.
@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data.dart' as fake;
import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  final cases = <(String, String, Device, Brightness, bool)>[
    ('dashboard_laptop', '/dashboard', Device.laptopTall, Brightness.light, true),
    ('dashboard_laptop_dark', '/dashboard', Device.laptopTall, Brightness.dark, true),
    ('dashboard_phone', '/dashboard', Device.phoneTall, Brightness.light, true),
    ('checks_phone', '/checks', Device.phone, Brightness.light, false),
    ('checks_phone_dark', '/checks', Device.phone, Brightness.dark, false),
    ('checks_laptop', '/checks', Device.laptop, Brightness.light, false),
    ('more_phone', '/more', Device.phone, Brightness.light, false),
    ('equipment_phone', '/equipment', Device.phone, Brightness.light, false),
    ('equipment_laptop', '/equipment', Device.laptop, Brightness.light, true),
    ('equipment_detail_laptop', '/equipment/e2', Device.laptop, Brightness.light, true),
    ('equipment_detail_phone', '/equipment/e2', Device.phoneTall, Brightness.light, false),
    ('report_phone', '/equipment/e2/report', Device.phone, Brightness.light, false),
    ('findings_phone', '/findings', Device.phone, Brightness.light, false),
    ('history_laptop', '/history', Device.laptop, Brightness.dark, true),
    ('qr_phone', '/equipment/e2/qr', Device.phone, Brightness.light, true),
  ];

  for (final (name, path, device, brightness, asManager) in cases) {
    testWidgets(name, (tester) async {
      await setDevice(tester, device);
      await tester.pumpWidget(testApp(profile: asManager ? fake.manager : fake.worker, location: path, brightness: brightness));
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }
}
