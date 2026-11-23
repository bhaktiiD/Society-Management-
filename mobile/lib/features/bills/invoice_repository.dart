import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class InvoiceItem {
  const InvoiceItem({required this.title, required this.kind, required this.period, required this.amountPaise});
  final String title;
  final String kind;
  final String? period;
  final int amountPaise;

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        title: (j['title'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        period: j['period'] as String?,
        amountPaise: (j['amount_paise'] ?? 0) as int,
      );
}

class InvoicePayment {
  const InvoicePayment({
    required this.paidOn,
    required this.amountPaise,
    required this.method,
    required this.reference,
    required this.paidByName,
  });
  final String paidOn;
  final int amountPaise;
  final String method;
  final String? reference;
  final String paidByName;

  factory InvoicePayment.fromJson(Map<String, dynamic> j) => InvoicePayment(
        paidOn: (j['paid_on'] ?? '') as String,
        amountPaise: (j['amount_paise'] ?? 0) as int,
        method: (j['method'] ?? '') as String,
        reference: j['reference'] as String?,
        paidByName: (j['paid_by_name'] ?? '') as String,
      );
}

class Invoice {
  const Invoice({
    required this.invoiceNumber,
    required this.issuedOn,
    required this.dueDate,
    required this.status,
    required this.societyName,
    required this.societyAddress,
    required this.flatNumber,
    required this.billedTo,
    required this.items,
    required this.totalPaise,
    required this.paidPaise,
    required this.balancePaise,
    required this.payments,
  });
  final String invoiceNumber;
  final String issuedOn;
  final String dueDate;
  final String status;
  final String societyName;
  final String? societyAddress;
  final String flatNumber;
  final String billedTo;
  final List<InvoiceItem> items;
  final int totalPaise;
  final int paidPaise;
  final int balancePaise;
  final List<InvoicePayment> payments;

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final society = (j['society'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return Invoice(
      invoiceNumber: (j['invoice_number'] ?? '') as String,
      issuedOn: (j['issued_on'] ?? '') as String,
      dueDate: (j['due_date'] ?? '') as String,
      status: (j['status'] ?? 'unpaid') as String,
      societyName: (society['name'] ?? '') as String,
      societyAddress: society['address'] as String?,
      flatNumber: (j['flat_number'] ?? '') as String,
      billedTo: (j['billed_to'] ?? '') as String,
      items: ((j['items'] as List?) ?? const [])
          .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalPaise: (j['total_paise'] ?? 0) as int,
      paidPaise: (j['paid_paise'] ?? 0) as int,
      balancePaise: (j['balance_paise'] ?? 0) as int,
      payments: ((j['payments'] as List?) ?? const [])
          .map((e) => InvoicePayment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LedgerCharge {
  const LedgerCharge({
    required this.id,
    required this.title,
    required this.kind,
    required this.period,
    required this.dueDate,
    required this.amountPaise,
    required this.paidPaise,
    required this.status,
    required this.paidOn,
  });
  final int id;
  final String title;
  final String kind;
  final String? period;
  final String dueDate;
  final int amountPaise;
  final int paidPaise;
  final String status;
  final String? paidOn;

  bool get isPaid => status == 'paid';
  int get balancePaise => (amountPaise - paidPaise).clamp(0, amountPaise);

  factory LedgerCharge.fromJson(Map<String, dynamic> j) => LedgerCharge(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        period: j['period'] as String?,
        dueDate: (j['due_date'] ?? '') as String,
        amountPaise: (j['amount_paise'] ?? 0) as int,
        paidPaise: (j['paid_paise'] ?? 0) as int,
        status: (j['status'] ?? 'unpaid') as String,
        paidOn: j['paid_on'] as String?,
      );
}

class LedgerFlat {
  const LedgerFlat({required this.flatNumber, required this.charges});
  final String flatNumber;
  final List<LedgerCharge> charges;

  factory LedgerFlat.fromJson(Map<String, dynamic> j) => LedgerFlat(
        flatNumber: (j['flat_number'] ?? '') as String,
        charges: ((j['charges'] as List?) ?? const [])
            .map((e) => LedgerCharge.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class InvoiceRepository {
  InvoiceRepository(this._dio);
  final Dio _dio;

  Future<Invoice> invoice(int chargeId) async {
    final r = await _dio.get('/invoices/$chargeId');
    return Invoice.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<LedgerFlat>> ledger() async {
    final r = await _dio.get('/me/ledger');
    return (r.data as List).map((e) => LedgerFlat.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final invoiceRepositoryProvider =
    Provider<InvoiceRepository>((ref) => InvoiceRepository(ref.watch(dioProvider)));

final invoiceProvider = FutureProvider.autoDispose.family<Invoice, int>(
  (ref, id) => ref.watch(invoiceRepositoryProvider).invoice(id),
);

final myLedgerProvider = FutureProvider.autoDispose<List<LedgerFlat>>(
  (ref) => ref.watch(invoiceRepositoryProvider).ledger(),
);
