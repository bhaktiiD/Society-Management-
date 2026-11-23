import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'invoice_repository.dart';

/// Full page for one bill (charge), laid out like a printed invoice.
/// "Pay now" only pops back (with the charge id); payment logic stays in Bills.
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.chargeId});
  final int chargeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(invoiceProvider(chargeId));
    final invoice = value.value;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Invoice')),
      body: AsyncBody<Invoice>(
        value: value,
        onRetry: () => ref.invalidate(invoiceProvider(chargeId)),
        builder: (inv) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(invoiceProvider(chargeId));
            await refreshProvider(() => ref.read(invoiceProvider(chargeId).future));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: _InvoicePage(invoice: inv),
          ),
        ),
      ),
      bottomNavigationBar: invoice == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (invoice.balancePaise > 0) ...[
                      FilledButton(
                        onPressed: () => Navigator.pop(context, chargeId),
                        child: const Text('Pay now'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const OutlinedButton(onPressed: null, child: Text('Download PDF')),
                    const SizedBox(height: 4),
                    const Text(
                      'PDF download is coming soon',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

(String, ChipTone) _statusLook(String status) => switch (status) {
      'paid' => ('Paid', ChipTone.success),
      'partial' => ('Partly paid', ChipTone.warning),
      'overdue' => ('Overdue', ChipTone.error),
      _ => ('Unpaid', ChipTone.error),
    };

String _refLabel(String ref) {
  final r = ref.trim();
  final tail = r.length > 4 ? r.substring(r.length - 4) : r;
  return 'ending ${tail.toUpperCase()}';
}

class _InvoicePage extends StatelessWidget {
  const _InvoicePage({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _statusLook(invoice.status);
    final owing = invoice.balancePaise > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.greenTint,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.societyName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      if (invoice.societyAddress != null && invoice.societyAddress!.isNotEmpty)
                        Text(
                          invoice.societyAddress!,
                          style: const TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'INVOICE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: AppColors.greenDark,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        invoice.invoiceNumber,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(label, tone: tone),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    _Meta('Issued', formatDate(invoice.issuedOn)),
                    _Meta('Due', formatDate(invoice.dueDate)),
                    _Meta('Billed to', invoice.billedTo),
                    _Meta('Flat', invoice.flatNumber),
                  ],
                ),
                const SizedBox(height: 20),
                const _Divider(),
                for (final item in invoice.items) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              if (item.period != null && item.period!.isNotEmpty)
                                Text(item.period!,
                                    style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(formatRupees(item.amountPaise),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const _Divider(),
                ],
                const SizedBox(height: 8),
                _TotalRow('Total', formatRupees(invoice.totalPaise)),
                _TotalRow('Paid', formatRupees(invoice.paidPaise), color: AppColors.greenDark),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: owing ? AppColors.errorTint : AppColors.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Balance due',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: owing ? AppColors.error : AppColors.greenDark,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Text(formatRupees(invoice.balancePaise),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: owing ? AppColors.error : AppColors.greenDark,
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (invoice.payments.isEmpty)
                  const Text('No payments yet', style: TextStyle(color: AppColors.muted))
                else
                  for (final p in invoice.payments) _PaymentTile(payment: p),
                const SizedBox(height: 20),
                const Center(
                  child: Text('Thank you',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: AppColors.border);
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.color = AppColors.ink});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.muted))),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final InvoicePayment payment;

  @override
  Widget build(BuildContext context) {
    final ref = payment.reference;
    final parts = [
      payment.method,
      if (ref != null && ref.isNotEmpty) _refLabel(ref),
      if (payment.paidByName.isNotEmpty) 'by ${payment.paidByName}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle, size: 18, color: AppColors.green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(payment.paidOn),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text(parts.join(' · '),
                    style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatRupees(payment.amountPaise),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
        ],
      ),
    );
  }
}
