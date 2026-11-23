import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../auth/auth_repository.dart';
import 'bills_repository.dart';
import 'invoice_screen.dart';
import 'paid_maintenance_card.dart';
import 'pay_controller.dart';

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  @override
  void initState() {
    super.initState();
    // If the app was closed mid-payment, find out what really happened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(payControllerProvider.notifier).recoverInterrupted(),
    );
  }

  Future<void> _pay(Charge charge) async {
    final paise = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PaySheet(charge: charge),
    );
    if (paise == null || !mounted) return;
    final email = ref.read(meProvider).value?.email ?? '';
    ref.read(payControllerProvider.notifier).start(
          charge: charge,
          amountPaise: paise,
          email: email,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PayState>(payControllerProvider, (previous, next) {
      if (next.message == null || previous?.phase == next.phase) return;
      final isError = next.phase == PayPhase.failed;
      showSnack(context, next.message!, error: isError);
    });

    final pay = ref.watch(payControllerProvider);
    final charges = ref.watch(chargesProvider);

    return Column(
      children: [
        if (pay.busy) const LinearProgressIndicator(minHeight: 3),
        Expanded(
          child: AsyncBody<List<Charge>>(
            value: charges,
            onRetry: () => ref.invalidate(chargesProvider),
            builder: (list) {
              if (list.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(chargesProvider);
                    await refreshProvider(() => ref.read(chargesProvider.future));
                  },
                  child: LayoutBuilder(
                      builder: (_, box) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: box.maxHeight,
                            child: const EmptyState(
                              icon: Icons.receipt_long_outlined,
                              message: 'No bills yet.\nYour secretary will add them here.',
                            ),
                          ),
                        ],
                      ),
                    ),
                );
              }
              final due = list.fold<int>(0, (sum, c) => sum + c.balancePaise);
              bool isMaintenance(Charge c) => c.chargeType == 'maintenance' || c.chargeType == 'late_fee';
              final pending = list.where((c) => !c.isPaid).toList()
                ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
              final maintenance = pending.where(isMaintenance).toList();
              final societyFees = pending.where((c) => !isMaintenance(c)).toList();
              final paid = list.where((c) => c.isPaid).toList()
                ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

              Widget section(String title, String subtitle, List<Charge> items) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(subtitle,
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ),
                    for (final c in items) ...[
                      _ChargeCard(charge: c, payDisabled: pay.busy, onPay: () => _pay(c)),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await ref.read(payControllerProvider.notifier).recoverInterrupted();
                  ref.invalidate(chargesProvider);
                  await refreshProvider(() => ref.read(chargesProvider.future));
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _DueSummary(totalDue: due),
                    if (maintenance.isNotEmpty)
                      section(
                        'Maintenance',
                        maintenance.length == 1 ? '1 bill waiting for payment' : '${maintenance.length} bills waiting for payment',
                        maintenance,
                      ),
                    if (societyFees.isNotEmpty)
                      section(
                        'Society fees',
                        societyFees.length == 1
                            ? '1 festival or repair charge waiting'
                            : '${societyFees.length} festival or repair charges waiting',
                        societyFees,
                      ),
                    if (pending.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Nothing is pending right now. You are all set.',
                            style: TextStyle(fontSize: 14, color: AppColors.muted)),
                      ),
                    if (paid.isNotEmpty)
                      section('Paid', 'Your most recent payments', paid.take(5).toList()),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

IconData _chargeIcon(String type) => switch (type) {
      'maintenance' => Icons.apartment,
      'festival' => Icons.celebration_outlined,
      'repair' => Icons.build_outlined,
      'late_fee' => Icons.schedule,
      _ => Icons.receipt_long_outlined,
    };

class _DueSummary extends StatelessWidget {
  const _DueSummary({required this.totalDue});
  final int totalDue;

  @override
  Widget build(BuildContext context) {
    final clear = totalDue == 0;
    if (clear) return const PaidMaintenanceCard();
    return HeroCard(
      label: clear ? 'Everything is paid' : 'Total due',
      value: clear ? '\u{1F389}' : formatRupees(totalDue),
    );
  }
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard({required this.charge, required this.onPay, required this.payDisabled});
  final Charge charge;
  final VoidCallback onPay;
  final bool payDisabled;

  @override
  Widget build(BuildContext context) {
    final chip = switch (charge.status) {
      'paid' => const StatusChip('Paid', tone: ChipTone.success),
      'partial' => const StatusChip('Partly paid', tone: ChipTone.warning),
      _ => charge.overdue
          ? const StatusChip('Overdue', tone: ChipTone.error)
          : const StatusChip('Due', tone: ChipTone.neutral),
    };
    final amountColor = charge.isPaid
        ? AppColors.greenDark
        : charge.overdue
            ? AppColors.error
            : AppColors.ink;
    void openInvoice() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => InvoiceScreen(chargeId: charge.id)),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
       onTap: charge.isPaid ? openInvoice : null,
       child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  _chargeIcon(charge.chargeType),
                  color: charge.overdue ? AppColors.error : AppColors.greenDark,
                  background: charge.overdue ? AppColors.errorTint : AppColors.greenTint,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        charge.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Flat ${charge.flatNumber ?? '-'}',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(padding: const EdgeInsets.only(top: 2), child: chip),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatRupees(charge.isPaid ? charge.amountPaise : charge.balancePaise),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: amountColor),
                      ),
                      const SizedBox(height: 2),
                      if (charge.overdue && !charge.isPaid)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(top: 1, right: 8),
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: const Icon(Icons.priority_high_rounded, size: 13, color: Colors.white),
                            ),
                            Expanded(
                              child: Text(
                                _statusLine(charge),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error, height: 1.3),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          _statusLine(charge),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                if (!(charge.overdue && !charge.isPaid)) ...[
                  const SizedBox(width: 12),
                  _StatusRing(charge: charge),
                ],
              ],
            ),
            if (!charge.isPaid) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: payDisabled ? null : onPay,
                  child: const Text('Pay now'),
                ),
              ),
            ],
            // An invoice exists only once a bill is paid.
            if (charge.isPaid)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0)),
                  onPressed: openInvoice,
                  child: const Text('View invoice'),
                ),
              ),
          ],
        ),
       ),
      ),
    );
  }
}

/// Progress ring on the right of a bill: fills with the paid share, ticks when
/// settled, shows days left while unpaid and a "!" when overdue.
class _StatusRing extends StatelessWidget {
  const _StatusRing({required this.charge});
  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final c = charge;
    final paidFrac = c.amountPaise == 0 ? 0.0 : (c.paidPaise / c.amountPaise).clamp(0.0, 1.0);
    final late = c.overdue && !c.isPaid;
    final color = c.isPaid ? AppColors.green : (late ? AppColors.error : AppColors.orange);
    final track = c.isPaid ? AppColors.greenTint : (late ? AppColors.errorTint : AppColors.orangeTint);

    Widget center;
    if (c.isPaid) {
      center = const Icon(Icons.check_rounded, size: 30, color: AppColors.greenDark);
    } else if (late) {
      center = const Icon(Icons.priority_high_rounded, size: 30, color: AppColors.error);
    } else if (c.paidPaise > 0) {
      center = Text('${(paidFrac * 100).round()}%',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.orange));
    } else {
      final d = DateTime.tryParse(c.dueDate);
      final now = DateTime.now();
      final days = d == null
          ? null
          : DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      center = days == null
          ? const Icon(Icons.hourglass_bottom_rounded, size: 26, color: AppColors.orange)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${days < 0 ? 0 : days}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.orange, height: 1)),
                const Text('days',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.orange, height: 1.2)),
              ],
            );
    }

    final target = c.isPaid ? 1.0 : (late ? 1.0 : (paidFrac == 0 ? 0.04 : paidFrac));
    return ExcludeSemantics(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: track,
                  color: color,
                ),
              ),
            ),
            center,
          ],
        ),
      ),
    );
  }
}

/// One friendly line under the amount: what is left, when it is due, or that it is settled.
String _statusLine(Charge c) {
  if (c.isPaid) return 'Paid in full. Thank you!';
  if (c.paidPaise > 0) {
    return '${formatRupees(c.paidPaise)} paid of ${formatRupees(c.amountPaise)}. Balance due by ${_shortDate(c.dueDate)}';
  }
  final d = DateTime.tryParse(c.dueDate);
  if (d == null) return 'Due by ${_shortDate(c.dueDate)}';
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days < 0) return 'Overdue since ${_shortDate(c.dueDate)}. Please pay soon';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due by ${_shortDate(c.dueDate)} · $days days left';
}

String _shortDate(String iso) {
  final full = formatDate(iso);
  final parts = full.split(' ');
  return parts.length == 3 ? '${parts[0]} ${parts[1]}' : full;
}

/// Bottom sheet: choose how much to pay (full or part). Returns paise.
class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.charge});
  final Charge charge;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final TextEditingController _amount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.charge.balancePaise;
    _amount = TextEditingController(
      text: p % 100 == 0 ? '${p ~/ 100}' : '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final paise = parseRupeesToPaise(_amount.text);
    if (paise == null) {
      setState(() => _error = 'Enter a valid amount, e.g. 500 or 499.50');
    } else if (paise > widget.charge.balancePaise) {
      setState(() => _error = 'Maximum is ${formatRupees(widget.charge.balancePaise)}');
    } else {
      Navigator.pop(context, paise);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.charge.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Outstanding: ${formatRupees(widget.charge.balancePaise)}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount to pay',
              prefixText: '₹ ',
              errorText: _error,
              helperText: 'You can pay part now and the rest later.',
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Continue to payment')),
          const SizedBox(height: 8),
          const Text(
            'Test mode: no real money is charged.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      )),
    );
  }
}
