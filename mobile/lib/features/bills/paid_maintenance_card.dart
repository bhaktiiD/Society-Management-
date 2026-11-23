import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import 'invoice_repository.dart';
import 'invoice_screen.dart';

const _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "2026-11-26" or ISO timestamp -> "26 November".
String _dayMonth(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? iso : '${d.day} ${_longMonths[d.month - 1]}';
}

/// "2026-11" (or a date) -> "November 2026".
String _monthYear(String? period, String fallbackDate) {
  final d = DateTime.tryParse(period == null ? fallbackDate : '$period-01') ??
      DateTime.tryParse(fallbackDate);
  return d == null ? '' : '${_longMonths[d.month - 1]} ${d.year}';
}

/// Shown while nothing is due: the latest paid maintenance with its amount,
/// month and payment date. Falls back to a simple "All paid up" message.
/// The "due" card takes over by itself once a new bill is raised.
class PaidMaintenanceCard extends ConsumerWidget {
  const PaidMaintenanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(myLedgerProvider).value;
    LedgerCharge? latest;
    for (final flat in ledger ?? const <LedgerFlat>[]) {
      for (final c in flat.charges) {
        if (!c.isPaid || c.kind != 'maintenance') continue;
        final key = c.paidOn ?? c.dueDate;
        if (latest == null || key.compareTo(latest.paidOn ?? latest.dueDate) > 0) latest = c;
      }
    }

    if (latest == null) {
      return const HeroCard(label: 'All paid up', value: '\u{1F389}');
    }
    final paid = latest;
    final month = _monthYear(paid.period, paid.dueDate);
    final paidOn = paid.paidOn == null ? null : 'Paid on ${_dayMonth(paid.paidOn!)}';
    return Semantics(
      button: true,
      label: 'Maintenance paid ${formatRupees(paid.amountPaise)} for $month. ${paidOn ?? ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => InvoiceScreen(chargeId: paid.id)),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.heroStart, AppColors.heroEnd],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Maintenance paid',
                        style: TextStyle(fontSize: 15, color: AppColors.greenDark, fontWeight: FontWeight.w700)),
                  ),
                  if (month.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(month,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(formatRupees(paid.amountPaise),
                          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: IconBadge(Icons.check_circle_rounded,
                        color: AppColors.greenDark, background: Colors.white, size: 52),
                  ),
                ],
              ),
              if (paidOn != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.event_available_rounded, size: 18, color: AppColors.greenDark),
                    const SizedBox(width: 8),
                    Text(paidOn,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
