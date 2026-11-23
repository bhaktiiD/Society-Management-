import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend address. Override per build:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
/// With a USB phone + `adb reverse tcp:8000 tcp:8000` the default works.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// A single, shared Dio client:
///  * attaches the Supabase access token to every request,
///  * on a 401 refreshes the session once and retries.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = Supabase.instance.client.auth.currentSession?.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        final alreadyRetried = request.extra['retried'] == true;
        if (error.response?.statusCode == 401 && !alreadyRetried) {
          try {
            final refreshed = await Supabase.instance.client.auth
                .refreshSession();
            final token = refreshed.session?.accessToken;
            if (token != null) {
              request.extra['retried'] = true;
              request.headers['Authorization'] = 'Bearer $token';
              try {
                return handler.resolve(await dio.fetch(request));
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
          } catch (_) {
            // fall through to the original error
          }
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});

/// Turns ANY thrown error into a short, plain-language message for a person
/// (never a status code, stack trace or class name).
String errorMessage(Object error) {
  if (error is DioException) return _networkMessage(error);
  if (error is AuthException) return _authMessage(error);
  if (error is TimeoutException) return _slow;
  final type = error.runtimeType.toString();
  if (type.contains('SocketException') || type.contains('HandshakeException')) {
    return _offline;
  }
  return _generic;
}

const _generic = 'Something went wrong. Please try again.';
const _offline = "We can't reach the server. Check your internet connection and try again.";
const _slow = 'This is taking longer than usual. Please try again.';

String _networkMessage(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return _slow;
    case DioExceptionType.connectionError:
      return _offline;
    case DioExceptionType.cancel:
      return _generic;
    case DioExceptionType.badCertificate:
      return "We couldn't make a secure connection. Please try again.";
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }

  final status = e.response?.statusCode;
  final data = e.response?.data;
  final detail = (data is Map && data['detail'] is String) ? (data['detail'] as String).trim() : null;

  switch (status) {
    case 401:
      return 'Your session has expired. Please sign in again.';
    case 429:
      return 'Too many attempts. Please wait a moment and try again.';
    case 502:
    case 503:
    case 504:
      return 'The service is temporarily unavailable. Please try again shortly.';
  }
  if (status != null && status >= 500) {
    return 'Something went wrong on our side. Please try again in a moment.';
  }
  // 400-level: the server already sends a plain-language sentence.
  if (detail != null && detail.isNotEmpty) return detail;
  if (data is Map && data['detail'] is List) return 'Please check the details you entered.';
  switch (status) {
    case 403:
      return "You don't have permission to do that.";
    case 404:
      return "We couldn't find that. It may have been removed.";
    case 409:
      return 'That has already changed. Please refresh and try again.';
    case 422:
      return 'Please check the details you entered.';
  }
  return e.type == DioExceptionType.unknown ? _offline : _generic;
}

String _authMessage(AuthException e) {
  if (e is AuthRetryableFetchException) return _offline;
  final code = (e.code ?? '').toLowerCase();
  final msg = e.message.toLowerCase();
  bool has(String s) => code.contains(s) || msg.contains(s);

  if (has('invalid_credentials') || has('invalid login')) {
    return 'Wrong email or password. Please try again.';
  }
  if (has('email_not_confirmed') || has('not confirmed')) {
    return 'Please confirm your email first. Check your inbox for the link.';
  }
  if (has('rate_limit') || has('rate limit') || has('too many')) {
    return 'Too many emails were sent. Please wait a few minutes and try again.';
  }
  if (has('already registered') || has('user_already_exists') || has('already exists')) {
    return 'This email already has an account. Try signing in instead.';
  }
  if (has('weak_password') || has('weak password') || has('at least')) {
    return 'That password is too weak. Use at least 8 characters with letters and numbers.';
  }
  if (has('same_password') || has('different from the old')) {
    return 'Please choose a password different from your current one.';
  }
  if (has('session') || has('refresh_token') || has('jwt')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (has('network') || has('socket') || has('failed host lookup')) return _offline;
  return "We couldn't complete that. Please try again.";
}
