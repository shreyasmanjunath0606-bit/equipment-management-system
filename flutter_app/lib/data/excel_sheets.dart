import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import 'checks.dart';

/// One parsed row of an uploaded check sheet, with validation problems (empty = OK).
class SheetRow {
  SheetRow({required this.rowNumber, required this.code, required this.title, required this.frequency, required this.startDate, this.description, this.problems = const []});

  final int rowNumber; // 1-based, as Excel shows it
  final String code, title;
  final CheckFrequency? frequency;
  final DateTime? startDate;
  final String? description;
  List<String> problems;

  bool get ok => problems.isEmpty;

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'description': description,
        'frequency': frequency!.name,
        'start_date': isoDate(startDate!),
      };
}

class ParsedSheet {
  ParsedSheet(this.rows, {this.sheetName});
  final List<SheetRow> rows;
  final String? sheetName;
  int get valid => rows.where((r) => r.ok).length;
}

const templateHeaders = ['Equipment Code', 'Check Item', 'Frequency', 'Start Date', 'Description'];

final _headerAliases = <String, List<String>>{
  'code': ['equipment code', 'equipment', 'code', 'tag', 'tag code', 'machine code', 'asset code'],
  'title': ['check item', 'check', 'item', 'task', 'activity', 'check point', 'checkpoint'],
  'frequency': ['frequency', 'freq', 'interval', 'schedule'],
  'start': ['start date', 'start', 'date', 'first date', 'from'],
  'description': ['description', 'details', 'notes', 'note', 'instructions', 'method'],
};

String _cellText(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  return switch (v) {
    TextCellValue() => v.value.toString(),
    _ => v.toString(),
  }
      .trim();
}

/// Accepts Excel dates, Excel serial numbers and common text formats (2026-11-01, 01/11/2026, 1-Nov-2026).
DateTime? parseSheetDate(Data? d) {
  final v = d?.value;
  if (v == null) return null;
  if (v is DateCellValue) return DateTime(v.year, v.month, v.day);
  if (v is DateTimeCellValue) return DateTime(v.year, v.month, v.day);
  if (v is IntCellValue || v is DoubleCellValue) {
    final n = num.tryParse(v.toString());
    if (n == null || n < 20000 || n > 80000) return null; // plausible Excel serial range (1954–2119)
    final d0 = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
    return DateTime(d0.year, d0.month, d0.day);
  }
  return parseDateText(_cellText(d));
}

DateTime? parseDateText(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (iso != null) return _ymd(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  final dmy = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(t);
  if (dmy != null) {
    var y = int.parse(dmy[3]!);
    if (y < 100) y += 2000;
    return _ymd(y, int.parse(dmy[2]!), int.parse(dmy[1]!)); // day first (India / UK)
  }
  for (final f in ['d-MMM-yyyy', 'd MMM yyyy', 'd-MMM-yy', 'MMM d, yyyy', 'd MMMM yyyy']) {
    try {
      final d = DateFormat(f).parseStrict(t);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {}
  }
  return null;
}

DateTime? _ymd(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final r = DateTime(y, m, d);
  return r.month == m ? r : null; // rejects 31/02 etc.
}

/// Parse the first sheet that has a recognisable header row.
/// [knownCodes] are the (upper-cased) equipment codes in the chosen plant.
ParsedSheet parseCheckSheet(List<int> bytes, {required Set<String> knownCodes}) {
  final excel = Excel.decodeBytes(bytes);
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    final rows = sheet.rows;
    // Find header row within the first 10 rows.
    for (var h = 0; h < rows.length && h < 10; h++) {
      final headers = rows[h].map((c) => _cellText(c).toLowerCase()).toList();
      int col(String key) => headers.indexWhere((x) => _headerAliases[key]!.contains(x));
      final c = {for (final k in _headerAliases.keys) k: col(k)};
      if (c['code']! < 0 || c['title']! < 0 || c['frequency']! < 0) continue;

      final out = <SheetRow>[];
      final seen = <String>{};
      for (var r = h + 1; r < rows.length; r++) {
        final row = rows[r];
        Data? at(String k) => c[k]! >= 0 && c[k]! < row.length ? row[c[k]!] : null;
        final code = _cellText(at('code'));
        final title = _cellText(at('title'));
        final freqText = _cellText(at('frequency'));
        if (code.isEmpty && title.isEmpty && freqText.isEmpty) continue; // blank line
        final freq = CheckFrequency.tryParse(freqText);
        final start = c['start']! >= 0 ? parseSheetDate(at('start')) : today();
        final desc = _cellText(at('description'));
        final problems = <String>[
          if (code.isEmpty) 'Missing equipment code' else if (!knownCodes.contains(code.toUpperCase())) 'Unknown code in this plant',
          if (title.isEmpty) 'Missing check item',
          if (freq == null) 'Frequency must be Daily, Weekly or Monthly',
          if (start == null) 'Start date not recognised',
        ];
        final key = '${code.toUpperCase()}|${title.toLowerCase()}|${freq?.name}';
        if (problems.isEmpty && !seen.add(key)) problems.add('Duplicate of an earlier row');
        out.add(SheetRow(
          rowNumber: r + 1,
          code: code,
          title: title,
          frequency: freq,
          startDate: start,
          description: desc.isEmpty ? null : desc,
          problems: problems,
        ));
      }
      return ParsedSheet(out, sheetName: name);
    }
  }
  return ParsedSheet(const []);
}

/// Blank template with the expected columns and two example rows.
List<int> buildTemplate({String exampleCode = '101-CNC-0001'}) {
  final x = Excel.createExcel();
  final s = x['Checks'];
  x.setDefaultSheet('Checks');
  if (x.tables.containsKey('Sheet1')) x.delete('Sheet1');
  final bold = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'));
  s.appendRow([for (final h in templateHeaders) TextCellValue(h)]);
  for (var i = 0; i < templateHeaders.length; i++) {
    s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = bold;
    s.setColumnWidth(i, i == 1 || i == 4 ? 38 : 18);
  }
  final t = today();
  s.appendRow([TextCellValue(exampleCode), TextCellValue('Check coolant level'), TextCellValue('Daily'), DateCellValue(year: t.year, month: t.month, day: t.day), TextCellValue('Top up if below the mark')]);
  s.appendRow([TextCellValue(exampleCode), TextCellValue('Clean chip tray'), TextCellValue('Weekly'), DateCellValue(year: t.year, month: t.month, day: t.day), TextCellValue('')]);
  s.appendRow([TextCellValue(exampleCode), TextCellValue('Inspect hydraulic hoses'), TextCellValue('Monthly'), DateCellValue(year: t.year, month: t.month, day: t.day), TextCellValue('Look for leaks at fittings')]);
  return x.encode()!;
}

/// Completed / missed / pending checks exported back to Excel.
List<int> buildCompletionsReport(List<CheckTask> tasks) {
  final x = Excel.createExcel();
  final s = x['Completions'];
  x.setDefaultSheet('Completions');
  if (x.tables.containsKey('Sheet1')) x.delete('Sheet1');
  const headers = ['Due date', 'Equipment code', 'Equipment', 'Check item', 'Frequency', 'Status', 'Completed by', 'Completed at'];
  s.appendRow([for (final h in headers) TextCellValue(h)]);
  final bold = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'));
  for (var i = 0; i < headers.length; i++) {
    s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = bold;
    s.setColumnWidth(i, i == 3 ? 36 : 18);
  }
  for (final t in tasks) {
    s.appendRow([
      DateCellValue(year: t.dueDate.year, month: t.dueDate.month, day: t.dueDate.day),
      TextCellValue(t.equipmentCode),
      TextCellValue(t.equipmentName),
      TextCellValue(t.title),
      TextCellValue(t.frequency.label),
      TextCellValue(switch (t.status) { TaskStatus.done => 'Done', TaskStatus.missed => 'Missed', TaskStatus.pending => 'Pending' }),
      TextCellValue(t.completedByName ?? ''),
      TextCellValue(t.completedAt == null ? '' : formatDateTime(t.completedAt!)),
    ]);
  }
  return x.encode()!;
}
