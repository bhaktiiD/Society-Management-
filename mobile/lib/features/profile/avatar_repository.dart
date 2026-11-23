import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Profile photo calls: GET / PUT / DELETE /me/avatar.
class AvatarRepository {
  AvatarRepository(this._dio);
  final Dio _dio;

  /// The photo bytes, or null when the user has none.
  Future<Uint8List?> fetch() async {
    try {
      final res = await _dio.get<List<int>>(
        '/me/avatar',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> upload(Uint8List bytes, String contentType) async {
    await _dio.put<void>(
      '/me/avatar',
      data: bytes,
      options: Options(
        contentType: contentType,
        headers: {Headers.contentLengthHeader: bytes.length},
      ),
    );
  }

  Future<void> remove() => _dio.delete<void>('/me/avatar');
}

final avatarRepositoryProvider =
    Provider<AvatarRepository>((ref) => AvatarRepository(ref.watch(dioProvider)));

/// Photo bytes keyed by avatar version: a new version loads fresh, the same
/// one is kept in memory instead of being downloaded again.
final avatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, int?>((ref, version) {
  ref.keepAlive();
  if (version == null) return null;
  return ref.read(avatarRepositoryProvider).fetch();
});
