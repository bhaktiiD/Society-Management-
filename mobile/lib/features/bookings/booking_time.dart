/// Pure time-range helpers for hall bookings. Times are minutes from midnight.
library;

const int kOpenMin = 8 * 60;
const int kCloseMin = 22 * 60;
const int kStepMin = 30;
const int kMinDurMin = 60;
const int kMaxDurMin = 8 * 60;

const kMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const kMonthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const kWeekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 'HH:MM' -> minutes, or null when malformed.
int? parseHm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 24 || min > 59) return null;
  return h * 60 + min;
}

/// minutes -> 'HH:MM' (24h).
String formatHm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// minutes -> '9 PM' or '9:30 AM'.
String timeText(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  return m == 0 ? '$h12 $suffix' : '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

/// minutes -> '9:00 PM' (always with minutes, for pills).
String timeTextFull(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${(minutes % 60).toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}

/// '1 hour', '2 hours', '30 min', '2 hr 30 min'.
String durationText(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return h == 1 ? '1 hour' : '$h hours';
  return '$h hr $m min';
}

class TimeRange {
  const TimeRange(this.start, this.end);
  final int start;
  final int end;

  int get duration => end - start;

  bool overlaps(TimeRange o) => start < o.end && o.start < end;

  String get label => '${timeText(start)} - ${timeText(end)}';

  static TimeRange? tryParse(Object? start, Object? end) {
    final s = parseHm(start as String?);
    final e = parseHm(end as String?);
    if (s == null || e == null || e <= s) return null;
    return TimeRange(s, e);
  }

  @override
  bool operator ==(Object other) => other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeRange(${formatHm(start)}-${formatHm(end)})';
}

bool overlapsAny(TimeRange r, Iterable<TimeRange> busy) => busy.any(r.overlaps);

/// Snap to the nearest 30 minutes and clamp inside opening hours.
int snapStep(int minutes, {int min = kOpenMin, int max = kCloseMin}) {
  final snapped = ((minutes / kStepMin).round()) * kStepMin;
  return snapped.clamp(min, max);
}

/// Apply a user change (new start/end) and enforce step, min 1h, max 8h and
/// opening hours. The handle that did not move gives way.
TimeRange adjustRange(TimeRange old, int newStart, int newEnd) {
  var s = snapStep(newStart);
  var e = snapStep(newEnd);
  if (s != old.start) {
    s = s.clamp(kOpenMin, kCloseMin - kMinDurMin);
    if (e - s < kMinDurMin) e = s + kMinDurMin;
    if (e - s > kMaxDurMin) e = s + kMaxDurMin;
  } else {
    e = e.clamp(kOpenMin + kMinDurMin, kCloseMin);
    if (e - s < kMinDurMin) s = e - kMinDurMin;
    if (e - s > kMaxDurMin) s = e - kMaxDurMin;
  }
  return TimeRange(s, e);
}

/// True when busy ranges cover the whole opening window.
bool fullyBooked(Iterable<TimeRange> busy, {int open = kOpenMin, int close = kCloseMin}) {
  final sorted = busy.toList()..sort((a, b) => a.start.compareTo(b.start));
  var covered = open;
  for (final r in sorted) {
    if (r.start > covered) return false;
    if (r.end > covered) covered = r.end;
    if (covered >= close) return true;
  }
  return covered >= close;
}

/// First free window of [length] minutes at or after [from] (30-minute steps).
TimeRange? firstFreeWindow(
  Iterable<TimeRange> busy, {
  int from = kOpenMin,
  int length = kMinDurMin,
  int open = kOpenMin,
  int close = kCloseMin,
}) {
  var start = ((from + kStepMin - 1) ~/ kStepMin) * kStepMin;
  if (start < open) start = open;
  for (; start + length <= close; start += kStepMin) {
    final r = TimeRange(start, start + length);
    if (!overlapsAny(r, busy)) return r;
  }
  return null;
}

/// The next half hour strictly after [now], in minutes from midnight.
int nextHalfHour(DateTime now) {
  final m = now.hour * 60 + now.minute;
  return (m ~/ kStepMin + 1) * kStepMin;
}

DateTime? parseIsoDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// 'Today', 'Tomorrow' or null.
String? dayHint(DateTime d, DateTime now) {
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return diff == 0 ? 'Today' : (diff == 1 ? 'Tomorrow' : null);
}

/// 'Fri, 28 Nov'.
String dateTitle(DateTime d) => '${kWeekdaysShort[d.weekday - 1]}, ${d.day} ${kMonthsShort[d.month - 1]}';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
