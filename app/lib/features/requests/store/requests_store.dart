import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/request_template.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'requests_store.g.dart';

/// Owner-side store for `requests` and the public submission endpoints.
///
/// Statics live here (not on `_RequestsStore`) because Dart does not expose a
/// superclass's statics through the subclass name.
class RequestsStore extends _RequestsStore with _$RequestsStore {
  RequestsStore(super.api);

  /// Parses the template payload from the probe into typed items. Sections
  /// are flattened so the responder sees one flat list of fields to fill.
  static List<RequestTemplateItem> parseTemplateFromProbe(
    Map<String, dynamic> probe,
  ) {
    final out = <RequestTemplateItem>[];
    final tpl = probe['template'];
    if (tpl is! Map) return out;
    for (final raw in (tpl['records'] as List? ?? const [])) {
      if (raw is Map<String, dynamic>) {
        out.add(RequestTemplateItem.fromJson(raw));
      }
    }
    for (final raw in (tpl['sections'] as List? ?? const [])) {
      if (raw is Map<String, dynamic>) {
        final section = RequestTemplateItem.fromJson(raw);
        for (final child in section.records) {
          out.add(child);
        }
      }
    }
    return out;
  }

  /// The exact API request [create] issues — single source of truth shared
  /// with the in-app API preview.
  static ApiRequestSpec createRequestSpec({
    required String slug,
    required String label,
    required String identityId,
    required String user,
    required String workspace,
    String status = 'active',
    String? templateId,
    String? password,
    DateTime? expiresAt,
    int? maxResponses,
    String? identifier,
    String? callbackUrl,
    bool requireHandshake = false,
    String identityScope = 'any',
    bool allowExtraFields = false,
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: '/api/collections/${AppConfig.requestsCollection}/records',
      body: {
        'slug': slug,
        'label': label,
        'status': status,
        'identity': identityId,
        if (templateId != null && templateId.isNotEmpty) 'template': templateId,
        if (password != null && password.isNotEmpty) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (maxResponses != null && maxResponses > 0)
          'maxResponses': maxResponses,
        if (identifier != null && identifier.isNotEmpty)
          'identifier': identifier,
        if (callbackUrl != null && callbackUrl.isNotEmpty)
          'callbackUrl': callbackUrl,
        'requireHandshake': requireHandshake,
        'identityScope': identityScope,
        'allowExtraFields': allowExtraFields,
        'user': user,
        'workspace': workspace,
      },
    );
  }

  /// The exact API request [update] issues.
  static ApiRequestSpec updateRequestSpec(
    String id,
    Map<String, dynamic> body,
  ) {
    return ApiRequestSpec(
      method: 'PATCH',
      path: '/api/collections/${AppConfig.requestsCollection}/records/$id',
      body: body,
    );
  }

  /// The exact API request [delete] issues.
  static ApiRequestSpec deleteRequestSpec(String id) {
    return ApiRequestSpec(
      method: 'DELETE',
      path: '/api/collections/${AppConfig.requestsCollection}/records/$id',
    );
  }
}

abstract class _RequestsStore with Store {
  final ApiClient _api;

  _RequestsStore(this._api);

  final ObservableList<DataRequest> requests = ObservableList<DataRequest>();

  /// Responses grouped by request id. Filled on demand by [loadResponses].
  final ObservableMap<String, List<Map<String, dynamic>>> responsesByRequest =
      ObservableMap<String, List<Map<String, dynamic>>>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  String get _requestsPath =>
      '/api/collections/${AppConfig.requestsCollection}/records';

  @action
  Future<void> loadRequests() async {
    isLoading = true;
    errorMessage = null;
    try {
      final reqs = await getAll();
      requests
        ..clear()
        ..addAll(reqs);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<List<Map<String, dynamic>>> loadResponses(String requestId) async {
    try {
      final result = await getResponses(requestId);
      responsesByRequest[requestId] = result;
      return result;
    } catch (e) {
      errorMessage = e.toString();
      return [];
    }
  }

  /// Loads responses for every request — used by the aggregated data screen.
  Future<void> loadAllResponses() async {
    for (final r in requests) {
      await loadResponses(r.id);
    }
  }

  @action
  Future<bool> createRequest({
    required String slug,
    required String label,
    required String identityId,
    required String user,
    required String workspace,
    String? templateId,
    String? password,
    DateTime? expiresAt,
    int? maxResponses,
    String? identifier,
    String? callbackUrl,
    bool requireHandshake = false,
    String identityScope = 'any',
    bool allowExtraFields = false,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final req = await create(
        slug: slug,
        label: label,
        identityId: identityId,
        user: user,
        workspace: workspace,
        templateId: templateId,
        password: password,
        expiresAt: expiresAt,
        maxResponses: maxResponses,
        identifier: identifier,
        callbackUrl: callbackUrl,
        requireHandshake: requireHandshake,
        identityScope: identityScope,
        allowExtraFields: allowExtraFields,
      );
      requests.insert(0, req);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> updateRequest(String id, Map<String, dynamic> body) async {
    try {
      final req = await update(id, body);
      final idx = requests.indexWhere((r) => r.id == id);
      if (idx != -1) {
        requests[idx] = req;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  @action
  Future<bool> deleteRequest(String id) async {
    try {
      await delete(id);
      requests.removeWhere((r) => r.id == id);
      responsesByRequest.remove(id);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  @action
  void clearError() {
    errorMessage = null;
  }

  /// Fetch all requests in the current user's active workspace.
  Future<List<DataRequest>> getAll({int page = 1, int perPage = 50}) async {
    final data = await _api.get(
      _requestsPath,
      queryParams: {
        'page': page.toString(),
        'perPage': perPage.toString(),
        'sort': '-created',
      },
    );
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items
        .map((e) => DataRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch responses for a request the caller owns, with every living grant
  /// resolved to the responder's CURRENT vault value. Resolution must happen
  /// on the server because the referenced records belong to the responder.
  Future<List<Map<String, dynamic>>> getResponses(String requestId) async {
    final data = await _api.get('/api/requests/$requestId/links');
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items.cast<Map<String, dynamic>>().toList();
  }

  /// The caller's own response link for [requestId], if they've already
  /// answered it. The links list rule is scoped to the current user/workspace,
  /// so no owner filter is needed.
  Future<Map<String, dynamic>?> getMyLinkForRequest(String requestId) async {
    final data = await _api.get(
      '/api/collections/${AppConfig.linksCollection}/records',
      queryParams: {
        'filter': 'request = "$requestId"',
        'perPage': '1',
        'sort': '-created',
      },
    );
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items.isEmpty ? null : items.first as Map<String, dynamic>;
  }

  /// Revoke the caller's own response link (status → revoked).
  Future<void> revokeMyLink(String linkId) async {
    await _api.patch(
      '/api/collections/${AppConfig.linksCollection}/records/$linkId',
      body: {'status': 'revoked'},
    );
  }

  /// Public probe — reveals what gates apply without exposing data.
  Future<Map<String, dynamic>> getPublicRequestProbe(String slug) async {
    final data = await _api.get('/api/public/requests/$slug');
    return data as Map<String, dynamic>;
  }

  /// Public submission. The server sets `X-Handshake-Token` on first
  /// handshake; callers must persist + replay it on subsequent requests
  /// from the same identity.
  Future<ApiResponse> submitPublicRequest(
    String slug, {
    String? password,
    String? identifier,
    String? handshakeToken,
    String? identityId,
    String? challengeNonce,
    String? challengeSignature,
    String? guestCertificate,
    String? senderName,
    Map<String, dynamic>? data,
    Map<String, String>? mappings,
  }) async {
    return _api.postWithHeaders(
      '/api/public/requests/$slug',
      body: {
        'password': ?password,
        'identifier': ?identifier,
        'handshakeToken': ?handshakeToken,
        'identityId': ?identityId,
        'challengeNonce': ?challengeNonce,
        'challengeSignature': ?challengeSignature,
        'guestCertificate': ?guestCertificate,
        'senderName': ?senderName,
        'data': ?data,
        'mappings': ?mappings,
      },
    );
  }

  /// Create a new request.
  Future<DataRequest> create({
    required String slug,
    required String label,
    required String identityId,
    required String user,
    required String workspace,
    String status = 'active',
    String? templateId,
    String? password,
    DateTime? expiresAt,
    int? maxResponses,
    String? identifier,
    String? callbackUrl,
    bool requireHandshake = false,
    String identityScope = 'any',
    bool allowExtraFields = false,
  }) async {
    final spec = RequestsStore.createRequestSpec(
      slug: slug,
      label: label,
      identityId: identityId,
      user: user,
      workspace: workspace,
      status: status,
      templateId: templateId,
      password: password,
      expiresAt: expiresAt,
      maxResponses: maxResponses,
      identifier: identifier,
      callbackUrl: callbackUrl,
      requireHandshake: requireHandshake,
      identityScope: identityScope,
      allowExtraFields: allowExtraFields,
    );
    final data = await _api.post(spec.path, body: spec.body);
    return DataRequest.fromJson(data as Map<String, dynamic>);
  }

  /// Update an existing request.
  Future<DataRequest> update(String id, Map<String, dynamic> body) async {
    final spec = RequestsStore.updateRequestSpec(id, body);
    final data = await _api.patch(spec.path, body: spec.body);
    return DataRequest.fromJson(data as Map<String, dynamic>);
  }

  /// Delete a request.
  Future<void> delete(String id) async {
    await _api.delete(RequestsStore.deleteRequestSpec(id).path);
  }

  /// Check if a slug is already taken (lets the caller pick another).
  Future<bool> isSlugTaken(String slug) async {
    try {
      final data = await _api.get(
        _requestsPath,
        queryParams: {'filter': 'slug = "$slug"', 'page': '1', 'perPage': '1'},
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      return items.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String> generateAlternativeSlug(String baseSlug) async {
    int counter = 1;
    while (true) {
      final candidate = '${baseSlug}_$counter';
      final taken = await isSlugTaken(candidate);
      if (!taken) return candidate;
      counter++;
    }
  }
}
