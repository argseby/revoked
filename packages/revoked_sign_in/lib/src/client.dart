import 'dart:convert';

import 'package:http/http.dart' as http;

/// A sign-in the service has prepared: what the panel shows, and the key only
/// this client holds to collect the result.
class RevokedSignInStart {
  const RevokedSignInStart({required this.appLink, required this.checkCode, required this.wait});

  /// The `revoked://signin?…` request, shown as a QR code and opened on this
  /// device.
  final Uri appLink;

  /// The code the app shows next to the request, e.g. `0D2-99B`.
  final String checkCode;

  /// The key for the `wait` route. Never shown, never put in the link.
  final String wait;
}

/// What the `wait` route said.
sealed class RevokedWaitAnswer {
  const RevokedWaitAnswer();
}

/// Not decided yet, or a passing problem: ask again.
class RevokedWaitPending extends RevokedWaitAnswer {
  const RevokedWaitPending();
}

/// Approved. [body] is the route's whole answer, so a service can hand an
/// app its session in it.
class RevokedWaitSignedIn extends RevokedWaitAnswer {
  const RevokedWaitSignedIn(this.body);
  final Map<String, dynamic> body;
}

/// Finished without signing in, e.g. `access_denied` when declined.
class RevokedWaitRefused extends RevokedWaitAnswer {
  const RevokedWaitRefused(this.error);
  final String error;
}

/// Expired or already collected.
class RevokedWaitExpired extends RevokedWaitAnswer {
  const RevokedWaitExpired();
}

class RevokedSignInException implements Exception {
  const RevokedSignInException(this.message);
  final String message;
  @override
  String toString() => 'RevokedSignInException: $message';
}

/// Talks to the service's own `start` and `wait` routes, as described in
/// docs/api/sign-in.md.
class RevokedSignInClient {
  RevokedSignInClient({required this.start, required this.wait, http.Client? httpClient, this.asApp = false})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  final Uri start;
  final Uri wait;

  /// Sends `"client": "app"` with each `wait`, so a service that also serves
  /// native apps knows to answer with a session in the body rather than a
  /// cookie.
  final bool asApp;

  final http.Client _http;
  final bool _ownsHttp;

  static const _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  Future<RevokedSignInStart> begin() async {
    final res = await _http.post(start, headers: _headers, body: '{}');
    if (res.statusCode >= 400) throw RevokedSignInException('start answered ${res.statusCode}');
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      throw const RevokedSignInException('start answered with something other than JSON');
    }
    if (json is! Map<String, dynamic>) throw const RevokedSignInException('start answered badly');
    final link = json['app_link'];
    final waitKey = json['wait'];
    final code = json['check_code'];
    if (link is! String || !link.startsWith('revoked://signin?') || waitKey is! String || waitKey.isEmpty) {
      throw const RevokedSignInException('start answered badly');
    }
    return RevokedSignInStart(appLink: Uri.parse(link), checkCode: code is String ? code : '', wait: waitKey);
  }

  /// Asks once whether the sign-in is finished. Anything that is not a clear
  /// answer, including a lost connection, counts as pending.
  Future<RevokedWaitAnswer> ask(String waitKey) async {
    final http.Response res;
    try {
      res = await _http.post(
        wait,
        headers: _headers,
        body: jsonEncode({'wait': waitKey, if (asApp) 'client': 'app'}),
      );
    } on Exception {
      return const RevokedWaitPending();
    }
    if (res.statusCode == 401 || res.statusCode == 404 || res.statusCode == 410) return const RevokedWaitExpired();
    if (res.statusCode != 200) return const RevokedWaitPending();
    try {
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic> || json['done'] != true) return const RevokedWaitPending();
      final error = json['error'];
      if (error is String && error.isNotEmpty) return RevokedWaitRefused(error);
      return RevokedWaitSignedIn(json);
    } on FormatException {
      return const RevokedWaitPending();
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
