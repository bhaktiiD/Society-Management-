import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'bookings_repository.dart';

/// Date choice without sideways scrolling: Today / Tomorrow shortcuts plus one
/// big card that opens a calendar. Fully booked days are greyed out there.
class DatePickField extends StatelessWidget {
  const DatePickField({
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

  DayAvailability? _hint(String label) {
    for (final d in days) {
      final p = parseIsoDate(d.date);
      if (p != null && dayHint(p, now) == label) return d;
    }
    return null;
  }

  Future<void> _openCalendar(BuildContext context) async {
    final open = {for (final d in days) if (!d.isFull) d.date};
    final dates = days.map((d) => parseIsoDate(d.date)).whereType<DateTime>().toList()..sort();
    if (dates.isEmpty) return;
    final cur = parseIsoDate(selected) ?? dates.first;
    final picked = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: dates.first,
      lastDate: dates.last,
      helpText: 'Choose a date',
      selectableDayPredicate: (d) => open.contains(isoDate(d)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.green, onPrimary: AppColors.onGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null) onSelect(isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final d = parseIsoDate(selected);
    final hint = d == null ? null : dayHint(d, now);
    final title = d == null ? 'Choose a date' : '${dateTitle(d)}${hint == null ? '' : ' - $hint'}';
    final quick = [('Today', _hint('Today')), ('Tomorrow', _hint('Tomorrow'))];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [
        for (final (label, day) in quick)
          if (day != null)
            ChoiceChip(
              showCheckmark: false,
              label: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected == day.date ? AppColors.onGreen : (day.isFull ? AppColors.muted : AppColors.ink))),
              selected: selected == day.date,
              selectedColor: AppColors.green,
              onSelected: day.isFull ? null : (_) => onSelect(day.date),
            ),
      ]),
      const SizedBox(height: 10),
      Semantics(
        button: true,
        label: '$title. Tap to choose another date',
        child: ExcludeSemantics(
          child: Material(
            color: AppColors.greenTint,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openCalendar(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  const Icon(Icons.calendar_month_rounded, color: AppColors.greenDark, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const Text('Your day - tap to change',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    ]),
                  ),
                  const Icon(Icons.expand_more, color: AppColors.muted),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
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
