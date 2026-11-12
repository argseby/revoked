import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_sign_in/revoked_sign_in.dart';

final _start = Uri.parse('https://game.example/start');
final _wait = Uri.parse('https://game.example/wait');

RevokedSignInClient _client(MockClientHandler handler, {bool asApp = false}) =>
    RevokedSignInClient(start: _start, wait: _wait, httpClient: MockClient(handler), asApp: asApp);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('begin', () {
    test('reads the link, the check code and the wait key', () async {
      late http.Request sent;
      final client = _client((req) async {
        sent = req;
        return _json({'app_link': 'revoked://signin?state=a', 'check_code': '0D2-99B', 'wait': 'w1'});
      });
      final start = await client.begin();
      expect(sent.method, 'POST');
      expect(sent.url, _start);
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(start.appLink.toString(), 'revoked://signin?state=a');
      expect(start.checkCode, '0D2-99B');
      expect(start.wait, 'w1');
    });

    test('refuses a link that is not a Revoked sign-in', () async {
      final client = _client((_) async => _json({'app_link': 'https://evil.example', 'wait': 'w'}));
      expect(client.begin(), throwsA(isA<RevokedSignInException>()));
    });

    test('refuses an answer without a wait key', () async {
      final client = _client((_) async => _json({'app_link': 'revoked://signin?x'}));
      expect(client.begin(), throwsA(isA<RevokedSignInException>()));
    });

    test('refuses an error status and a body that is not JSON', () async {
      expect(_client((_) async => http.Response('', 500)).begin(), throwsA(isA<RevokedSignInException>()));
      expect(_client((_) async => http.Response('<html>', 200)).begin(), throwsA(isA<RevokedSignInException>()));
    });
  });

  group('ask', () {
    test('sends the wait key, and says it is an app only when asked to', () async {
      final bodies = <Map<String, dynamic>>[];
      Future<http.Response> record(http.Request req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({'done': false});
      }

      await _client(record).ask('w1');
      await _client(record, asApp: true).ask('w2');
      expect(bodies, [
        {'wait': 'w1'},
        {'wait': 'w2', 'client': 'app'},
      ]);
    });

    test('not done yet is pending', () async {
      expect(await _client((_) async => _json({'done': false})).ask('w'), isA<RevokedWaitPending>());
    });

    test('done hands over the whole answer', () async {
      final answer = await _client((_) async => _json({'done': true, 'session': 's1'})).ask('w');
      expect(answer, isA<RevokedWaitSignedIn>());
      expect((answer as RevokedWaitSignedIn).body, {'done': true, 'session': 's1'});
    });

    test('done with an error is refused', () async {
      final answer = await _client((_) async => _json({'done': true, 'error': 'access_denied'})).ask('w');
      expect((answer as RevokedWaitRefused).error, 'access_denied');
    });

    for (final status in [401, 404, 410]) {
      test('$status is expired', () async {
        expect(await _client((_) async => http.Response('', status)).ask('w'), isA<RevokedWaitExpired>());
      });
    }

    test('a server error, a bad body or a lost connection is pending', () async {
      expect(await _client((_) async => http.Response('', 502)).ask('w'), isA<RevokedWaitPending>());
      expect(await _client((_) async => http.Response('nope', 200)).ask('w'), isA<RevokedWaitPending>());
      expect(await _client((_) async => throw http.ClientException('offline')).ask('w'), isA<RevokedWaitPending>());
    });
  });
}
