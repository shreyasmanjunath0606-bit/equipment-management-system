import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:equipment_portal/data/checks.dart';
import 'package:equipment_portal/data/pm_workbook.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixture = File('test/fixtures/alp_c_gun.xlsx').readAsBytesSync();

/// The real workbook with the shared string "MONTHLY" replaced, i.e. the same sheets as daily/weekly ones.
List<int> _withFrequency(String text) {
  final zip = ZipDecoder().decodeBytes(_fixture);
  final out = Archive();
  for (final f in zip.files) {
    if (f.name == 'xl/sharedStrings.xml') {
      final xml = utf8.decode(f.content as List<int>).replaceAll('<t>MONTHLY</t>', '<t>$text</t>');
      final b = utf8.encode(xml);
      out.addFile(ArchiveFile(f.name, b.length, b));
    } else {
      out.addFile(f);
    }
  }
  return ZipEncoder().encode(out)!;
}

void main() {
  group('parsePmFrequency', () {
    test('words, numbers and abbreviations', () {
      expect(parsePmFrequency('DAILY'), const PmSchedule(CheckFrequency.daily));
      expect(parsePmFrequency('Every day'), const PmSchedule(CheckFrequency.daily));
      expect(parsePmFrequency(' weekly '), const PmSchedule(CheckFrequency.weekly));
      expect(parsePmFrequency('2 WEEKLY'), const PmSchedule(CheckFrequency.weekly, 2));
      expect(parsePmFrequency('Fortnightly'), const PmSchedule(CheckFrequency.weekly, 2));
      expect(parsePmFrequency('MONTHLY'), const PmSchedule(CheckFrequency.monthly));
      expect(parsePmFrequency('4 MONTHLY'), const PmSchedule(CheckFrequency.monthly, 4));
      expect(parsePmFrequency('every 4 months'), const PmSchedule(CheckFrequency.monthly, 4));
      expect(parsePmFrequency('4M'), const PmSchedule(CheckFrequency.monthly, 4));
      expect(parsePmFrequency('QUARTERLY'), const PmSchedule(CheckFrequency.monthly, 3));
      expect(parsePmFrequency('HALF YEARLY'), const PmSchedule(CheckFrequency.monthly, 6));
      expect(parsePmFrequency('Half-yearly'), const PmSchedule(CheckFrequency.monthly, 6));
      expect(parsePmFrequency('YEARLY'), const PmSchedule(CheckFrequency.monthly, 12));
      expect(parsePmFrequency('14 days'), const PmSchedule(CheckFrequency.weekly, 2));
    });
    test('ambiguous text is rejected, never guessed', () {
      expect(parsePmFrequency(''), isNull);
      expect(parsePmFrequency('TWICE A WEEK'), isNull);
      expect(parsePmFrequency('Every shift'), isNull);
      expect(parsePmFrequency('Bi-weekly'), isNull);
      expect(parsePmFrequency('3 days'), isNull);
      expect(parsePmFrequency('soon'), isNull);
    });
    test('labels', () {
      expect(frequencyLabel(CheckFrequency.monthly, 4), 'Every 4 months');
      expect(frequencyLabel(CheckFrequency.monthly, 6), 'Half-yearly');
      expect(frequencyLabel(CheckFrequency.weekly, 1), 'Weekly');
    });
    test('tab name hints', () {
      expect(frequencyFromTabName('10.AL-4M'), const PmSchedule(CheckFrequency.monthly, 4));
      expect(frequencyFromTabName('1.KC.Temp-1MOL'), const PmSchedule(CheckFrequency.monthly));
      expect(frequencyFromTabName('17.TIMER PM 6M'), const PmSchedule(CheckFrequency.monthly, 6));
      expect(frequencyFromTabName('Daily-1D'), const PmSchedule(CheckFrequency.daily));
      expect(frequencyFromTabName('Cover'), isNull);
    });
  });

  group('ALP C GUN workbook', () {
    final wb = parsePmWorkbook(_fixture)!;

    test('every tab is a PM check with its frequency read from the sheet', () {
      expect(wb.checks, hasLength(18));
      expect(wb.skippedTabs, isEmpty);
      expect(wb.checks.every((c) => c.ok), isTrue, reason: wb.checks.expand((c) => c.problems).join('; '));
      final freq = wb.checks.map((c) => c.schedule!.label).toList();
      expect(freq.where((f) => f == 'Monthly'), hasLength(9));
      expect(freq.where((f) => f == 'Every 4 months'), hasLength(5));
      expect(freq.where((f) => f == 'Half-yearly'), hasLength(4));
      expect(wb.checks.expand((c) => c.warnings), isEmpty);
    });

    test('all check points are found', () {
      expect(wb.checks.map((c) => c.points.length).toList(), [4, 5, 9, 5, 6, 9, 9, 6, 6, 6, 6, 3, 4, 8, 8, 9, 6, 6]);
    });

    test('header block', () {
      final kc = wb.checks.first;
      expect(kc.title, 'KICKLESS CABLE TEMPERATURE CHECKING & GUN HITTING MONITORING CHECK');
      expect(kc.tab, '1.KC.Temp-1MOL');
      expect(kc.frequencyText, 'MONTHLY');
      expect(kc.pmType, 'ONLINE');
      expect(kc.manPower, '1');
      expect(kc.timeMinutes, '17');
      expect(kc.equipmentRank, 'B');
      expect(kc.equipmentNo, 'C');
      expect(kc.equipmentLabel, contains('ALP GUN'));
      expect(kc.kanbanNo, isNull);
      expect(kc.startDate, DateTime(2026, 11, 1));
      expect(kc.safetyNote, 'REMOVE THE CONCENTRIC PLUG BEFORE WORKING ON GUN');
      expect(kc.tools, contains('Thermal imager'));

      final shi = wb.checks[6];
      expect(shi.manPower, contains('SHI: 2'));
      expect(shi.timeMinutes, contains('SPC: 15'));
      expect(wb.checks[11].tools, '1.Cutter 2.Ladder 3.Flate Screw Driver'); // no "TOOLS:" label on this tab
      expect(wb.checks[3].tools, isNull);
    });

    test('every column of a check point', () {
      final p = wb.checks[9].points.first; // 10.AL-4M, row 6
      expect(p.row, 6);
      expect(p.slNo, '1');
      expect(p.checkPoint, 'Check for any air leak from front side of piston rod');
      expect(p.safetyPoint, startsWith('1) Remove Concentric plug'));
      expect(p.keyPoints, contains('Finger may get crush'));
      expect(p.ifNotDone, contains('Tip Sticking'));
      expect(p.checkingMethod, startsWith('By Hand Feel'));
      expect(p.stdValue, 'There should be no air leak from cylinder front side');
      expect(p.actionIfNg, contains('Replace the seals'));
      expect(p.pmRank, 'A');
      expect(wb.checks[9].points.last.checkPoint, 'Check for any air leak from Exhaust Valve');
    });

    test('pictures: per point, shared ones on the check, EMF skipped', () {
      final gtsb = wb.checks[8]; // 9.GTSB-1M: one picture per row 6..11, row 9 is EMF
      expect([for (final p in gtsb.points) p.pictures.length], [1, 1, 1, 0, 1, 1]);
      expect(gtsb.pictures, isEmpty);
      expect(wb.skippedPictures, 1);

      // Grouped pictures are placed by their position inside the group: one per point.
      final crc = wb.checks[2]; // 3.K.CRC: a group of 8 pictures beside rows 6..13, one on row 14
      expect(crc.pictures, isEmpty);
      expect(crc.points.every((p) => p.pictures.length == 1), isTrue);
      final timer = wb.checks[16]; // 17.TIMER PM: a group of 6 pictures over F6:G11
      expect(timer.points.every((p) => p.pictures.length == 1), isTrue);

      // Picture-filled rectangles count as pictures (12.TILL CABLE TRAY).
      expect(wb.checks[11].points.every((p) => p.pictures.length == 1), isTrue);

      // One picture spanning points 1-4 and again 5-8 (same image): shown once for the whole check.
      expect(wb.checks[13].pictures, hasLength(1));

      for (final pic in wb.pictures.values) {
        expect(pic.contentType, anyOf('image/jpeg', 'image/png'));
      }
      expect(wb.checks.every((c) => c.pictureCount > 0), isTrue);
    });

    test('the same layout as a daily or weekly sheet', () {
      for (final (text, schedule) in [('DAILY', const PmSchedule(CheckFrequency.daily)), ('WEEKLY', const PmSchedule(CheckFrequency.weekly))]) {
        final v = parsePmWorkbook(_withFrequency(text))!;
        expect(v.checks, hasLength(18));
        final changed = v.checks.where((c) => c.frequencyText == text).toList();
        expect(changed, hasLength(9));
        for (final c in changed) {
          expect(c.schedule, schedule);
          // Tab names still say "1M": flagged as a warning, the FREQUENCY cell wins.
          expect(c.warnings.single, contains('using the cell'));
        }
        expect(v.checks.map((c) => c.points.length).toList(), wb.checks.map((c) => c.points.length).toList());
        expect(v.pictures.length, wb.pictures.length);
      }
    });

    test('json for the import RPC', () {
      final j = wb.checks[9].toJson(
        fallbackStart: DateTime(2026, 1, 1),
        picturePaths: {for (final k in wb.pictures.keys) k: 'p/$k'},
        isoDate: (d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
      expect(j['frequency'], 'monthly');
      expect(j['interval_count'], 4);
      expect(j['start_date'], '2026-11-01');
      expect((j['points'] as List), hasLength(6));
    });
  });

  group('suggestEquipment', () {
    const eq = [
      EquipmentCandidate(id: 'a', name: 'ALP Gun A', code: '101-PSW-0001'),
      EquipmentCandidate(id: 'c', name: 'ALP Gun C', code: '101-PSW-0003'),
      EquipmentCandidate(id: 'x', name: 'CNC Lathe', code: '101-CNC-0001'),
    ];
    test('matches by gun number and name words', () {
      expect(suggestEquipment(fileName: 'ALP C GUN.xlsx', equipmentLabel: 'PSW ALP GUN NO', equipmentNo: 'C', equipment: eq), 'c');
    });
    test('no guess when the number is missing from every candidate', () {
      expect(suggestEquipment(fileName: 'ALP D GUN.xlsx', equipmentLabel: 'PSW ALP GUN NO', equipmentNo: 'D', equipment: eq), isNull);
    });
  });
}
