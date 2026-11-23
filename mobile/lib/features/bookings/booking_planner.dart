import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'booking_pickers.dart';
import 'booking_timeline.dart';
import 'bookings_repository.dart';

/// What the resident chose: date (YYYY-MM-DD), start/end (HH:MM), purpose.
class BookingDraft {
  const BookingDraft(this.date, this.start, this.end, this.purpose);
  final String date;
  final String start;
  final String end;
  final String purpose;
}

/// Date strip + timeline + time controls + occasion + summary + send button.
/// Used on the booking page and inside the "pick a new time" sheet.
class BookingPlanner extends StatefulWidget {
  const BookingPlanner({
    super.key,
    required this.days,
    required this.onSubmit,
    this.initialPurpose = '',
    this.clock = DateTime.now,
  });
  final List<DayAvailability> days;
  final Future<void> Function(BookingDraft draft) onSubmit;
  final String initialPurpose;
  final DateTime Function() clock;

  @override
  State<BookingPlanner> createState() => _BookingPlannerState();
}

class _Slot {
  const _Slot(this.name, this.icon, this.range);
  final String name;
  final IconData icon;
  final TimeRange range;
}

// Four big choices instead of dragging handles; "exact time" stays for odd cases.
const _slots = [
  _Slot('Morning', Icons.wb_sunny_outlined, TimeRange(8 * 60, 12 * 60)),
  _Slot('Afternoon', Icons.light_mode_outlined, TimeRange(12 * 60, 16 * 60)),
  _Slot('Evening', Icons.wb_twilight_outlined, TimeRange(16 * 60, 20 * 60)),
  _Slot('Night', Icons.nights_stay_outlined, TimeRange(20 * 60, 22 * 60)),
];

class _BookingPlannerState extends State<BookingPlanner> {
  late final TextEditingController _note;
  String _date = '';
  TimeRange _range = const TimeRange(18 * 60, 19 * 60);
  String? _occasion;
  bool _sending = false;
  bool _exact = false; // show the fine-grained time controls

  @override
  void initState() {
    super.initState();
    final (label, text) = splitPurpose(widget.initialPurpose);
    _occasion = label;
    _note = TextEditingController(text: text);
    _note.addListener(() => setState(() {}));
    _pickInitial();
  }

  @override
  void didUpdateWidget(BookingPlanner old) {
    super.didUpdateWidget(old);
    if (!widget.days.any((d) => d.date == _date)) _pickInitial();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DayAvailability? get _day {
    for (final d in widget.days) {
      if (d.date == _date) return d;
    }
    return null;
  }

  int _earliest(DayAvailability day) {
    final now = widget.clock();
    final d = parseIsoDate(day.date);
    final isToday = d != null && dayHint(d, now) == 'Today';
    return isToday ? nextHalfHour(now) : day.open;
  }

  TimeRange? _defaultFor(DayAvailability day) =>
      firstFreeWindow(day.busy, from: _earliest(day), open: day.open, close: day.close);

  void _pickInitial() {
    if (widget.days.isEmpty) return;
    final day = widget.days.firstWhere((d) => _defaultFor(d) != null, orElse: () => widget.days.first);
    _date = day.date;
    _range = _defaultFor(day) ?? const TimeRange(kOpenMin, kOpenMin + kMinDurMin);
    _preferSlot(day);
  }

  bool _slotOk(DayAvailability day, TimeRange r) =>
      r.start >= day.open && r.end <= day.close && _valid(day, r);

  /// Snap to the first free preset slot; fall back to exact-time controls.
  void _preferSlot(DayAvailability day) {
    for (final sl in _slots) {
      if (_slotOk(day, sl.range)) {
        _range = sl.range;
        _exact = false;
        return;
      }
    }
    _exact = true;
  }

  bool _valid(DayAvailability day, TimeRange r) => !overlapsAny(r, day.busy) && r.start >= _earliest(day);

  void _selectDate(String iso) {
    final day = widget.days.firstWhere((d) => d.date == iso);
    setState(() {
      _date = iso;
      if (!_valid(day, _range)) {
        _range = _defaultFor(day) ?? _range;
        _preferSlot(day);
      }
    });
  }

  String get _purpose => composePurpose(_occasion, _note.text);

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.onSubmit(BookingDraft(_date, formatHm(_range.start), formatHm(_range.end), _purpose));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    if (day == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No dates to show.', style: TextStyle(color: AppColors.muted))),
      );
    }
    final now = widget.clock();
    final date = parseIsoDate(day.date)!;
    final hint = dayHint(date, now);
    final title = hint == null ? dateTitle(date) : '${dateTitle(date)} - $hint';
    final conflict = overlapsAny(_range, day.busy);
    final passed = !conflict && _range.start < _earliest(day);
    final ok = !conflict && !passed;
    const h = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${kMonthsFull[date.month - 1]} ${date.year}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.muted)),
      const SizedBox(height: 10),
      DateStrip(days: widget.days, selected: _date, onSelect: _selectDate, now: widget.clock()),
      const SizedBox(height: 16),
      Text(title, style: h),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('When do you need the hall?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                for (final sl in _slots)
                  _SlotTile(
                    slot: sl,
                    selected: !_exact && _range == sl.range,
                    available: _slotOk(day, sl.range),
                    onTap: () => setState(() {
                      _range = sl.range;
                      _exact = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => setState(() => _exact = !_exact),
              icon: Icon(_exact ? Icons.expand_less : Icons.tune_rounded),
              label: Text(_exact ? 'Hide exact time' : 'Need a different time?'),
            ),
            if (_exact) ...[
              TimeRangeControls(
                range: _range,
                busy: day.busy,
                earliestStart: _earliest(day),
                onChanged: (r) => setState(() => _range = r),
              ),
            ],
            if (!ok) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.errorTint, borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 20, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conflict
                          ? 'That time is already booked. Please pick another time.'
                          : 'That start time has already passed. Pick a later time today.',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 20),
      const Text('What is the occasion?', style: h),
      const SizedBox(height: 10),
      OccasionPicker(
        selected: _occasion,
        controller: _note,
        onSelect: (v) => setState(() => _occasion = v),
      ),
      const SizedBox(height: 20),
      RequestSummary(
        dateText: title,
        timeText: '${_range.label} (${durationText(_range.duration)})',
        occasion: _purpose,
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: ok && !_sending ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.onGreen))
              : const Text('Send request'),
        ),
      ),
    ]);
  }
}


class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.selected, required this.available, required this.onTap});
  final _Slot slot;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onGreen : (available ? AppColors.ink : AppColors.muted);
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      label: '${slot.name}, ${slot.range.label}, ${available ? 'available' : 'not available'}',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.green : (available ? AppColors.greenTint : AppColors.surface),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: available ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(selected ? Icons.check_circle : slot.icon, size: 22, color: fg),
                    const SizedBox(width: 6),
                    Text(slot.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
                  ]),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    available ? slot.range.label : 'Not available',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
