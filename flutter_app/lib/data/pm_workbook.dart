import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'checks.dart';
import 'excel_sheets.dart' show parseDateText;

/// Reads plant PM check-sheet workbooks (the "ALP C GUN" layout): one tab per PM check, a header block
/// with FREQUENCY / PM TYPE / MAN POWER / TIME, a column-header row (SAFETY POINT, CHECKING METHOD,
/// STD VALUE, ...) and one row per check point, with pictures in the CHECK POINT column.
///
/// The .xlsx is read directly (zip + XML) because the `excel` package exposes neither drawings nor
/// pictures. Everything is located by its label text, not by fixed cell addresses, so daily, weekly
/// and monthly sheets that share the layout but shift a column or row still parse.

// ------------------------------------------------------------------ schedule

/// How often a check repeats: [unit] × [interval] (e.g. monthly × 4 = every 4 months).
class PmSchedule {
  const PmSchedule(this.unit, [this.interval = 1]);
  final CheckFrequency unit;
  final int interval;

  String get label => frequencyLabel(unit, interval);

  @override
  bool operator ==(Object other) => other is PmSchedule && other.unit == unit && other.interval == interval;
  @override
  int get hashCode => Object.hash(unit, interval);
  @override
  String toString() => label;
}

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9&]+'), ' ').trim();

/// Frequency cell text -> schedule. Returns null for anything ambiguous (e.g. "twice a week") so the
/// sheet is flagged instead of guessed.
PmSchedule? parsePmFrequency(String? raw) {
  final s = _norm(raw ?? '');
  if (s.isEmpty) return null;
  if (RegExp(r'\b(TWICE|THRICE|TIMES|SHIFT|BI WEEKLY|BIWEEKLY|ALTERNATE)\b').hasMatch(s)) return null;

  const daily = PmSchedule(CheckFrequency.daily);
  final exact = <String, PmSchedule>{
    'DAILY': daily, 'DAY': daily, 'EVERY DAY': daily, 'EVERYDAY': daily, 'D': daily, '1D': daily, '1 D': daily, '1 DAY': daily,
    'WEEKLY': const PmSchedule(CheckFrequency.weekly), 'WEEK': const PmSchedule(CheckFrequency.weekly),
    'EVERY WEEK': const PmSchedule(CheckFrequency.weekly), 'W': const PmSchedule(CheckFrequency.weekly),
    'FORTNIGHTLY': const PmSchedule(CheckFrequency.weekly, 2),
    'MONTHLY': const PmSchedule(CheckFrequency.monthly), 'MONTH': const PmSchedule(CheckFrequency.monthly),
    'EVERY MONTH': const PmSchedule(CheckFrequency.monthly), 'M': const PmSchedule(CheckFrequency.monthly),
    'QUARTERLY': const PmSchedule(CheckFrequency.monthly, 3),
    'HALF YEARLY': const PmSchedule(CheckFrequency.monthly, 6), 'HALFYEARLY': const PmSchedule(CheckFrequency.monthly, 6),
    'HALF YEAR': const PmSchedule(CheckFrequency.monthly, 6), 'SIX MONTHLY': const PmSchedule(CheckFrequency.monthly, 6),
    'SEMI ANNUAL': const PmSchedule(CheckFrequency.monthly, 6), 'SEMI ANNUALLY': const PmSchedule(CheckFrequency.monthly, 6),
    'BI ANNUAL': const PmSchedule(CheckFrequency.monthly, 6),
    'YEARLY': const PmSchedule(CheckFrequency.monthly, 12), 'ANNUAL': const PmSchedule(CheckFrequency.monthly, 12),
    'ANNUALLY': const PmSchedule(CheckFrequency.monthly, 12), 'EVERY YEAR': const PmSchedule(CheckFrequency.monthly, 12),
    'Y': const PmSchedule(CheckFrequency.monthly, 12),
  };
  if (exact[s] != null) return exact[s];

  // "4 MONTHLY", "EVERY 4 MONTHS", "4M", "4 MONTHS", "2 WEEKLY", "2W", "2 YEARLY", "3 DAYS"
  final m = RegExp(r'^(?:EVERY |ONCE IN )?(\d{1,2}) ?(D|DAY|DAYS|DAILY|W|WK|WEEK|WEEKS|WEEKLY|M|MON|MONTH|MONTHS|MONTHLY|Y|YR|YEAR|YEARS|YEARLY)$')
      .firstMatch(s);
  if (m == null) return null;
  final n = int.parse(m[1]!);
  if (n < 1) return null;
  final u = m[2]!;
  if (u.startsWith('D')) return n == 1 ? daily : (n % 7 == 0 ? PmSchedule(CheckFrequency.weekly, n ~/ 7) : null);
  if (u.startsWith('W')) return n > 52 ? null : PmSchedule(CheckFrequency.weekly, n);
  if (u.startsWith('M')) return n > 60 ? null : PmSchedule(CheckFrequency.monthly, n);
  return n > 5 ? null : PmSchedule(CheckFrequency.monthly, 12 * n);
}

/// Frequency hint at the end of a tab name: "10.AL-4M" -> every 4 months, "1.KC.Temp-1MOL" -> monthly.
PmSchedule? frequencyFromTabName(String tab) {
  final m = RegExp(r'(\d{1,2}) ?([DWMY])[A-Z]{0,4}$').firstMatch(tab.toUpperCase().trim());
  return m == null ? null : parsePmFrequency('${m[1]}${m[2]}');
}

// ------------------------------------------------------------------ output model

class PmPicture {
  PmPicture({required this.key, required this.bytes, required this.contentType});

  /// Path of the media file inside the workbook (same picture used twice = same key).
  final String key;
  final Uint8List bytes;
  final String contentType;

  String get extension => contentType == 'image/png' ? 'png' : (contentType == 'image/gif' ? 'gif' : (contentType == 'image/webp' ? 'webp' : 'jpg'));
}

class PmPoint {
  PmPoint({
    required this.row,
    required this.checkPoint,
    this.slNo,
    this.safetyPoint,
    this.keyPoints,
    this.ifNotDone,
    this.checkingMethod,
    this.stdValue,
    this.actionIfNg,
    this.pmRank,
  });

  final int row; // 1-based, as Excel shows it
  final String checkPoint;
  final String? slNo, safetyPoint, keyPoints, ifNotDone, checkingMethod, stdValue, actionIfNg, pmRank;

  /// Keys of [PmWorkbook.pictures] that belong to this point only.
  final List<String> pictures = [];

  Map<String, dynamic> toJson({required Map<String, String> picturePaths}) => {
        'sl_no': slNo,
        'check_point': checkPoint,
        'safety_point': safetyPoint,
        'key_points': keyPoints,
        'if_not_done': ifNotDone,
        'checking_method': checkingMethod,
        'std_value': stdValue,
        'action_if_ng': actionIfNg,
        'pm_rank': pmRank,
        'image_paths': [for (final k in pictures) ?picturePaths[k]],
      };
}

/// One tab = one PM check.
class PmCheck {
  PmCheck({required this.tab, required this.title});

  final String tab;
  String title;
  String? frequencyText, pmType, equipmentRank, manPower, timeMinutes, kanbanNo, equipmentLabel, equipmentNo, safetyNote, tools;
  PmSchedule? schedule;
  DateTime? startDate;
  final List<PmPoint> points = [];

  /// Pictures spanning several points (or none): shown once at the top of the check.
  final List<String> pictures = [];
  final List<String> problems = [];
  final List<String> warnings = [];

  bool get ok => problems.isEmpty;
  int get pictureCount => pictures.length + points.fold(0, (n, p) => n + p.pictures.length);

  Map<String, dynamic> toJson({required DateTime fallbackStart, required Map<String, String> picturePaths, required String Function(DateTime) isoDate}) => {
        'title': title,
        'source_tab': tab,
        'frequency': schedule!.unit.name,
        'interval_count': schedule!.interval,
        'frequency_text': frequencyText,
        'start_date': isoDate(startDate ?? fallbackStart),
        'pm_type': pmType,
        'pm_rank': equipmentRank,
        'man_power': manPower,
        'time_minutes': timeMinutes,
        'kanban_no': kanbanNo,
        'safety_note': safetyNote,
        'tools': tools,
        'image_paths': [for (final k in pictures) ?picturePaths[k]],
        'points': [for (final p in points) p.toJson(picturePaths: picturePaths)],
      };
}

class PmWorkbook {
  PmWorkbook({required this.checks, required this.pictures, required this.skippedTabs, required this.skippedPictures});

  final List<PmCheck> checks;

  /// Every usable picture, by [PmPicture.key].
  final Map<String, PmPicture> pictures;

  /// Tabs that do not have the PM layout (cover sheets, notes, ...).
  final List<String> skippedTabs;

  /// Pictures in formats the app cannot show (EMF/WMF/...).
  final int skippedPictures;

  List<PmCheck> get ready => checks.where((c) => c.ok).toList();

  /// "PSW ALP GUN NO: C" -> label + value, from the first tab that has them.
  String? get equipmentLabel => checks.map((c) => c.equipmentLabel).nonNulls.firstOrNull;
  String? get equipmentNo => checks.map((c) => c.equipmentNo).nonNulls.firstOrNull;
}

// ------------------------------------------------------------------ xlsx reading

class _Cell {
  _Cell(this.text, {this.number});
  final String text;
  final num? number;
}

class _Merge {
  const _Merge(this.r1, this.c1, this.r2, this.c2);
  final int r1, c1, r2, c2;
  bool contains(int r, int c) => r >= r1 && r <= r2 && c >= c1 && c <= c2;
}

class _Sheet {
  final cells = <int, Map<int, _Cell>>{}; // row -> col -> cell (1-based)
  final merges = <_Merge>[];
  final rowHeights = <int, double>{}; // points
  double defaultRowHeight = 15;
  int maxRow = 0;

  double heightOf(int r) => rowHeights[r] ?? defaultRowHeight;

  /// Distance in points from the top of the sheet to the top of row [r] (1-based).
  double topOf(int r) {
    var y = 0.0;
    for (var i = 1; i < r; i++) {
      y += heightOf(i);
    }
    return y;
  }

  /// Row containing the vertical position [y] (points from the top).
  int rowAt(double y) {
    var top = 0.0;
    for (var r = 1; r < 5000; r++) {
      top += heightOf(r);
      if (y < top) return r;
    }
    return 5000;
  }

  _Merge? mergeAt(int r, int c) {
    for (final m in merges) {
      if (m.contains(r, c)) return m;
    }
    return null;
  }

  /// Raw cell (no merge resolution).
  _Cell? raw(int r, int c) => cells[r]?[c];

  /// Cell value, where a cell inside a merged range takes the range's top-left value.
  _Cell? at(int r, int c) {
    final m = mergeAt(r, c);
    return m == null ? raw(r, c) : raw(m.r1, m.c1);
  }

  String text(int r, int c) => at(r, c)?.text ?? '';
}

({int row, int col}) _ref(String a1) {
  final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(a1.replaceAll(r'$', ''))!;
  var col = 0;
  for (final ch in m[1]!.codeUnits) {
    col = col * 26 + (ch - 64);
  }
  return (row: int.parse(m[2]!), col: col);
}

String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = [...baseDir.split('/').where((p) => p.isNotEmpty)];
  for (final p in target.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      parts.add(p);
    }
  }
  return parts.join('/');
}

String _dir(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
String _relsOf(String path) => '${_dir(path)}/_rels/${path.split('/').last}.rels';

Iterable<XmlElement> _all(XmlNode n, String local) => n.findAllElements(local, namespace: '*');
Iterable<XmlElement> _kids(XmlNode n, String local) => n.findElements(local, namespace: '*');
String? _attr(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// Text of a shared-string item: plain `t` or rich-text runs `r/t`; phonetic guides (`rPh`) are skipped.
String _siText(XmlElement si) {
  final b = StringBuffer();
  for (final child in si.childElements) {
    if (child.name.local == 't') b.write(child.innerText);
    if (child.name.local == 'r') {
      for (final t in _kids(child, 't')) {
        b.write(t.innerText);
      }
    }
  }
  return b.toString();
}

class _Zip {
  _Zip(List<int> bytes) : _archive = ZipDecoder().decodeBytes(bytes);
  final Archive _archive;

  Uint8List? bytes(String path) {
    final f = _archive.findFile(path);
    if (f == null) return null;
    final c = f.content;
    return c is Uint8List ? c : Uint8List.fromList(c as List<int>);
  }

  XmlDocument? xml(String path) {
    final b = bytes(path);
    return b == null ? null : XmlDocument.parse(utf8.decode(b, allowMalformed: true));
  }

  Map<String, String> rels(String path) {
    final doc = xml(_relsOf(path));
    if (doc == null) return const {};
    return {
      for (final r in _all(doc, 'Relationship'))
        if (_attr(r, 'TargetMode') != 'External') _attr(r, 'Id')!: _resolve(_dir(path), _attr(r, 'Target')!),
    };
  }
}

_Sheet _readSheet(XmlDocument doc, List<String> shared) {
  final s = _Sheet();
  for (final c in _all(doc, 'c')) {
    final ref = _attr(c, 'r');
    if (ref == null) continue;
    final t = _attr(c, 't');
    final v = _kids(c, 'v').firstOrNull?.innerText;
    String? text;
    num? number;
    switch (t) {
      case 's':
        final i = int.tryParse(v ?? '');
        if (i != null && i < shared.length) text = shared[i];
      case 'inlineStr':
        final is_ = _kids(c, 'is').firstOrNull;
        if (is_ != null) text = _siText(is_);
      case 'b':
        text = v == '1' ? 'TRUE' : (v == null ? null : 'FALSE');
      case 'e':
        text = null; // #REF! etc.
      case 'str':
        text = v;
      default:
        if (v != null) {
          number = num.tryParse(v);
          text = number == null ? v : (number == number.roundToDouble() && !v.contains('E') ? number.toInt().toString() : v);
        }
    }
    final value = text?.trim() ?? '';
    if (value.isEmpty) continue;
    final p = _ref(ref);
    (s.cells[p.row] ??= {})[p.col] = _Cell(value, number: number);
    if (p.row > s.maxRow) s.maxRow = p.row;
  }
  final fmt = _all(doc, 'sheetFormatPr').firstOrNull;
  s.defaultRowHeight = double.tryParse(fmt == null ? '' : _attr(fmt, 'defaultRowHeight') ?? '') ?? 15;
  for (final row in _all(doc, 'row')) {
    final r = int.tryParse(_attr(row, 'r') ?? '');
    final ht = double.tryParse(_attr(row, 'ht') ?? '');
    if (r != null && ht != null) s.rowHeights[r] = _attr(row, 'hidden') == '1' ? 0 : ht;
  }
  for (final m in _all(doc, 'mergeCell')) {
    final parts = (_attr(m, 'ref') ?? '').split(':');
    if (parts.length != 2) continue;
    final a = _ref(parts[0]), b = _ref(parts[1]);
    s.merges.add(_Merge(a.row, a.col, b.row, b.col));
  }
  return s;
}

class _Anchor {
  _Anchor(this.media, this.fromRow, this.toRow);
  final String media;
  final int fromRow, toRow; // 1-based, inclusive
}

const _emuPerPoint = 12700;

/// Picture anchors of a sheet (shapes such as the legend circles/triangles are ignored).
/// Pictures inside a group are placed by their own position within the group, so a group of
/// pictures laid out beside several check points gives one picture per point.
List<_Anchor> _readPictures(_Zip zip, String sheetPath, _Sheet sheet) {
  final out = <_Anchor>[];
  final sheetRels = zip.rels(sheetPath);
  final sheetDoc = zip.xml(sheetPath);
  if (sheetDoc == null) return out;
  for (final d in _all(sheetDoc, 'drawing')) {
    final drawingPath = sheetRels[_attr(d, 'id')];
    if (drawingPath == null) continue;
    final doc = zip.xml(drawingPath);
    if (doc == null) continue;
    final drels = zip.rels(drawingPath);
    for (final anchor in doc.rootElement.childElements) {
      final from = _kids(anchor, 'from').firstOrNull;
      if (from == null) continue;
      int num(XmlElement e, String k) => int.tryParse(_kids(e, k).firstOrNull?.innerText ?? '') ?? 0;
      final fromRow = num(from, 'row') + 1;
      final to = _kids(anchor, 'to').firstOrNull;
      var toRow = to == null ? fromRow : num(to, 'row') + 1;
      // A picture whose bottom edge sits exactly on a row boundary does not reach into that row.
      if (to != null && toRow > fromRow && num(to, 'rowOff') == 0) toRow--;
      final top = sheet.topOf(fromRow) + num(from, 'rowOff') / _emuPerPoint;
      final bottom = to == null ? top + sheet.heightOf(fromRow) : sheet.topOf(num(to, 'row') + 1) + num(to, 'rowOff') / _emuPerPoint;
      // Real pictures (<pic>) and shapes filled with a picture (<sp> + blipFill); plain shapes have no blip.
      final carriers = anchor.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pic' || e.name.local == 'sp');
      for (final pic in carriers) {
        final blip = _all(pic, 'blip').firstOrNull;
        final media = blip == null ? null : drels[_attr(blip, 'embed')];
        if (media == null) continue;
        final row = _rowInGroup(pic, top, bottom, sheet);
        out.add(row == null ? _Anchor(media, fromRow, toRow) : _Anchor(media, row, row));
      }
    }
  }
  return out;
}

({double y, double h})? _xfrmY(XmlElement? xfrm, String off, String ext) {
  if (xfrm == null) return null;
  final o = _kids(xfrm, off).firstOrNull, e = _kids(xfrm, ext).firstOrNull;
  final y = double.tryParse(o == null ? '' : _attr(o, 'y') ?? ''), h = double.tryParse(e == null ? '' : _attr(e, 'cy') ?? '');
  return y == null || h == null ? null : (y: y, h: h);
}

/// For a picture inside a group: the sheet row at the picture's vertical centre. Null otherwise.
int? _rowInGroup(XmlElement pic, double top, double bottom, _Sheet sheet) {
  final grp = pic.ancestors.whereType<XmlElement>().where((e) => e.name.local == 'grpSp').lastOrNull; // outermost group
  if (grp == null) return null;
  final gx = _all(grp, 'grpSpPr').firstOrNull;
  final g = _kids(gx ?? grp, 'xfrm').firstOrNull;
  final child = _xfrmY(g, 'chOff', 'chExt');
  final px = _all(pic, 'spPr').firstOrNull;
  final self = _xfrmY(px == null ? null : _kids(px, 'xfrm').firstOrNull, 'off', 'ext');
  if (child == null || self == null || child.h <= 0) return null;
  final frac = ((self.y + self.h / 2) - child.y) / child.h;
  if (frac < 0 || frac > 1) return null;
  return sheet.rowAt(top + frac * (bottom - top));
}

String? _sniff(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
  if (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
  return null; // EMF, WMF, TIFF, ... cannot be shown in the app
}

// ------------------------------------------------------------------ layout detection

enum _Col { slNo, checkPoint, safety, keyPoints, ifNotDone, method, picture, std, action, rank }

_Col? _columnFor(String label) {
  final s = _norm(label);
  if (s.isEmpty) return null;
  if (s == 'SL NO' || s == 'SL' || s == 'SR NO' || s == 'S NO' || s == 'NO') return _Col.slNo;
  if (s.contains('PM CHECK POINT') || s == 'CHECK POINTS' || s == 'CHECK ITEM' || s == 'CHECK ITEMS') return _Col.checkPoint;
  if (s.contains('SAFETY')) return _Col.safety;
  if (s.contains('KEY POINT') || s.contains('KY POINT')) return _Col.keyPoints;
  if (s.contains('NOT DONE')) return _Col.ifNotDone;
  if (s.contains('METHOD')) return _Col.method;
  if (s == 'CHECK POINT' || s.contains('PICTURE') || s.contains('PHOTO') || s.contains('IMAGE')) return _Col.picture;
  if (s.contains('STD') || s.contains('STANDARD')) return _Col.std;
  if (s.contains('ACTION')) return _Col.action;
  if (s == 'PM RANK' || s == 'RANK') return _Col.rank;
  return null;
}

bool _isFooter(String s) {
  final n = _norm(s);
  return n.startsWith('TOOL') || n.contains('SIGN & DATE') || n.contains('SIGN DATE') || n.contains('SIGNATURE');
}

bool _isSignature(String s) {
  final n = _norm(s);
  return n.contains('SIGN & DATE') || n.contains('SIGN DATE') || n.contains('SIGNATURE');
}

const _legend = {'OK', 'X', 'ABNORMAL PENDING', 'IMMEDIATE CORRECTION', 'PENDING COMPLETED', 'NG', 'O'};

/// Parse one tab; null when it does not have the PM layout.
PmCheck? _parseTab(String tab, _Sheet s, List<_Anchor> anchors, Map<String, PmPicture> pictures) {
  // Column-header row: has CHECKING METHOD (or similar) and STD VALUE.
  int? headerRow;
  for (var r = 1; r <= s.maxRow && r <= 15; r++) {
    final labels = {for (final c in (s.cells[r] ?? const {}).keys) _columnFor(s.text(r, c))};
    if (labels.contains(_Col.method) && labels.contains(_Col.std)) {
      headerRow = r;
      break;
    }
  }
  if (headerRow == null) return null;

  // Map columns. Labels may sit in a merged cell above the header row (e.g. "PM CHECK POINTS" in B4:B5).
  final cols = <_Col, int>{};
  final allCols = <int>{for (var r = 1; r <= headerRow; r++) ...?s.cells[r]?.keys};
  final maxCol = allCols.isEmpty ? 0 : allCols.reduce((a, b) => a > b ? a : b);
  for (var c = 1; c <= maxCol; c++) {
    final kind = _columnFor(s.text(headerRow, c));
    if (kind != null) cols.putIfAbsent(kind, () => c);
  }
  if (!cols.containsKey(_Col.checkPoint)) {
    // Look one or two rows up for the check-point label (merged header block).
    for (var r = headerRow - 1; r >= 1 && r >= headerRow - 2 && !cols.containsKey(_Col.checkPoint); r--) {
      for (var c = 1; c <= maxCol; c++) {
        if (_columnFor(s.text(r, c)) == _Col.checkPoint) {
          cols[_Col.checkPoint] = c;
          break;
        }
      }
    }
  }
  if (!cols.containsKey(_Col.checkPoint) && cols.containsKey(_Col.slNo)) cols[_Col.checkPoint] = cols[_Col.slNo]! + 1;
  final cpCol = cols[_Col.checkPoint];
  if (cpCol == null) return null;

  // Title: the banner across the top (a cell merged over many columns, e.g. A1:V1); otherwise the
  // first text above the header block that is not a label.
  String title = '';
  for (var r = 1; r < headerRow && title.isEmpty; r++) {
    for (final c in ((s.cells[r]?.keys.toList() ?? <int>[])..sort())) {
      final m = s.mergeAt(r, c);
      final t = s.raw(r, c)!.text;
      if (m != null && m.r1 == r && m.c1 == c && m.c2 - m.c1 >= 4 && !_legend.contains(_norm(t)) && _norm(t) != 'X') {
        title = t.replaceAll(RegExp(r'\s+'), ' ').trim();
        break;
      }
    }
  }
  for (var r = 1; r < headerRow && title.isEmpty; r++) {
    final row = s.cells[r];
    if (row == null) continue;
    final keys = row.keys.toList()..sort();
    for (final c in keys) {
      final t = row[c]!.text;
      if (_labelKind(t) == null && !_legend.contains(_norm(t))) {
        title = t.replaceAll(RegExp(r'\s+'), ' ').trim();
        break;
      }
    }
  }
  final check = PmCheck(tab: tab.trim(), title: title.isEmpty ? tab.trim() : title);

  // Header block (rows above the column headers): labelled values.
  final consumed = <String>{}; // "r:c" of cells already used
  String key(int r, int c) => '$r:$c';
  String? below(int r, int c) {
    final m = s.mergeAt(r, c);
    final rr = (m?.r2 ?? r) + 1;
    if (rr >= headerRow!) return null;
    final v = s.at(rr, c);
    if (v == null || _labelKind(v.text) != null) return null;
    final m2 = s.mergeAt(rr, c);
    consumed.add(key(m2?.r1 ?? rr, m2?.c1 ?? c));
    return v.text;
  }

  String? right(int r, int c) {
    final m = s.mergeAt(r, c);
    final cc = (m?.c2 ?? c) + 1;
    final v = s.at(r, cc);
    if (v == null || _labelKind(v.text) != null || _legend.contains(_norm(v.text))) return null;
    final m2 = s.mergeAt(r, cc);
    consumed.add(key(m2?.r1 ?? r, m2?.c1 ?? cc));
    return v.text;
  }

  for (var r = 1; r < headerRow; r++) {
    final row = s.cells[r];
    if (row == null) continue;
    for (final c in row.keys) {
      final t = row[c]!.text;
      switch (_labelKind(t)) {
        case _Label.frequency:
          consumed.add(key(r, c));
          check.frequencyText ??= below(r, c);
        case _Label.pmType:
          consumed.add(key(r, c));
          check.pmType ??= below(r, c);
        case _Label.manPower:
          consumed.add(key(r, c));
          check.manPower ??= below(r, c);
        case _Label.time:
          consumed.add(key(r, c));
          check.timeMinutes ??= below(r, c);
        case _Label.rank:
          consumed.add(key(r, c));
          check.equipmentRank ??= right(r, c);
        case _Label.kanban:
          consumed.add(key(r, c));
          check.kanbanNo ??= right(r, c);
        case _Label.equipment:
          consumed.add(key(r, c));
          check.equipmentLabel ??= t
              .replaceFirst(RegExp(r'^\s*(EQUIPMENTS?|EQUIP|EQIP|EQPT|EQP)\b[\s.:]*', caseSensitive: false), '')
              .replaceAll(RegExp(r'[:\s]+$'), '')
              .trim();
          check.equipmentNo ??= right(r, c);
        case _Label.column:
          consumed.add(key(r, c));
        case null:
          break;
      }
    }
  }

  // Other header-block text: plan date, sheet-wide safety warning.
  final notes = <String>[];
  for (var r = 2; r < headerRow; r++) {
    final row = s.cells[r];
    if (row == null) continue;
    for (final c in (row.keys.toList()..sort())) {
      final cell = row[c]!;
      if (consumed.contains(key(r, c)) || _labelKind(cell.text) != null || _legend.contains(_norm(cell.text))) continue;
      final n = cell.number;
      if (n != null && n >= 30000 && n <= 80000) {
        check.startDate ??= DateTime(1899, 12, 30).add(Duration(days: n.floor()));
        continue;
      }
      final asDate = parseDateText(cell.text);
      if (asDate != null) {
        check.startDate ??= asDate;
        continue;
      }
      if (n == null && cell.text.length > 3) notes.add(cell.text.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
  }
  if (notes.isNotEmpty) check.safetyNote = notes.join('\n');

  // Check points, until the footer (TOOLS / sign & date).
  String? val(int r, _Col k) {
    final c = cols[k];
    if (c == null) return null;
    final t = s.text(r, c).trim();
    return t.isEmpty || t == r'\' ? null : t;
  }

  var footerRow = s.maxRow + 1;
  for (var r = headerRow + 1; r <= s.maxRow; r++) {
    final row = s.cells[r];
    if (row != null && row.values.any((cell) => _isFooter(cell.text))) {
      footerRow = r;
      break;
    }
    // Check-point text must start in this row (a point merged over several rows counts once).
    final m = s.mergeAt(r, cpCol);
    if (m != null && m.r1 != r) continue;
    final text = s.raw(r, cpCol)?.text.trim() ?? '';
    if (text.isEmpty) continue; // blank or SL-number-only row
    check.points.add(PmPoint(
      row: r,
      checkPoint: text,
      slNo: val(r, _Col.slNo),
      safetyPoint: val(r, _Col.safety),
      keyPoints: val(r, _Col.keyPoints),
      ifNotDone: val(r, _Col.ifNotDone),
      checkingMethod: val(r, _Col.method),
      stdValue: val(r, _Col.std),
      actionIfNg: val(r, _Col.action),
      pmRank: val(r, _Col.rank),
    ));
  }

  // Footer: tools list (with or without a "TOOLS:" label); signature boxes ignored.
  final tools = <String>[];
  final seen = <String>{};
  for (var r = footerRow; r <= s.maxRow; r++) {
    final row = s.cells[r];
    if (row == null) continue;
    for (final c in (row.keys.toList()..sort())) {
      final m = s.mergeAt(r, c);
      final k = key(m?.r1 ?? r, m?.c1 ?? c);
      final t = row[c]!.text;
      if (!seen.add(k) || _isSignature(t)) continue;
      final cleaned = t.replaceFirst(RegExp(r'^\s*tools?\s*[:\-–]*\s*', caseSensitive: false), '').trim();
      if (cleaned.isNotEmpty) tools.add(cleaned);
    }
  }
  if (tools.isNotEmpty) check.tools = tools.join('\n');

  // Pictures: one point -> that point; several points (or none) -> the whole check.
  for (final a in anchors) {
    final pic = pictures[a.media];
    if (pic == null) continue;
    if (a.toRow < headerRow + 1 || a.fromRow >= footerRow) continue; // logos / header art
    final hit = check.points.where((p) => p.row >= a.fromRow && p.row <= a.toRow).toList();
    if (hit.length == 1) {
      if (!hit.first.pictures.contains(a.media)) hit.first.pictures.add(a.media);
    } else if (!check.pictures.contains(a.media) && !check.points.any((p) => p.pictures.contains(a.media))) {
      check.pictures.add(a.media);
    }
  }

  // Frequency: the sheet's own cell decides; the tab name is only a fallback / sanity check.
  final fromCell = parsePmFrequency(check.frequencyText);
  final fromTab = frequencyFromTabName(tab);
  if (fromCell != null) {
    check.schedule = fromCell;
    if (fromTab != null && fromTab != fromCell) {
      check.warnings.add('Tab name suggests ${fromTab.label.toLowerCase()} but the FREQUENCY cell says "${check.frequencyText}" — using the cell');
    }
  } else if (fromTab != null && (check.frequencyText ?? '').isEmpty) {
    check.schedule = fromTab;
    check.warnings.add('FREQUENCY cell is empty — using ${fromTab.label.toLowerCase()} from the tab name');
  } else {
    check.problems.add((check.frequencyText ?? '').isEmpty
        ? 'No FREQUENCY found on this sheet'
        : 'Frequency "${check.frequencyText}" not recognised (use Daily, Weekly, Monthly, 4 Monthly, Half Yearly, Yearly)');
  }
  if (check.points.isEmpty) check.problems.add('No check points found below the column headers');
  return check;
}

enum _Label { frequency, pmType, manPower, time, rank, kanban, equipment, column }

final _equipmentWord = RegExp(r'^(EQUIPMENT|EQUIPMENTS|EQUIP|EQIP|EQPT|EQP)\b');

_Label? _labelKind(String text) {
  final s = _norm(text);
  if (s.isEmpty) return null;
  if (s == 'FREQUENCY' || s == 'FREQ' || s == 'CHECK FREQUENCY' || s == 'PM FREQUENCY') return _Label.frequency;
  if (s == 'PM TYPE' || s == 'TYPE') return _Label.pmType;
  if (s.startsWith('MAN POWER') || s.startsWith('MANPOWER')) return _Label.manPower;
  if (RegExp(r'^TIME\b').hasMatch(s)) return _Label.time; // "TIME MINTS", not a title like "TIMER PM"
  if (s.contains('PM RANK') && _equipmentWord.hasMatch(s)) return _Label.rank;
  if (s.startsWith('KANBAN')) return _Label.kanban;
  // "EQUIPMENT PSW ALP GUN NO:", "EQIP PSW GUN:ALP", "EQUIP NO", ...
  if (_equipmentWord.hasMatch(s) && !s.contains('RANK')) return _Label.equipment;
  if (_columnFor(text) != null) return _Label.column;
  return null;
}

/// Parse a PM workbook. Returns null when no tab has the PM layout (so callers can fall back to the
/// flat template parser).
PmWorkbook? parsePmWorkbook(List<int> bytes) {
  final zip = _Zip(bytes);
  final wb = zip.xml('xl/workbook.xml');
  if (wb == null) return null;
  final wbRels = zip.rels('xl/workbook.xml');

  final shared = <String>[];
  final sst = zip.xml('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in _kids(sst.rootElement, 'si')) {
      shared.add(_siText(si));
    }
  }

  final pictures = <String, PmPicture>{};
  final unsupported = <String>{};
  final checks = <PmCheck>[];
  final skipped = <String>[];
  for (final sh in _all(wb, 'sheet')) {
    final name = _attr(sh, 'name') ?? '';
    if (_attr(sh, 'state') == 'hidden' || _attr(sh, 'state') == 'veryHidden') {
      skipped.add(name);
      continue;
    }
    final path = wbRels[_attr(sh, 'id')];
    final doc = path == null ? null : zip.xml(path);
    if (doc == null) {
      skipped.add(name);
      continue;
    }
    final sheet = _readSheet(doc, shared);
    final anchors = _readPictures(zip, path!, sheet);
    for (final a in anchors) {
      if (pictures.containsKey(a.media) || unsupported.contains(a.media)) continue;
      final b = zip.bytes(a.media);
      final type = b == null ? null : _sniff(b);
      if (type == null) {
        unsupported.add(a.media);
      } else {
        pictures[a.media] = PmPicture(key: a.media, bytes: b!, contentType: type);
      }
    }
    final check = _parseTab(name, sheet, anchors, pictures);
    if (check == null) {
      skipped.add(name);
    } else {
      checks.add(check);
    }
  }
  if (checks.isEmpty) return null;

  // Keep only pictures that ended up attached somewhere.
  final used = {for (final c in checks) ...c.pictures, for (final c in checks) for (final p in c.points) ...p.pictures};
  pictures.removeWhere((k, _) => !used.contains(k));
  return PmWorkbook(checks: checks, pictures: pictures, skippedTabs: skipped, skippedPictures: unsupported.length);
}

// ------------------------------------------------------------------ equipment matching

class EquipmentCandidate {
  const EquipmentCandidate({required this.id, required this.name, required this.code});
  final String id, name, code;
}

/// Suggest which equipment a workbook belongs to, from the file name ("ALP C GUN.xlsx") and the
/// equipment label/number on the sheets ("PSW ALP GUN NO:" "C"). Null when nothing matches clearly.
String? suggestEquipment({required String fileName, String? equipmentLabel, String? equipmentNo, required List<EquipmentCandidate> equipment}) {
  const stop = {'EQUIPMENT', 'NO', 'XLSX', 'THE', 'OF', 'AND', 'CHECK', 'SHEET', 'SHEETS', 'PM'};
  List<String> words(String s) => _norm(s).split(' ').where((w) => w.isNotEmpty && !stop.contains(w)).toList();
  final number = equipmentNo == null ? null : _norm(equipmentNo);
  final tokens = {...words(fileName.replaceAll(RegExp(r'\.xlsx?$', caseSensitive: false), '')), ...words(equipmentLabel ?? '')};
  if (number != null && number.isNotEmpty) tokens.add(number);
  if (tokens.isEmpty) return null;

  String? best;
  var bestScore = 0;
  var tie = false;
  for (final e in equipment) {
    final hay = {...words(e.name), ...words(e.code), ...words(e.code.replaceAll('-', ' '))};
    var score = 0;
    for (final t in tokens) {
      if (hay.contains(t)) score += t == number ? 3 : (t.length == 1 ? 1 : 2);
    }
    // The gun / unit number must match when the sheet gives one; otherwise "ALP GUN" matches every gun.
    if (number != null && number.isNotEmpty && !hay.contains(number)) score = 0;
    if (score > bestScore) {
      best = e.id;
      bestScore = score;
      tie = false;
    } else if (score == bestScore && score > 0) {
      tie = true;
    }
  }
  return tie || bestScore < 3 ? null : best;
}
