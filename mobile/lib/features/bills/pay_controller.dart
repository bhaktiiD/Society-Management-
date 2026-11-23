import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import 'bills_repository.dart';

enum PayPhase { idle, creating, checkout, verifying, success, pending, failed }

class PayState {
  const PayState({this.phase = PayPhase.idle, this.message});
  final PayPhase phase;
  final String? message;

  bool get busy =>
      phase == PayPhase.creating ||
      phase == PayPhase.checkout ||
      phase == PayPhase.verifying;
}

const _pendingIntentKey = 'pending_intent_id';

/// Orchestrates one payment attempt:
/// create intent (server decides the amount) -> Razorpay checkout ->
/// tell the server what happened -> trust only the server's answer.
class PayController extends Notifier<PayState> {
  Razorpay? _razorpay;
  PaymentIntent? _intent;
  Timer? _checkoutTimeout;

  @override
  PayState build() {
    ref.onDispose(() {
      _checkoutTimeout?.cancel();
      _razorpay?.clear();
    });
    return const PayState();
  }

  BillsRepository get _repo => ref.read(billsRepositoryProvider);

  Future<void> start({
    required Charge charge,
    required int amountPaise,
    required String email,
  }) async {
    if (state.busy) return;
    state = const PayState(phase: PayPhase.creating);
    try {
      final intent = await _repo.createIntent(
        chargeId: charge.id,
        amountPaise: amountPaise,
        idempotencyKey: _newKey(),
      );
      _intent = intent;
      await _remember(intent.intentId); // survive an app kill mid-checkout

      _razorpay?.clear();
      _razorpay = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

      state = const PayState(phase: PayPhase.checkout);
      // Safety: if Razorpay never calls back, don't leave Pay buttons disabled.
      _checkoutTimeout?.cancel();
      _checkoutTimeout = Timer(const Duration(minutes: 10), () {
        if (state.phase == PayPhase.checkout) state = const PayState();
      });
      _razorpay!.open({
        'key': intent.keyId,
        'order_id': intent.orderId,
        'amount': intent.amountPaise,
        'name': 'SocietyOS',
        'description': charge.title,
        'prefill': {'email': email},
        'theme': {'color': '#58CC02'},
      });
    } catch (error) {
      state = PayState(phase: PayPhase.failed, message: errorMessage(error));
    }
  }

  Future<void> _onSuccess(PaymentSuccessResponse r) async {
    // The checkout callback is only a UX signal. Ask the server to verify.
    state = const PayState(phase: PayPhase.verifying);
    try {
      var status = await _repo.verify(
        orderId: r.orderId ?? _intent?.orderId ?? '',
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      // Not confirmed yet? Poll the recovery endpoint a few times.
      for (var i = 0; i < 5 && status != 'paid'; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        status = await _repo.intentStatus(_intent!.intentId);
      }
      await _finish(status);
    } catch (error) {
      state = PayState(
        phase: PayPhase.pending,
        message: 'We could not confirm your payment yet. Pull to refresh in a moment.',
      );
    }
  }

  void _onError(PaymentFailureResponse r) {
    state = PayState(
      phase: PayPhase.failed,
      // Razorpay's own text is technical; show a calm, accurate message instead.
      message: r.code == Razorpay.PAYMENT_CANCELLED
          ? 'Payment cancelled. You were not charged.'
          : "The payment didn't go through. You were not charged. Please try again.",
    );
  }

  Future<void> _finish(String status) async {
    if (status == 'paid') {
      await _forget();
      state = const PayState(phase: PayPhase.success, message: 'Payment received. Thank you!');
    } else if (status == 'failed') {
      await _forget();
      state = const PayState(phase: PayPhase.failed, message: 'The payment failed.');
    } else {
      state = const PayState(
        phase: PayPhase.pending,
        message: 'Payment is being confirmed. It will show up shortly.',
      );
    }
    ref.invalidate(chargesProvider);
  }

  /// Call on app start / Bills tab open: if an attempt was interrupted,
  /// ask the server what really happened.
  Future<void> recoverInterrupted() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_pendingIntentKey);
    if (id == null || state.busy) return;
    try {
      final status = await _repo.intentStatus(id);
      if (status == 'paid' || status == 'failed') {
        await _forget();
        ref.invalidate(chargesProvider);
        if (status == 'paid') {
          state = const PayState(phase: PayPhase.success, message: 'Your earlier payment was confirmed.');
        }
      }
    } catch (_) {
      // Try again next time the Bills tab opens.
    }
  }

  void reset() => state = const PayState();

  Future<void> _remember(int intentId) async =>
      (await SharedPreferences.getInstance()).setInt(_pendingIntentKey, intentId);

  Future<void> _forget() async =>
      (await SharedPreferences.getInstance()).remove(_pendingIntentKey);

  String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
}

final payControllerProvider =
    NotifierProvider<PayController, PayState>(PayController.new);
