import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'booking_time.dart';

/// Exact-time fallback: just a From and a To box. Tapping one opens a plain
/// list of times; times that are booked or too early are greyed out.
class TimeRangeControls extends StatelessWidget {
  const TimeRangeControls({
    super.key,
    required this.range,
    required this.busy,
    required this.earliestStart,
    required this.onChanged,
  });
  final TimeRange range;
  final List<TimeRange> busy;

  /// Earliest allowed start in minutes (later than opening when booking today).
  final int earliestStart;
  final ValueChanged<TimeRange> onChanged;

  List<(int, bool)> _options(bool isStart) {
    final out = <(int, bool)>[];
    if (isStart) {
      for (var t = kOpenMin; t <= kCloseMin - kMinDurMin; t += kStepMin) {
        out.add((t, t >= earliestStart && !overlapsAny(TimeRange(t, t + kMinDurMin), busy)));
      }
    } else {
      for (var t = range.start + kMinDurMin; t <= kCloseMin && t - range.start <= kMaxDurMin; t += kStepMin) {
        out.add((t, !overlapsAny(TimeRange(range.start, t), busy)));
      }
    }
    return out;
  }

  Future<void> _pick(BuildContext context, bool isStart) async {
    final cur = isStart ? range.start : range.end;
    final options = _options(isStart);
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(isStart ? 'Start time' : 'End time',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final (t, ok) in options)
                ListTile(
                  enabled: ok,
                  selected: t == cur,
                  selectedColor: AppColors.greenDark,
                  title: Text(timeTextFull(t),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  subtitle: ok ? null : const Text('Not available'),
                  trailing: t == cur ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, t),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    onChanged(isStart ? adjustRange(range, picked, range.end) : adjustRange(range, range.start, picked));
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: TimeField(label: 'From', value: timeTextFull(range.start), onTap: () => _pick(context, true))),
      const SizedBox(width: 12),
      Expanded(child: TimeField(label: 'To', value: timeTextFull(range.end), onTap: () => _pick(context, false))),
    ]);
  }
}

class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $value. Tap to change',
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.expand_more, color: AppColors.muted),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
