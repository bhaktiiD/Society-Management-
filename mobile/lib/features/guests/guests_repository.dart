import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

List<GuestRequest> _parse(dynamic data) => (data as List)
    .map((e) => GuestRequest.fromJson(e as Map<String, dynamic>))
    .toList();

class GuestsRepository {
  GuestsRepository(this._dio);
  final Dio _dio;

  // ---- resident
  Future<List<GuestRequest>> pending() async => _parse((await _dio.get('/guests/pending')).data);
  Future<List<GuestRequest>> history() async => _parse((await _dio.get('/guests/history')).data);
  Future<void> decide(int id, {required bool approve}) =>
      _dio.post('/guests/$id/decision', data: {'approve': approve});

  // ---- guard
  Future<List<GuestRequest>> guardList() async => _parse((await _dio.get('/guard/guests')).data);
  Future<void> requestEntry({
    required String flatNumber,
    required String guestName,
    String? phone,
    String? purpose,
  }) =>
      _dio.post('/guard/guests', data: {
        'flat_number': flatNumber,
        'guest_name': guestName,
        'guest_phone': phone,
        'purpose': purpose,
      });
  Future<void> checkIn(int id) => _dio.post('/guard/guests/$id/check-in');
  Future<void> checkOut(int id) => _dio.post('/guard/guests/$id/check-out');
}

final guestsRepositoryProvider =
    Provider<GuestsRepository>((ref) => GuestsRepository(ref.watch(dioProvider)));

final pendingGuestsProvider = FutureProvider.autoDispose<List<GuestRequest>>(
  (ref) => ref.watch(guestsRepositoryProvider).pending(),
);

final guestHistoryProvider = FutureProvider.autoDispose<List<GuestRequest>>(
  (ref) => ref.watch(guestsRepositoryProvider).history(),
);

final guardGuestsProvider = FutureProvider.autoDispose<List<GuestRequest>>(
  (ref) => ref.watch(guestsRepositoryProvider).guardList(),
);
