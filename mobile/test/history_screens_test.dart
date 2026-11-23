import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/bills/invoice_repository.dart';
import 'package:mobile/features/bills/invoice_screen.dart';
import 'package:mobile/features/bills/maintenance_history_screen.dart';
import 'package:mobile/features/society/society_history_screen.dart';
import 'package:mobile/features/society/society_repository.dart';

Widget _host(Widget child, List<Override> overrides, {double scale = 1.4}) => ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), size: const Size(360, 2400)),
          child: w!,
        ),
        home: child,
      ),
    );

const _invoiceJson = {
  'invoice_number': 'INV-0001',
  'issued_on': '2026-11-01',
  'due_date': '2026-11-10',
  'status': 'partial',
  'society': {'name': 'Green Heights', 'address': null},
  'flat_number': 'A-101',
  'billed_to': 'Asha Rao',
  'items': [
    {'title': 'Maintenance', 'kind': 'maintenance', 'period': 'Nov 2026', 'amount_paise': 200000},
  ],
  'total_paise': 200000,
  'paid_paise': 50000,
  'balance_paise': 150000,
  'payments': [
    {'paid_on': '2026-11-05T10:00:00', 'amount_paise': 50000, 'method': 'UPI', 'reference': 'abc4f2a', 'paid_by_name': 'Asha Rao'},
  ],
};

void main() {
  test('Invoice.fromJson parses contract', () {
    final i = Invoice.fromJson(_invoiceJson);
    expect(i.societyAddress, isNull);
    expect(i.items.single.amountPaise, 200000);
    expect(i.payments.single.reference, 'abc4f2a');
  });

  testWidgets('invoice shows balance, pay now and PDF caption', (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(
      const InvoiceScreen(chargeId: 1),
      [invoiceProvider(1).overrideWith((ref) async => Invoice.fromJson(_invoiceJson))],
    ));
    await t.pumpAndSettle();
    expect(find.text('INVOICE'), findsOneWidget);
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);
    expect(find.text('PDF download is coming soon'), findsOneWidget);
    expect(find.textContaining('ending 4F2A'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('payment history totals, filter and empty state', (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final flats = [
      LedgerFlat(flatNumber: 'A-101', charges: [
        LedgerCharge.fromJson({
          'id': 1, 'title': 'Nov maintenance', 'kind': 'maintenance', 'period': '2026-11',
          'due_date': '2026-11-10', 'amount_paise': 200000, 'paid_paise': 200000,
          'status': 'paid', 'paid_on': '2026-11-05',
        }),
        LedgerCharge.fromJson({
          'id': 2, 'title': 'Diwali', 'kind': 'festival', 'period': null,
          'due_date': '2026-10-10', 'amount_paise': 50000, 'paid_paise': 0,
          'status': 'unpaid', 'paid_on': null,
        }),
      ]),
    ];
    await t.pumpWidget(_host(const MaintenanceHistoryScreen(), [myLedgerProvider.overrideWith((ref) async => flats)]));
    await t.pumpAndSettle();
    expect(find.text('Paid so far'), findsOneWidget);
    expect(find.text('Paid on 5 Nov'), findsOneWidget);
    await t.tap(find.text('Pending').last);
    await t.pumpAndSettle();
    expect(find.text('Nov maintenance'), findsNothing);
    expect(find.text('Diwali'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(_host(const MaintenanceHistoryScreen(), [myLedgerProvider.overrideWith((ref) async => <LedgerFlat>[])]));
    await t.pumpAndSettle();
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets('society history renders at 1.4x text', (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SocietySummary.fromJson({
      'society_name': 'Green Heights',
      'flat_count': 10,
      'months': [
        {'month': '2026-11', 'billed_paise': 1000000, 'collected_paise': 600000, 'flats_billed': 10, 'flats_fully_paid': 6},
      ],
      'society_charges': [
        {'id': 1, 'title': 'Diwali celebration', 'kind': 'festival', 'amount_per_flat_paise': 50000,
         'due_date': '2026-11-10', 'created_at': '2026-10-01T00:00:00', 'flats_billed': 10, 'flats_paid': 4},
      ],
      'totals': {'collected_all_time_paise': 600000, 'billed_all_time_paise': 1000000},
    });
    await t.pumpWidget(_host(const SocietyHistoryScreen(), [societySummaryProvider.overrideWith((ref) async => s)]));
    await t.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('6 of 10 flats paid'), findsOneWidget);
    expect(find.text('Diwali celebration'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
