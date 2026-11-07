import 'package:intl/intl.dart';

/// "just now", "5 min ago", "3 h ago", "4 days ago" — same wording as the web portal.
String timeAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '—';
  final s = ((now ?? DateTime.now()).difference(t).inSeconds).clamp(0, 1 << 31);
  if (s < 60) return 'just now';
  final m = s ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 48) return '$h h ago';
  return '${h ~/ 24} days ago';
}

final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _date = DateFormat('d MMM yyyy');
final _dayShort = DateFormat('d MMM');

String formatDateTime(DateTime t) => _dateTime.format(t);
String formatDate(DateTime t) => _date.format(t);
String formatDayShort(DateTime t) => _dayShort.format(t);

/// Date-only ISO string (yyyy-MM-dd) for Postgres `date` columns.
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
