import 'package:equipment_portal/data/assignments.dart';
import 'package:equipment_portal/data/checks.dart';
import 'package:equipment_portal/data/pm_workbook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinal day names', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(ordinal), ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
  });

  test('slot schedules', () {
    expect(SheetSlot.daily.schedule(), 'Every day');
    expect(SheetSlot.weekly.schedule(), 'Every Monday');
    expect(SheetSlot.monthly.schedule(monthlyDay: 5), 'Monthly on the 5th');
    expect(SheetSlot.parse('nonsense'), SheetSlot.extra);
  });

  test('a Daily/Weekly/Monthly upload overrides each tab\'s FREQUENCY, including unreadable ones', () {
    final unreadable = PmCheck(tab: 'A', title: 'A')
      ..frequencyText = 'twice a week'
      ..frequencyProblem = 'Frequency "twice a week" not recognised';
    final halfYearly = PmCheck(tab: 'B', title: 'B')
      ..schedule = const PmSchedule(CheckFrequency.monthly, 6)
      ..frequencyWarning = 'Tab name suggests monthly';
    final noPoints = PmCheck(tab: 'C', title: 'C')..problems.add('No check points found below the column headers');
    final wb = PmWorkbook(checks: [unreadable, halfYearly, noPoints], pictures: const {}, skippedTabs: const [], skippedPictures: 0);

    expect(wb.ready, [halfYearly]);
    wb.useSchedule(const PmSchedule(CheckFrequency.weekly));
    expect(wb.ready, [unreadable, halfYearly]);
    expect(wb.checks.map((c) => c.schedule), everyElement(const PmSchedule(CheckFrequency.weekly)));
    expect(halfYearly.allWarnings, isEmpty);
    expect(noPoints.ok, isFalse, reason: 'missing check points still block the tab');
  });
}
