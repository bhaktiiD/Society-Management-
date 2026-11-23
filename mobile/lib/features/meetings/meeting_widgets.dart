import 'package:flutter/material.dart';

import '../../core/theme.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monUpper = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String timeText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// "Tue, 5:30 PM"
String weekdayTime(DateTime utc) {
  final d = utc.toLocal();
  return '${_wd[d.weekday - 1]}, ${timeText(d)}';
}

/// "Tue, 25 Nov 2026 at 5:30 PM"
String fullWhen(DateTime utc) {
  final d = utc.toLocal();
  return '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]} ${d.year} at ${timeText(d)}';
}

/// "Today, 5:30 PM" / "Tomorrow, ..." / "Fri 28 Nov, ..."
String friendlyWhen(DateTime utc, DateTime now) {
  final d = utc.toLocal();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = days == 0
      ? 'Today'
      : days == 1
          ? 'Tomorrow'
          : '${_wd[d.weekday - 1]} ${d.day} ${_mon[d.month - 1]}';
  return '$day, ${timeText(d)}';
}

String audienceTag(String audience) => audience == 'owners' ? 'Owners only' : 'Owners and tenants';

class DateBlock extends StatelessWidget {
  const DateBlock(this.utc, {super.key, this.muted = false});
  final DateTime utc;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final d = utc.toLocal();
    final fg = muted ? AppColors.muted : AppColors.greenDark;
    return Container(
      width: 58,
      height: 62,
      decoration: BoxDecoration(
        color: muted ? AppColors.surface : AppColors.greenTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${d.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg, height: 1.1)),
          Text(_monUpper[d.month - 1],
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
