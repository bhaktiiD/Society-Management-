import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';

/// Flat types the society bills by. Keep in sync with billing_service.FLAT_TYPES.
const flatTypes = ['1RK', '1BHK', '2BHK'];

class SecretaryRepository {
  SecretaryRepository(this._dio);
  final Dio _dio;

  Future<Collections> collections() async =>
      Collections.fromJson((await _dio.get('/secretary/collections')).data as Map<String, dynamic>);

  Future<List<Charge>> charges() async => ((await _dio.get('/secretary/charges')).data as List)
      .map((e) => Charge.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<List<FlatInfo>> flats() async => ((await _dio.get('/secretary/flats')).data as List)
      .map((e) => FlatInfo.fromJson(e as Map<String, dynamic>))
      .toList();

  /// Guard / secretary invites (flat invites are listed under their flat).
  Future<List<PendingInvite>> staffInvites() async =>
      ((await _dio.get('/secretary/invites')).data as List)
          .map((e) => PendingInvite.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> revokeInvite(int id) => _dio.delete('/secretary/invites/$id');

  Future<void> endMembership(int id) => _dio.post('/secretary/memberships/$id/end');

  Future<void> createFlat(String flatNumber, {String? flatType}) =>
      _dio.post('/secretary/flats', data: {'flat_number': flatNumber, 'flat_type': flatType});

  Future<void> setFlatType(int flatId, String flatType) =>
      _dio.put('/secretary/flats/$flatId/type', data: {'flat_type': flatType});

  // ---- monthly maintenance settings
  Future<BillingSettings> billingSettings() async =>
      BillingSettings.fromJson((await _dio.get('/secretary/billing')).data as Map<String, dynamic>);

  Future<void> setPlan(String flatType, {required int amountPaise, required int penaltyPaise}) =>
      _dio.put('/secretary/billing/plans/$flatType',
          data: {'amount_paise': amountPaise, 'penalty_paise': penaltyPaise});

  Future<void> setDueDay(int day) => _dio.put('/secretary/billing/due-day', data: {'due_day': day});

  /// Returns "created N bills, M late fees" counts.
  Future<Map<String, dynamic>> runBilling() async =>
      (await _dio.post('/secretary/billing/run')).data as Map<String, dynamic>;

  Future<void> invite({
    required String email,
    required String role,
    int? flatId,
    bool isResident = true,
    String? fullName,
    String? phone,
  }) =>
      _dio.post('/secretary/invites', data: {
        'email': email,
        'role': role,
        'flat_id': flatId,
        'is_resident': isResident,
        'full_name': fullName,
        'phone': phone,
      });

  /// Society-wide festival / repair charge: the server bills EVERY flat.
  /// Returns {created, skipped_flats, billed_owner_instead}.
  Future<Map<String, dynamic>> createSocietyCharge({
    required String chargeType,
    required String title,
    required int amountPaise,
    required DateTime dueDate,
    required String responsible,
  }) async {
    final r = await _dio.post('/secretary/charges', data: {
      'charge_type': chargeType,
      'title': title,
      'amount_paise': amountPaise,
      'due_date': toApiDate(dueDate),
      'responsible': responsible,
    });
    return r.data as Map<String, dynamic>;
  }
}

final secretaryRepositoryProvider =
    Provider<SecretaryRepository>((ref) => SecretaryRepository(ref.watch(dioProvider)));

final collectionsProvider = FutureProvider.autoDispose<Collections>(
  (ref) => ref.watch(secretaryRepositoryProvider).collections(),
);

final secretaryChargesProvider = FutureProvider.autoDispose<List<Charge>>(
  (ref) => ref.watch(secretaryRepositoryProvider).charges(),
);

final billingSettingsProvider = FutureProvider.autoDispose<BillingSettings>(
  (ref) => ref.watch(secretaryRepositoryProvider).billingSettings(),
);

final staffInvitesProvider = FutureProvider.autoDispose<List<PendingInvite>>(
  (ref) => ref.watch(secretaryRepositoryProvider).staffInvites(),
);

final flatsProvider = FutureProvider.autoDispose<List<FlatInfo>>(
  (ref) => ref.watch(secretaryRepositoryProvider).flats(),
);
