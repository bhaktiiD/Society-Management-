import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'invoice_repository.dart';
import 'invoice_screen.dart';

enum _Filter { all, paid, pending }

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _shortDate(String iso) {
  final parts = formatDate(iso).split(' ');
  return parts.length == 3 ? '${parts[0]} ${parts[1]}' : formatDate(iso);
}

/// "2026-11-10" -> "November 2026" (falls back to the raw text).
String monthHeading(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_monthNames[d.month - 1]} ${d.year}';
}

/// Full page: the resident's own bills and payments, newest first.
class MaintenanceHistoryScreen extends ConsumerStatefulWidget {
  const MaintenanceHistoryScreen({super.key});

  @override
  ConsumerState<MaintenanceHistoryScreen> createState() => _MaintenanceHistoryScreenState();
}

class _MaintenanceHistoryScreenState extends ConsumerState<MaintenanceHistoryScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _refresh() async {
    ref.invalidate(myLedgerProvider);
    await refreshProvider(() => ref.read(myLedgerProvider.future));
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(myLedgerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My payment history')),
      body: AsyncBody<List<LedgerFlat>>(
        value: ledger,
        onRetry: () => ref.invalidate(myLedgerProvider),
        builder: (flats) {
          final all = [for (final f in flats) ...f.charges];
          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: LayoutBuilder(
                builder: (_, box) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: box.maxHeight,
                      child: const EmptyState(icon: Icons.receipt_long_outlined, message: 'No payments yet'),
                    ),
                  ],
                ),
              ),
            );
          }
          final paid = all.fold<int>(0, (s, c) => s + c.paidPaise);
          final pending = all.fold<int>(0, (s, c) => s + c.balancePaise);
          final shown = all.where((c) => switch (_filter) {
                _Filter.all => true,
                _Filter.paid => c.isPaid,
                _Filter.pending => !c.isPaid,
              }).toList();

          // Group by due-date month, keeping the server's newest-first order.
          final groups = <String, List<LedgerCharge>>{};
          for (final c in shown) {
            groups.putIfAbsent(monthHeading(c.dueDate), () => []).add(c);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(paid: paid, pending: pending),
                const SizedBox(height: 16),
                _FilterToggle(value: _filter, onChanged: (f) => setState(() => _filter = f)),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'Nothing to show here',
                    ),
                  ),
                for (final e in groups.entries) ...[
                  SectionHeader(e.key),
                  for (final c in e.value) ...[
                    _LedgerRow(charge: c),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.paid, required this.pending});
  final int paid;
  final int pending;

  Widget _cell(String label, int paise, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.greenDark)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatRupees(paise),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.heroStart, AppColors.heroEnd],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cell('Paid so far', paid, AppColors.ink),
            const SizedBox(width: 12),
            _cell('Pending', pending, pending > 0 ? AppColors.error : AppColors.ink),
          ],
        ),
      );
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.value, required this.onChanged});
  final _Filter value;
  final ValueChanged<_Filter> onChanged;

  static const _labels = {_Filter.all: 'All', _Filter.paid: 'Paid', _Filter.pending: 'Pending'};

  @override
  Widget build(BuildContext context) {
    final index = _Filter.values.indexOf(value);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment(-1.0 + index, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final f in _Filter.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: f == value,
                    label: _labels[f],
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onChanged(f),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _labels[f]!,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: f == value ? FontWeight.w800 : FontWeight.w600,
                                color: f == value ? AppColors.greenDark : AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.charge});
  final LedgerCharge charge;

  @override
  Widget build(BuildContext context) {
    final c = charge;
    final chip = switch (c.status) {
      'paid' => const StatusChip('Paid', tone: ChipTone.success),
      'partial' => const StatusChip('Partly paid', tone: ChipTone.warning),
      'overdue' => const StatusChip('Overdue', tone: ChipTone.error),
      _ => const StatusChip('Unpaid', tone: ChipTone.error),
    };
    final sub = c.isPaid && c.paidOn != null ? 'Paid on ${_shortDate(c.paidOn!)}' : 'Due ${_shortDate(c.dueDate)}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Only paid bills have an invoice.
        onTap: c.isPaid
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => InvoiceScreen(chargeId: c.id)),
                )
            : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupees(c.amountPaise),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  chip,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
