import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

class BillsRepository {
  BillsRepository(this._dio);
  final Dio _dio;

  Future<List<Charge>> myCharges() async {
    final r = await _dio.get('/charges');
    return (r.data as List).map((e) => Charge.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Safe to retry with the same [idempotencyKey]: the server returns the
  /// same intent instead of creating a second gateway order.
  Future<PaymentIntent> createIntent({
    required int chargeId,
    required int amountPaise,
    required String idempotencyKey,
  }) async {
    final r = await _dio.post('/payments/intents', data: {
      'charge_id': chargeId,
      'amount_paise': amountPaise,
      'idempotency_key': idempotencyKey,
    });
    return PaymentIntent.fromJson(r.data as Map<String, dynamic>);
  }

  /// Tells the server what Razorpay returned. The server re-checks the
  /// signature and asks Razorpay itself; this is not proof on its own.
  Future<String> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final r = await _dio.post('/payments/verify', data: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    return (r.data as Map<String, dynamic>)['status'] as String;
  }

  /// Recovery: ask the server for the real outcome (also reconciles with the
  /// gateway). Used after a crash, a lost response, or a pending verify.
  Future<String> intentStatus(int intentId) async {
    final r = await _dio.get('/payments/intents/$intentId/status');
    return (r.data as Map<String, dynamic>)['status'] as String;
  }
}

final billsRepositoryProvider =
    Provider<BillsRepository>((ref) => BillsRepository(ref.watch(dioProvider)));

final chargesProvider = FutureProvider.autoDispose<List<Charge>>(
  (ref) => ref.watch(billsRepositoryProvider).myCharges(),
);
