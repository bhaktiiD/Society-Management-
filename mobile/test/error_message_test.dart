import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

DioException _http(int status, {Object? data}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: data),
  );
}

DioException _of(DioExceptionType type) =>
    DioException(requestOptions: RequestOptions(path: '/x'), type: type);

void main() {
  group('errors shown to people are plain language', () {
    test('offline and slow connections', () {
      expect(errorMessage(_of(DioExceptionType.connectionError)), contains('internet connection'));
      expect(errorMessage(_of(DioExceptionType.receiveTimeout)), contains('longer than usual'));
      expect(errorMessage(TimeoutException('x')), contains('longer than usual'));
    });

    test('server sentences for 4xx pass through, status codes never leak', () {
      expect(errorMessage(_http(409, data: {'detail': 'Sorry, this slot has just been booked.'})),
          'Sorry, this slot has just been booked.');
      for (final status in [400, 403, 404, 409, 422, 500, 503]) {
        final text = errorMessage(_http(status));
        expect(text, isNot(contains('$status')), reason: 'status $status leaked');
        expect(text.toLowerCase(), isNot(contains('exception')));
      }
    });

    test('auth and server failures get calm explanations', () {
      expect(errorMessage(_http(401, data: {'detail': 'Invalid authentication token'})),
          contains('session has expired'));
      expect(errorMessage(_http(500, data: {'detail': 'Traceback ...'})), contains('our side'));
      expect(errorMessage(_http(503)), contains('temporarily unavailable'));
      expect(errorMessage(_http(422, data: {'detail': <Object>[{'loc': 'x'}]})),
          'Please check the details you entered.');
    });

    test('Supabase sign-in errors are translated', () {
      expect(errorMessage(const AuthException('Invalid login credentials')), contains('Wrong email or password'));
      expect(errorMessage(const AuthException('Email not confirmed')), contains('confirm your email'));
      expect(errorMessage(const AuthException('email rate limit exceeded')), contains('Too many emails'));
      expect(errorMessage(const AuthException('User already registered')), contains('already has an account'));
    });

    test('unknown errors never expose class names or stack text', () {
      for (final e in [FormatException('bad'), StateError('boom'), TypeError(), Exception('internal')]) {
        final text = errorMessage(e);
        expect(text, 'Something went wrong. Please try again.');
      }
    });
  });
}
