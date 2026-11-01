import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';

/// What a reader sees when something fails must be written for them. A caught
/// error's `toString()` showed "ApiException(404): Request failed" on screen,
/// and can carry whatever the request held.
void main() {
  group('describeError', () {
    test('an uncoded server error is described by its status', () {
      for (final status in [
        0,
        400,
        401,
        403,
        404,
        410,
        413,
        422,
        429,
        500,
        503,
      ]) {
        final text = describeError(ApiException(status, 'Internal details'));
        expect(text, isNot(contains('Internal details')), reason: '$status');
        expect(text, isNot(contains('ApiException')), reason: '$status');
      }
    });

    test('a coded error keeps the words written for it', () {
      expect(
        describeError(ApiException(410, 'x', code: AppErrorCode.linkExpired)),
        'This link has expired.',
      );
      expect(
        describeError(ApiException(400, 'Written by us', code: 'new_code')),
        'Written by us',
      );
    });

    test('a network failure says so, without its details', () {
      for (final error in [
        const SocketException('Failed host lookup: internal.example'),
        http.ClientException('Connection refused', Uri.parse('http://x')),
        const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        TimeoutException('slow'),
      ]) {
        expect(
          describeError(error),
          'Check your connection, then try again.',
          reason: '$error',
        );
      }
    });

    test('words written for the reader pass through', () {
      expect(
        describeError(const SealingException('Choose a workspace first.')),
        'Choose a workspace first.',
      );
      expect(
        describeError(const UserFacingException('Sign in first.')),
        'Sign in first.',
      );
    });

    test('anything else never reaches the screen', () {
      for (final error in [
        StateError('secret-state'),
        const FormatException('secret-format'),
        Exception('secret-exception'),
      ]) {
        expect(describeError(error), isNot(contains('secret')));
      }
    });
  });

  test('no screen or store shows a raw error', () {
    final raw = RegExp(
      r'''(?:[eE]rror\w*|Hint|detail|subtitle|message|reason|_loadError\.value)\s*[:=]\s*(?:e|err|error)\.toString\(\)'''
      r'''|['"][^'"\n]*:\s*\$\{?(?:e|err|error)\}?['"]''',
    );
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('debugPrint')) continue;
        if (raw.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
