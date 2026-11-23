import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api_client.dart';

class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  /// Change my display name / phone (email and roles are not editable).
  Future<void> updateProfile({required String fullName, String? phone}) =>
      _dio.patch('/me', data: {'full_name': fullName, 'phone': phone});

  // ---- admin only
  Future<String> societyName() async =>
      ((await _dio.get('/secretary/society')).data as Map<String, dynamic>)['name'] as String;

  Future<void> setSocietyName(String name) => _dio.patch('/secretary/society', data: {'name': name});

  // ---- sign-in method
  /// Password sign-in only. Google accounts have no password to change.
  bool get canChangePassword =>
      Supabase.instance.client.auth.currentUser?.appMetadata['provider'] == 'email';

  Future<void> changePassword(String newPassword) async {
    await Supabase.instance.client.auth.updateUser(UserAttributes(password: newPassword));
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(dioProvider)));

final societyNameProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(profileRepositoryProvider).societyName(),
);
