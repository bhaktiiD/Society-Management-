import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'society_repository.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "2026-11" -> "November 2026".
String societyMonthName(String ym) {
  final parts = ym.split('-');
  final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return ym;
  return '${_monthNames[m - 1]} ${parts[0]}';
}

double _ratio(int part, int whole) => whole <= 0 ? 0 : (part / whole).clamp(0.0, 1.0);

/// Full page: society-wide records, no personal details.
class SocietyHistoryScreen extends ConsumerWidget {
  const SocietyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(societySummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Society history')),
      body: AsyncBody<SocietySummary>(
        value: summary,
        onRetry: () => ref.invalidate(societySummaryProvider),
        builder: (s) {
          final months = s.months.length > 12 ? s.months.sublist(0, 12) : s.months;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(societySummaryProvider);
              await refreshProvider(() => ref.read(societySummaryProvider.future));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'How the society is doing (no personal details)',
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                _TotalsCard(s: s),
                const SectionHeader('Monthly collection'),
                if (months.isEmpty)
                  const SizedBox(
                    height: 160,
                    child: EmptyState(icon: Icons.calendar_month_outlined, message: 'No monthly records yet'),
                  )
                else
                  for (final m in months) ...[_MonthRow(m: m), const SizedBox(height: 8)],
                const SectionHeader('Festival and repair charges'),
                if (s.societyCharges.isEmpty)
                  const SizedBox(
                    height: 160,
                    child: EmptyState(icon: Icons.celebration_outlined, message: 'No special charges yet'),
                  )
                else
                  for (final c in s.societyCharges) ...[_ChargeTile(c: c), const SizedBox(height: 8)],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.value, {this.height = 6});
  final double value;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value,
          minHeight: height,
          backgroundColor: AppColors.surface,
          valueColor: const AlwaysStoppedAnimation(AppColors.green),
        ),
      );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.s});
  final SocietySummary s;

  @override
  Widget build(BuildContext context) {
    final r = _ratio(s.collectedAllTimePaise, s.billedAllTimePaise);
    return HeroCard(
      label: 'Collected so far',
      value: formatRupees(s.collectedAllTimePaise),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bar(r, height: 10),
          const SizedBox(height: 8),
          Text(
            'of ${formatRupees(s.billedAllTimePaise)} billed (${(r * 100).round()}%)',
            style: const TextStyle(fontSize: 14, color: AppColors.greenDark, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.m});
  final MonthSummary m;

  @override
  Widget build(BuildContext context) {
    final r = _ratio(m.flatsFullyPaid, m.flatsBilled);
    return _Row(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(societyMonthName(m.month),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text('${m.flatsFullyPaid} of ${m.flatsBilled} flats paid',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupees(m.collectedPaise),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.greenDark)),
                  Text('of ${formatRupees(m.billedPaise)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Bar(r)),
              const SizedBox(width: 10),
              Text('${(r * 100).round()}%',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChargeTile extends StatelessWidget {
  const _ChargeTile({required this.c});
  final SocietyCharge c;

  @override
  Widget build(BuildContext context) {
    final r = _ratio(c.flatsPaid, c.flatsBilled);
    return _Row(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text('Due ${formatDate(c.dueDate)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupees(c.amountPerFlatPaise),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const Text('per flat', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${c.flatsPaid} of ${c.flatsBilled} flats paid',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _Bar(r),
        ],
      ),
    );
  }
}
