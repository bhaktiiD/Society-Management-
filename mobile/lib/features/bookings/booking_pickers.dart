import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'bookings_repository.dart';

/// Horizontal date strip. Each chip: Today/weekday, day number, month and a
/// plain word for availability (Free / Some booked / Full).
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.now,
  });
  final List<DayAvailability> days;
  final String selected;
  final ValueChanged<String> onSelect;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _DateChip(
          day: days[i],
          now: now,
          selected: days[i].date == selected,
          onTap: () => onSelect(days[i].date),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.day, required this.now, required this.selected, required this.onTap});
  final DayAvailability day;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = parseIsoDate(day.date);
    final full = day.isFull;
    final fg = selected ? AppColors.onGreen : (full ? AppColors.muted : AppColors.ink);
    final state = full ? 'Full' : (day.isFree ? 'Free' : 'Some booked');
    final top = d == null ? '' : (dayHint(d, now) ?? kWeekdaysShort[d.weekday - 1]);
    return Semantics(
      button: true,
      selected: selected,
      label: '${d == null ? day.date : dateTitle(d)}, $state',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.green : (full ? AppColors.surface : AppColors.greenTint),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: SizedBox(
              width: 82,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(top, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                  Text(d == null ? '' : '${d.day}',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: fg,
                          decoration: full ? TextDecoration.lineThrough : null)),
                  Text(d == null ? '' : kMonthsShort[d.month - 1],
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(state, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Occasion {
  const Occasion(this.label, this.icon);
  final String label;
  final IconData icon;
}

const occasions = [
  Occasion('Birthday', Icons.cake_outlined),
  Occasion('Wedding/Function', Icons.celebration_outlined),
  Occasion('Meeting', Icons.groups_2_outlined),
  Occasion('Pooja/Festival', Icons.auto_awesome_outlined),
  Occasion('Family get-together', Icons.family_restroom_outlined),
  Occasion('Other', Icons.more_horiz),
];

/// Label then text, joined with a colon, or just whichever exists.
String composePurpose(String? label, String text) {
  final t = text.trim();
  if (label == null) return t;
  return t.isEmpty ? label : '$label: $t';
}

/// Inverse of [composePurpose] for pre-filling an existing purpose.
(String?, String) splitPurpose(String purpose) {
  final p = purpose.trim();
  for (final o in occasions) {
    if (p == o.label) return (o.label, '');
    if (p.startsWith('${o.label}: ')) return (o.label, p.substring(o.label.length + 2));
  }
  return (null, p);
}

class OccasionPicker extends StatelessWidget {
  const OccasionPicker({super.key, required this.selected, required this.controller, required this.onSelect});
  final String? selected;
  final TextEditingController controller;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final o in occasions)
          ChoiceChip(
            showCheckmark: false, // green fill already shows selection; the tick overlapped the icon
            avatar: Icon(o.icon, size: 18, color: selected == o.label ? AppColors.onGreen : AppColors.muted),
            label: Text(o.label,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: selected == o.label ? AppColors.onGreen : AppColors.ink)),
            selected: selected == o.label,
            selectedColor: AppColors.green,
            onSelected: (v) => onSelect(v ? o.label : null),
          ),
      ]),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: selected == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: controller,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tell us a little more (optional)'),
                ),
              ),
      ),
    ]);
  }
}

class RequestSummary extends StatelessWidget {
  const RequestSummary({super.key, required this.dateText, required this.timeText, required this.occasion});
  final String dateText;
  final String timeText;
  final String occasion;

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.greenDark),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        _row(Icons.event_outlined, dateText),
        _row(Icons.schedule_outlined, timeText),
        _row(Icons.celebration_outlined, occasion.isEmpty ? 'Occasion not added' : occasion),
        const SizedBox(height: 6),
        const Text('The secretary will confirm your request.',
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
      ]),
    );
  }
}
