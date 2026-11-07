import 'package:equipment_portal/data/checks.dart';
import 'package:equipment_portal/data/equipment_repo.dart';
import 'package:equipment_portal/data/excel_sheets.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _workbook(List<List<CellValue?>> rows) {
  final x = Excel.createExcel();
  final s = x['Sheet1'];
  for (final r in rows) {
    s.appendRow(r);
  }
  return x.encode()!;
}

void main() {
  group('parseDateText', () {
    test('ISO, day-first and month-name formats', () {
      expect(parseDateText('2026-11-07'), DateTime(2026, 11, 7));
      expect(parseDateText('07/11/2026'), DateTime(2026, 11, 7)); // day first (India / UK)
      expect(parseDateText('7.11.26'), DateTime(2026, 11, 7));
      expect(parseDateText('7-Nov-2026'), DateTime(2026, 11, 7));
      expect(parseDateText('7 November 2026'), DateTime(2026, 11, 7));
    });
    test('rejects nonsense and impossible dates', () {
      expect(parseDateText(''), isNull);
      expect(parseDateText('soon'), isNull);
      expect(parseDateText('31/02/2026'), isNull);
    });
  });

  group('CheckFrequency.tryParse', () {
    test('accepts case and abbreviations', () {
      expect(CheckFrequency.tryParse('Daily'), CheckFrequency.daily);
      expect(CheckFrequency.tryParse(' WEEKLY '), CheckFrequency.weekly);
      expect(CheckFrequency.tryParse('mon'), CheckFrequency.monthly);
      expect(CheckFrequency.tryParse('yearly'), isNull);
      expect(CheckFrequency.tryParse(''), isNull);
    });
  });

  group('parseCheckSheet', () {
    test('reads the template and validates each row', () {
      final bytes = _workbook([
        [TextCellValue('Plant checks — CNC bay')], // title row above the header is skipped
        [TextCellValue('Equipment Code'), TextCellValue('Check Item'), TextCellValue('Frequency'), TextCellValue('Start Date'), TextCellValue('Description')],
        [TextCellValue('101-cnc-0001'), TextCellValue('Check coolant'), TextCellValue('Daily'), DateCellValue(year: 2026, month: 11, day: 1), TextCellValue('Top up')],
        [TextCellValue('101-CNC-0001'), TextCellValue('Clean tray'), TextCellValue('weekly'), TextCellValue('01/11/2026'), null],
        [TextCellValue('101-PRS-0009'), TextCellValue('Hoses'), TextCellValue('Monthly'), TextCellValue('2026-11-07'), null], // unknown code
        [TextCellValue('101-CNC-0001'), TextCellValue(''), TextCellValue('Yearly'), TextCellValue('?'), null], // 3 problems
        [null, null, null, null, null], // blank row ignored
        [TextCellValue('101-CNC-0001'), TextCellValue('Check coolant'), TextCellValue('Daily'), TextCellValue('2026-11-01'), null], // duplicate
      ]);
      final parsed = parseCheckSheet(bytes, knownCodes: {'101-CNC-0001'});

      expect(parsed.rows, hasLength(5));
      expect(parsed.valid, 2);

      final first = parsed.rows[0];
      expect(first.ok, isTrue);
      expect(first.rowNumber, 3);
      expect(first.frequency, CheckFrequency.daily);
      expect(first.startDate, DateTime(2026, 11, 1));
      expect(first.toJson(), {'code': '101-cnc-0001', 'title': 'Check coolant', 'description': 'Top up', 'frequency': 'daily', 'start_date': '2026-11-01'});

      expect(parsed.rows[1].ok, isTrue);
      expect(parsed.rows[1].startDate, DateTime(2026, 11, 1));
      expect(parsed.rows[2].problems, ['Unknown code in this plant']);
      expect(parsed.rows[3].problems, hasLength(3));
      expect(parsed.rows[4].problems, ['Duplicate of an earlier row']);
    });

    test('returns nothing when no header row is found', () {
      final bytes = _workbook([
        [TextCellValue('a'), TextCellValue('b')],
        [TextCellValue('1'), TextCellValue('2')],
      ]);
      expect(parseCheckSheet(bytes, knownCodes: {}).rows, isEmpty);
    });

    test('the downloadable template parses back cleanly', () {
      final parsed = parseCheckSheet(buildTemplate(exampleCode: 'X-1'), knownCodes: {'X-1'});
      expect(parsed.rows, hasLength(3));
      expect(parsed.valid, 3);
      expect(parsed.rows.map((r) => r.frequency), [CheckFrequency.daily, CheckFrequency.weekly, CheckFrequency.monthly]);
    });
  });

  group('parseScannedValue', () {
    test('understands new code links, old portal links and bare codes', () {
      expect(parseScannedValue('https://plant.example.com/e/101-CNC-0001'), (id: null, code: '101-CNC-0001'));
      expect(parseScannedValue('https://plant.example.com/equipment/abc-123/update'), (id: 'abc-123', code: null));
      expect(parseScannedValue('  101-PRS-0002 '), (id: null, code: '101-PRS-0002'));
    });
  });
}
