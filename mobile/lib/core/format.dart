/// Money is integer paise everywhere. Never use double for currency.
String formatRupees(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = abs % 100;
  final grouped = _indianGrouping(rupees.toString());
  final text = fraction == 0
      ? '₹$grouped'
      : '₹$grouped.${fraction.toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

/// 1234567 -> 12,34,567 (Indian digit grouping).
String _indianGrouping(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// "1250", "1250.5", "1250.50" -> paise, without floating point.
/// Returns null for anything that is not a valid positive amount.
int? parseRupeesToPaise(String input) {
  final text = input.trim().replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final rupees = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final paise = rupees * 100 + int.parse(fraction);
  return paise > 0 ? paise : null;
}

/// Like [parseRupeesToPaise] but "0" is allowed (for an optional fee).
int? parseRupeesAllowZero(String input) {
  final paise = parseRupeesToPaise(input);
  if (paise != null) return paise;
  return RegExp(r'^0+(\.0{1,2})?$').hasMatch(input.trim()) ? 0 : null;
}

/// 1 -> "1st", 2 -> "2nd", 11 -> "11th", 22 -> "22nd".
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Paise -> text for an input box: 150000 -> "1500", 150050 -> "1500.50".
String paiseToInput(int paise) => paise % 100 == 0
    ? '${paise ~/ 100}'
    : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2026-11-24" or an ISO timestamp -> "24 Nov 2026".
String formatDate(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// ISO timestamp -> "24 Nov, 6:05 PM".
String formatDateTime(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final suffix = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${_months[d.month - 1]}, $hour12:$minute $suffix';
}

/// DateTime -> "2026-11-24" for the API.
String toApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
