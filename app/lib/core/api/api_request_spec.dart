import 'dart:convert';

/// A description of a single HTTP API call the app makes, surfaced in the UI so
/// a developer can reproduce any action against the API directly.
///
/// The app is API-first: every mutating flow builds one of these (the same spec
/// that drives the real request) and shows it via an [ApiPreview], so what you
/// see is exactly what the app sends.
class ApiRequestSpec {
  final String method;
  final String path;
  final Map<String, dynamic>? body;

  /// How an external caller authenticates. API keys are the API-first path
  /// The app itself sends its session token as `Authorization: Bearer`; an
  /// API key is sent as `X-API-Key: <key>` instead.
  final String authHeader;

  const ApiRequestSpec({
    required this.method,
    required this.path,
    this.body,
    this.authHeader = 'Authorization: Bearer <YOUR_TOKEN>',
  });

  String fullUrl(String baseUrl) => '$baseUrl$path';

  String prettyBody() =>
      const JsonEncoder.withIndent('  ').convert(body ?? const {});

  /// A readable request block: method + URL, headers, then the JSON body.
  String requestText(String baseUrl) {
    final b = StringBuffer('$method ${fullUrl(baseUrl)}\n');
    b.write('$authHeader\n');
    if (body != null) {
      b.write('Content-Type: application/json\n\n');
      b.write(prettyBody());
    }
    return b.toString();
  }

  /// A copy-pasteable cURL command (compact JSON body).
  String toCurl(String baseUrl) {
    final parts = <String>["curl -X $method '${fullUrl(baseUrl)}'"];
    parts.add("  -H '$authHeader'");
    if (body != null) {
      parts.add("  -H 'Content-Type: application/json'");
      parts.add("  -d '${jsonEncode(body)}'");
    }
    return parts.join(' \\\n');
  }
}
