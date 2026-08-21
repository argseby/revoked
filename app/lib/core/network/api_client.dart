import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/config/app_config.dart';

/// Exception thrown when an API call fails.
///
/// `code` mirrors the stable error codes emitted by the backend's
/// `appErrorResponse` helper (e.g. `link_password_required`,
/// `handshake_invalid`, `request_completed`). Code is empty when the
/// server returned a non-coded error (PocketBase's generic envelope).
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String code;
  final Map<String, dynamic>? data;

  ApiException(this.statusCode, this.message, {this.code = '', this.data});

  @override
  String toString() =>
      'ApiException($statusCode${code.isEmpty ? '' : ', $code'}): $message';
}

/// Represents an API response with both the decoded body and raw headers.
class ApiResponse {
  final dynamic body;
  final Map<String, String> headers;

  ApiResponse(this.body, this.headers);
}

/// Thrown into an upload's body stream to abandon it.
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

/// Handle for an in-flight upload.
///
/// Cancelling makes the body stream throw on its next chunk, which tears down
/// that one request. Closing the client would work too and would also drop
/// every other request sharing it.
class UploadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// A deadline that is pushed back on every chunk, so it fires only when a
/// transfer stops making progress rather than when it takes a long time.
class _IdleDeadline {
  final Completer<Never> _expired = Completer<Never>();
  Timer? _timer;

  _IdleDeadline(Duration limit) {
    poke(limit);
  }

  Future<Never> get expiry => _expired.future;

  void poke(Duration limit) {
    if (_expired.isCompleted) return;
    _timer?.cancel();
    _timer = Timer(limit, () {
      if (!_expired.isCompleted) {
        _expired.completeError(TimeoutException('transfer stalled'));
      }
    });
  }

  void dispose() => _timer?.cancel();
}

/// Low-level HTTP client for PocketBase API.
/// Handles auth token injection and response parsing.
class ApiClient {
  final http.Client _httpClient;
  final FlutterSecureStorage _secure;

  static const _tokenKey = 'pb_auth_token';
  static const _userKey = 'pb_user_data';
  static const _baseUrlKey = 'server_base_url';

  /// Prefix of the per-slug handshake tokens. They authorise a specific
  /// viewer against a specific link, so they are account state and must not
  /// outlive a session on a shared device.
  static const handshakeKeyPrefix = 'handshake_';

  /// Every request is bounded. A server that accepts the connection and then
  /// stalls would otherwise leave the caller waiting forever, which on the
  /// startup path meant a permanently blank screen.
  static const Duration timeout = Duration(seconds: 15);

  /// File transfers are bounded by idleness instead, because [timeout] measures
  /// the wrong thing for them: a large file legitimately takes longer than any
  /// fixed budget, while a connection that has stopped moving bytes is dead
  /// whatever its size. The deadline is pushed back on every chunk, so it fires
  /// only on a genuine stall.
  static const Duration transferIdleTimeout = Duration(seconds: 30);

  /// Applied once the body is fully sent: the server still has to hash and
  /// store it, and nothing crosses the wire in the meantime to reset the idle
  /// deadline.
  static const Duration transferResponseTimeout = Duration(minutes: 5);

  String? _authToken;
  Map<String, dynamic>? _userData;
  String _baseUrl = AppConfig.baseUrl;

  /// Called when the server rejects our credentials mid-session, so the app
  /// can drop to the login screen instead of showing error toasts forever.
  void Function()? onUnauthorized;

  ApiClient({http.Client? httpClient, FlutterSecureStorage? secureStorage})
    : _httpClient = httpClient ?? http.Client(),
      _secure = secureStorage ?? const FlutterSecureStorage();

  /// Current backend base URL. Persisted and user-configurable from the login
  /// screen's server settings; defaults to [AppConfig.baseUrl].
  String get baseUrl => _baseUrl;

  /// The compiled-in default base URL (for "reset to default").
  String get defaultBaseUrl => AppConfig.baseUrl;
  String? get authToken => _authToken;
  Map<String, dynamic>? get userData => _userData;
  bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;

  /// Load persisted auth state. The session token and the cached user record
  /// live in the keychain, not in preferences: a token is a bearer credential
  /// for the whole account, and preferences are world-readable on a rooted
  /// device and swept up by backups.
  /// Keychain reads are unbounded platform calls, and flutter_secure_storage
  /// is known to hang on some Android devices. A keychain that never answers
  /// must degrade to "signed out", not wedge the splash forever - the
  /// restore path sits before the first screen the user can interact with.
  Future<String?> _secureRead(String key) => _secure
      .read(key: key)
      .timeout(const Duration(seconds: 5), onTimeout: () => null);

  Future<void> loadAuthState() async {
    _authToken = await _secureRead(_tokenKey);
    final userJson = await _secureRead(_userKey);
    if (userJson != null) {
      _userData = jsonDecode(userJson) as Map<String, dynamic>;
    }

    // Anything left in preferences by a build that stored it there.
    final prefs = await SharedPreferences.getInstance();
    if (_authToken == null) {
      final legacy = prefs.getString(_tokenKey);
      final legacyUser = prefs.getString(_userKey);
      // Migration writes are best-effort: the in-memory state is already
      // set, so a hung keychain write costs a retry next launch, never the
      // session and never the splash.
      try {
        if (legacy != null) {
          _authToken = legacy;
          await _secure
              .write(key: _tokenKey, value: legacy)
              .timeout(const Duration(seconds: 5));
        }
        if (legacyUser != null) {
          _userData = jsonDecode(legacyUser) as Map<String, dynamic>;
          await _secure
              .write(key: _userKey, value: legacyUser)
              .timeout(const Duration(seconds: 5));
        }
      } on TimeoutException {
        // kept in prefs; migrated on a launch where the keychain answers
        return;
      }
    }
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// Persist auth state.
  Future<void> saveAuthState(String token, Map<String, dynamic> user) async {
    _authToken = token;
    _userData = user;
    await _secure.write(key: _tokenKey, value: token);
    await _secure.write(key: _userKey, value: jsonEncode(user));
  }

  /// Clear auth state, including the per-link handshake tokens. Those are
  /// tied to whoever was signed in: left behind, the next account on the
  /// device inherits access to the links the previous one unlocked.
  Future<void> clearAuthState() async {
    _authToken = null;
    _userData = null;
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _userKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(handshakeKeyPrefix)) await prefs.remove(key);
    }
  }

  /// Load the persisted backend base URL (falls back to the compiled default).
  /// Call once at startup before any request.
  Future<void> loadServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_baseUrlKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved.trim();
    }
  }

  /// Point the client at a new backend and persist it. Returns the normalized
  /// URL that was stored.
  Future<String> setBaseUrl(String raw) async {
    final normalized = normalizeServerUrl(raw);
    _baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized);
    return normalized;
  }

  /// Normalizes a user-entered server address into a base URL: prepends a
  /// scheme when missing (http:// for a bare host/IP) and strips a trailing
  /// slash. Empty input falls back to the compiled default.
  static String normalizeServerUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return AppConfig.baseUrl;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Map<String, String> _buildHeaders([Map<String, String>? extra]) => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    ...?extra,
  };

  /// GET request.
  /// This server's host[:port], the form links embed so a recipient on any
  /// instance knows where the link lives.
  String get originAuthority => Uri.tryParse(baseUrl)?.authority ?? '';

  /// Whether [origin] names the server this client is signed into.
  bool isOwnOrigin(String? origin) {
    final o = origin?.trim().toLowerCase() ?? '';
    return o.isEmpty || o == originAuthority.toLowerCase();
  }

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  /// Resolves a link-embedded origin (host[:port], no scheme) to a base URL.
  /// https is forced for anything that is not loopback: the origin arrived
  /// inside an unauthenticated link, and TLS is the only thing proving the
  /// fetch reaches the host it names. Returns null for a malformed origin.
  static String? publicBaseFor(String origin) {
    final o = origin.trim();
    if (o.isEmpty || o.contains('/') || o.contains('@')) return null;
    final u = Uri.tryParse('https://$o');
    if (u == null || u.host.isEmpty) return null;
    final scheme = _isLoopbackHost(u.host) ? 'http' : 'https';
    return '$scheme://${u.authority}';
  }

  /// GET that a link-embedded [origin] routes to its own server.
  ///
  /// The foreign path never attaches the session token — the token is a
  /// credential for *this* server, and a link is exactly the vector an
  /// attacker would use to make the app hand it to theirs. A foreign 401 also
  /// must not end the local session.
  Future<dynamic> getFromOrigin(
    String? origin,
    String path, {
    Map<String, String>? queryParams,
  }) async {
    if (isOwnOrigin(origin)) return get(path, queryParams: queryParams);
    final base = publicBaseFor(origin!);
    if (base == null) {
      throw ApiException(
        0,
        'The link names an invalid server.',
        code: 'invalid_origin',
      );
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: queryParams);
    final response = await _send(
      _httpClient.get(uri, headers: {'Content-Type': 'application/json'}),
    );
    return _handleResponse(response, foreign: true);
  }

  /// POST counterpart of [getFromOrigin]; same credential rules.
  Future<ApiResponse> postFromOrigin(
    String? origin,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (isOwnOrigin(origin)) return postWithHeaders(path, body: body);
    final base = publicBaseFor(origin!);
    if (base == null) {
      throw ApiException(
        0,
        'The link names an invalid server.',
        code: 'invalid_origin',
      );
    }
    final response = await _send(
      _httpClient.post(
        Uri.parse('$base$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ),
    );
    return ApiResponse(
      _handleResponse(response, foreign: true),
      response.headers,
    );
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: queryParams);
    final response = await _send(
      _httpClient.get(uri, headers: _buildHeaders()),
    );
    return _handleResponse(response);
  }

  /// GET request returning both body and headers.
  Future<ApiResponse> getWithHeaders(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: queryParams);
    final response = await _send(
      _httpClient.get(uri, headers: _buildHeaders(headers)),
    );
    final decodedBody = _handleResponse(response);
    return ApiResponse(decodedBody, response.headers);
  }

  /// POST request.
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final response = await postWithHeaders(path, body: body);
    return response.body;
  }

  /// POST request returning both body and headers.
  Future<ApiResponse> postWithHeaders(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _send(
      _httpClient.post(
        uri,
        headers: _buildHeaders(headers),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    final decodedBody = _handleResponse(response);
    return ApiResponse(decodedBody, response.headers);
  }

  /// Multipart write — the one non-JSON request shape in the app, used for
  /// record file uploads. Fields travel as form parts, the file as one part.
  ///
  /// The file arrives as [openFile], a factory for its byte stream, so nothing
  /// larger than a chunk is ever resident. It is a factory and not a stream
  /// because a stream is consumed once and a retried save needs a fresh one.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filename,
    required Stream<List<int>> Function() openFile,
    required int length,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) => _sendMultipart(
    'POST',
    path,
    fields: fields,
    fileField: fileField,
    filename: filename,
    openFile: openFile,
    length: length,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  /// PATCH counterpart of [postMultipart], for replacing a record's file.
  Future<dynamic> patchMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filename,
    required Stream<List<int>> Function() openFile,
    required int length,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) => _sendMultipart(
    'PATCH',
    path,
    fields: fields,
    fileField: fileField,
    filename: filename,
    openFile: openFile,
    length: length,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  Future<dynamic> _sendMultipart(
    String method,
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filename,
    required Stream<List<int>> Function() openFile,
    required int length,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    final request = http.MultipartRequest(method, Uri.parse('$baseUrl$path'));
    // The boundary header comes from the request itself; only auth carries over.
    final headers = _buildHeaders()..remove('Content-Type');
    request.headers.addAll(headers);
    request.fields.addAll(fields);

    final deadline = _IdleDeadline(transferIdleTimeout);
    request.files.add(
      http.MultipartFile(
        fileField,
        _meter(openFile(), length, deadline, onProgress, cancelToken),
        length,
        filename: filename,
      ),
    );

    try {
      // Sent through the shared client rather than BaseRequest.send(), which
      // spins up a private one — that bypassed both the connection pool and
      // any client injected for a test.
      final response = await Future.any<http.Response>([
        _httpClient.send(request).then(http.Response.fromStream),
        deadline.expiry,
      ]);
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        408,
        'The upload stopped making progress and was abandoned.',
        code: 'request_timeout',
      );
    } finally {
      deadline.dispose();
    }
  }

  /// Counts bytes as the socket drains them. The same pull that reports
  /// progress is also the proof the connection is alive, so one pass over the
  /// stream serves both; once the body is out the deadline switches to waiting
  /// for the server's reply.
  Stream<List<int>> _meter(
    Stream<List<int>> source,
    int total,
    _IdleDeadline deadline,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  ) async* {
    var sent = 0;
    onProgress?.call(0, total);
    await for (final chunk in source) {
      if (cancelToken?.isCancelled ?? false) {
        throw const UploadCancelledException();
      }
      sent += chunk.length;
      deadline.poke(transferIdleTimeout);
      onProgress?.call(sent, total);
      yield chunk;
    }
    deadline.poke(transferResponseTimeout);
  }

  /// GET raw bytes from a link's origin. Same credential rule as
  /// [getFromOrigin]: no session token ever — the query carries the only
  /// capability (a download or file token).
  Future<Uint8List> getPublicBytes(
    String? origin,
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final foreign = !isOwnOrigin(origin);
    final base = foreign ? publicBaseFor(origin!) : baseUrl;
    if (base == null) {
      throw ApiException(
        0,
        'The link names an invalid server.',
        code: 'invalid_origin',
      );
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: queryParams);
    final response = await _receive(http.Request('GET', uri));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    _handleResponse(response, foreign: foreign);
    throw ApiException(response.statusCode, 'Download failed.');
  }

  /// Reads a response under the same idle rule uploads use, so a large file is
  /// not mistaken for a stalled server. The body is still accumulated in
  /// memory — the save path takes bytes — so this bounds the wait, not the
  /// footprint.
  Future<http.Response> _receive(http.BaseRequest request) async {
    final deadline = _IdleDeadline(transferIdleTimeout);
    try {
      final streamed = await Future.any<http.StreamedResponse>([
        _httpClient.send(request),
        deadline.expiry,
      ]);
      final body = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        deadline.poke(transferIdleTimeout);
        body.add(chunk);
      }
      return http.Response.bytes(
        body.takeBytes(),
        streamed.statusCode,
        headers: streamed.headers,
        request: streamed.request,
        reasonPhrase: streamed.reasonPhrase,
      );
    } on TimeoutException {
      throw ApiException(
        408,
        'The download stopped making progress and was abandoned.',
        code: 'request_timeout',
      );
    } finally {
      deadline.dispose();
    }
  }

  /// PATCH request.
  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _send(
      _httpClient.patch(
        uri,
        headers: _buildHeaders(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _handleResponse(response);
  }

  /// DELETE request.
  Future<dynamic> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _send(
      _httpClient.delete(uri, headers: _buildHeaders()),
    );
    if (response.statusCode == 204) return null;
    return _handleResponse(response);
  }

  /// Bounds a request and turns a timeout into an ApiException, so callers
  /// see one failure type rather than a TimeoutException leaking through.
  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        408,
        'The server did not respond in time.',
        code: 'request_timeout',
      );
    }
  }

  dynamic _handleResponse(http.Response response, {bool foreign = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    String message = 'Request failed';
    String code = '';
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
        // Custom app-error envelope: {"code": "...", "message": "...", "status": int}
        if (decoded['code'] is String &&
            (decoded['code'] as String).isNotEmpty) {
          code = decoded['code'] as String;
        }
        if (decoded['message'] is String) {
          message = decoded['message'] as String;
        }
        // Hooks carry their code one level down, as
        // {"data": {"<field>": {"code": "...", "message": "..."}}} — the shape
        // PocketBase gives a validation error. Without this the typed codes
        // the backend goes to the trouble of emitting never reach the app.
        if (code.isEmpty && decoded['data'] is Map<String, dynamic>) {
          for (final entry
              in (decoded['data'] as Map<String, dynamic>).values) {
            if (entry is Map<String, dynamic> &&
                entry['code'] is String &&
                (entry['code'] as String).isNotEmpty) {
              code = entry['code'] as String;
              if (entry['message'] is String) {
                message = entry['message'] as String;
              }
              break;
            }
          }
        }
      }
    } catch (_) {
      // body wasn't JSON; keep generic message
    }

    // A rejected session is not a per-screen error: without this every screen
    // shows its own failure toast forever while the session stays dead.
    if (response.statusCode == 401 && isAuthenticated && !foreign) {
      onUnauthorized?.call();
    }

    throw ApiException(response.statusCode, message, code: code, data: data);
  }

  void dispose() {
    _httpClient.close();
  }
}
