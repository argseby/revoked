import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';

/// The server names the reason a registration was refused; the app has to be
/// able to read it. Hooks carry their code inside `data`, not at the top level,
/// so a parser that only looked at the top level silently lost every typed
/// code the backend emits.
void main() {
  Future<ApiException> capture(String body, int status) async {
    final client = ApiClient(httpClient: _Stub(body, status));
    try {
      await client.post('/api/collections/users/records');
      fail('expected the request to throw');
    } on ApiException catch (e) {
      return e;
    }
  }

  test('a refused signup surfaces its code and a usable message', () async {
    final e = await capture(
      jsonEncode({
        'status': 403,
        'message': 'Failed to create record.',
        'data': {
          'signup': {
            'code': 'signups_disabled',
            'message': 'This server does not accept new registrations.',
          },
        },
      }),
      403,
    );

    expect(e.code, AppErrorCode.signupsDisabled);

    final mapped = AppErrorMessage.fromException(e);
    expect(mapped.title, 'This server is invite-only');
    expect(mapped.isTerminal, isTrue);
  });

  test('a top-level envelope still wins', () async {
    final e = await capture(
      jsonEncode({'code': 'link_revoked', 'message': 'gone', 'status': 404}),
      404,
    );
    expect(e.code, AppErrorCode.linkRevoked);
  });
}

class _Stub extends http.BaseClient {
  final String body;
  final int status;
  _Stub(this.body, this.status);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), status);
}
