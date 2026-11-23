import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

class NoticesRepository {
  NoticesRepository(this._dio);
  final Dio _dio;

  Future<List<Notice>> list() async {
    final r = await _dio.get('/notices');
    return (r.data as List).map((e) => Notice.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> post({required String title, required String body, required bool pinned}) =>
      _dio.post('/secretary/notices', data: {'title': title, 'body': body, 'pinned': pinned});

  Future<void> delete(int id) => _dio.delete('/secretary/notices/$id');
}

final noticesRepositoryProvider =
    Provider<NoticesRepository>((ref) => NoticesRepository(ref.watch(dioProvider)));

final noticesProvider = FutureProvider.autoDispose<List<Notice>>(
  (ref) => ref.watch(noticesRepositoryProvider).list(),
);
