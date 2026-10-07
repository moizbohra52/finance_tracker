import 'dart:io';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('auth error codes become specific, friendly messages', () {
    expect(
      mapSupabaseError(
        const AuthApiException('raw', code: 'invalid_credentials'),
      ),
      isA<AuthFailure>().having(
        (AuthFailure f) => f.message,
        'message',
        'Incorrect email or password.',
      ),
    );
    expect(
      mapSupabaseError(
        const AuthApiException('raw', code: 'email_exists'),
      ).message,
      contains('already exists'),
    );
    expect(
      mapSupabaseError(
        const AuthApiException('raw', code: 'otp_expired'),
      ).message,
      contains('expired'),
    );
  });

  test('unknown auth codes never leak the raw server message', () {
    final AppException failure = mapSupabaseError(
      const AuthApiException('internal detail', code: 'something_new'),
    );
    expect(failure, isA<AuthFailure>());
    expect(failure.message, isNot(contains('internal detail')));
  });

  test('connectivity problems become NetworkFailure', () {
    expect(
      mapSupabaseError(AuthRetryableFetchException()),
      isA<NetworkFailure>(),
    );
    expect(
      mapSupabaseError(const SocketException('down')),
      isA<NetworkFailure>(),
    );
    expect(
      mapSupabaseError(http.ClientException('down')),
      isA<NetworkFailure>(),
    );
  });

  test('database errors map by code', () {
    expect(
      mapSupabaseError(const PostgrestException(message: 'rls', code: '42501')),
      isA<AuthFailure>(),
    );
    expect(
      mapSupabaseError(const PostgrestException(message: 'x', code: '23505')),
      isA<DatabaseFailure>(),
    );
  });

  test('AppExceptions pass through and anything else is unexpected', () {
    const NetworkFailure network = NetworkFailure();
    expect(mapSupabaseError(network), same(network));
    expect(
      mapSupabaseError(const FormatException('x')),
      isA<UnexpectedFailure>(),
    );
  });

  test('guardSupabase rethrows mapped failures', () async {
    await expectLater(
      guardSupabase<void>(() async => throw const SocketException('down')),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
