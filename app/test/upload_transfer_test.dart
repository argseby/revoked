import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A file upload is bounded by idleness, not by a fixed budget. Sharing the
/// ordinary request timeout meant any file larger than the link could carry in
/// fifteen seconds failed, and reported itself as an unresponsive server.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Stream<List<int>> chunks(int count, int size) async* {
    for (var i = 0; i < count; i++) {
      yield List<int>.filled(size, 65);
    }
  }

  test('the body streams and progress tracks it to completion', () async {
    var opened = 0;
    final sentAt = <int>[];
    final client = ApiClient(
      httpClient: _DrainingClient(),
      secureStorage: const FlutterSecureStorage(),
    );

    final body = await client.postMultipart(
      '/api/x',
      fields: {'key': 'k'},
      fileField: 'file',
      filename: 'big.bin',
      openFile: () {
        opened++;
        return chunks(8, 1024);
      },
      length: 8 * 1024,
      onProgress: (sent, _) => sentAt.add(sent),
    );

    expect(body['ok'], isTrue);
    // Opened once, at send time — a handle, not bytes held since the pick.
    expect(opened, 1);
    expect(sentAt.first, 0);
    expect(sentAt.last, 8 * 1024);
    expect(sentAt, orderedEquals(List.of(sentAt)..sort()));
  });

  test('cancelling abandons the request', () async {
    final token = UploadCancelToken();
    final client = ApiClient(
      httpClient: _DrainingClient(),
      secureStorage: const FlutterSecureStorage(),
    );

    await expectLater(
      client.postMultipart(
        '/api/x',
        fields: const {},
        fileField: 'file',
        filename: 'big.bin',
        openFile: () => chunks(64, 1024),
        length: 64 * 1024,
        cancelToken: token,
        onProgress: (sent, _) {
          if (sent > 0) token.cancel();
        },
      ),
      throwsA(isA<UploadCancelledException>()),
    );
  });

  test(
    'an upload slower than the fixed request timeout still completes',
    () async {
      // Two gaps of just over half the fixed budget: their sum clears
      // ApiClient.timeout, while each stays well inside transferIdleTimeout.
      final client = ApiClient(
        httpClient: _DrainingClient(
          pauses: 2,
          pause: ApiClient.timeout ~/ 2 + const Duration(seconds: 1),
        ),
        secureStorage: const FlutterSecureStorage(),
      );

      final body = await client.postMultipart(
        '/api/x',
        fields: const {},
        fileField: 'file',
        filename: 'big.bin',
        openFile: () => chunks(4, 1024),
        length: 4 * 1024,
      );

      expect(body['ok'], isTrue);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// Drains the request body the way a socket would, stalling on the first
/// [pauses] chunks so a test can outlast a deadline without outlasting CI.
class _DrainingClient extends http.BaseClient {
  final int pauses;
  final Duration pause;

  _DrainingClient({this.pauses = 0, this.pause = Duration.zero});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var seen = 0;
    await for (final _ in request.finalize()) {
      if (seen++ < pauses) {
        await Future<void>.delayed(pause);
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'ok': true}))),
      200,
    );
  }
}
