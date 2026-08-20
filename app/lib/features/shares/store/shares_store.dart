import 'dart:typed_data';

import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'shares_store.g.dart';

// ignore: library_private_types_in_public_api
class SharesStore = _SharesStore with _$SharesStore;

/// Share links plus the CRUD they ride on. Since migration 000018 the `links`
/// collection rules are owner-only — public viewers must go through
/// [getPublicLinkProbe] / [submitPublicLink], never the collection endpoints.
abstract class _SharesStore with Store {
  final ApiClient _api;

  _SharesStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.linksCollection}/records';

  final ObservableTextController draftLabel = ObservableTextController();
  final ObservableTextController draftSlug = ObservableTextController();
  final ObservableTextController draftPassword = ObservableTextController();
  final ObservableTextController draftMaxViews = ObservableTextController();

  @observable
  DateTime? draftExpiresAt;

  @observable
  String? draftIdentityId;

  @observable
  bool draftRequireHandshake = false;

  @observable
  String? draftSlugWarning;

  @observable
  bool isSubmittingShare = false;

  @action
  void setDraftExpiry(DateTime? value) => draftExpiresAt = value;

  @action
  void setDraftIdentity(String? value) => draftIdentityId = value;

  @action
  void setDraftHandshake(bool value) => draftRequireHandshake = value;

  @action
  void setDraftSlugWarning(String? value) => draftSlugWarning = value;

  @action
  void setSubmittingShare(bool value) => isSubmittingShare = value;

  @action
  void startShareDraft({
    String label = '',
    String slug = '',
    String maxViews = '',
    DateTime? expiresAt,
    String? identityId,
    bool requireHandshake = false,
  }) {
    draftLabel.text = label;
    draftSlug.text = slug;
    draftPassword.clear();
    draftMaxViews.text = maxViews;
    draftExpiresAt = expiresAt;
    draftIdentityId = identityId;
    draftRequireHandshake = requireHandshake;
    draftSlugWarning = null;
    isSubmittingShare = false;
  }

  // The unauthenticated view of one /s/<slug> link.

  final ObservableTextController sharePassword = ObservableTextController();

  @observable
  bool isLoadingShare = true;

  @observable
  bool isUnlockingShare = false;

  /// Probe result for the slug.
  @observable
  Map<String, dynamic>? shareProbe;

  /// Origin the open link named; null when it lives on the signed-in server.
  String? shareOrigin;

  /// The DNS walk over the sharer's signing identity. Null while unchecked;
  /// an unsigned share never produces one.
  @observable
  TrustVerdict? shareTrustVerdict;

  @observable
  bool isVerifyingShareTrust = false;

  @action
  void startShareTrust() {
    isVerifyingShareTrust = true;
    shareTrustVerdict = null;
  }

  /// A stored verdict shown while the fresh check runs; isVerifying stays
  /// true so the UI can say it is still being confirmed.
  @action
  void seedShareTrust(TrustVerdict verdict) => shareTrustVerdict = verdict;

  @action
  void finishShareTrust(TrustVerdict? verdict) {
    shareTrustVerdict = verdict;
    isVerifyingShareTrust = false;
  }

  /// Successful submission result with records/sections.
  @observable
  Map<String, dynamic>? shareData;

  /// Terminal failure — wrong slug, revoked, expired, max views hit.
  @observable
  AppErrorMessage? shareTerminalError;

  @observable
  String? sharePasswordHint;

  @observable
  String? shareIdentityId;

  /// Records whose hidden value the viewer chose to reveal, by key.
  final ObservableSet<String> revealedShareValues = ObservableSet<String>();

  /// Shared file records currently being fetched, keyed by record id, so each
  /// row shows its own busy state.
  final ObservableSet<String> downloadingShareRecordIds =
      ObservableSet<String>();

  /// Fetches a shared file's bytes with the single-use token the resolve
  /// minted. Same credential rule as every public call: never a session token.
  @action
  Future<Uint8List?> downloadSharedFile({
    required String? origin,
    required String slug,
    required String recordId,
    required String token,
  }) async {
    downloadingShareRecordIds.add(recordId);
    try {
      return await _api.getPublicBytes(
        origin,
        '/api/public/links/$slug/files/$recordId',
        queryParams: {'dl': token},
      );
    } catch (e) {
      errorMessage = e.toString();
      return null;
    } finally {
      downloadingShareRecordIds.remove(recordId);
    }
  }

  @action
  void toggleShareValue(String key) {
    if (!revealedShareValues.remove(key)) revealedShareValues.add(key);
  }

  @action
  void setShareIdentity(String? value) => shareIdentityId = value;

  @action
  void resetShareView() {
    sharePassword.clear();
    isLoadingShare = true;
    isUnlockingShare = false;
    shareProbe = null;
    shareOrigin = null;
    shareTrustVerdict = null;
    isVerifyingShareTrust = false;
    shareData = null;
    shareTerminalError = null;
    sharePasswordHint = null;
    shareIdentityId = null;
    revealedShareValues.clear();
  }

  @observable
  ObservableList<Link> shares = ObservableList<Link>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  /// Active links that currently expose [recordId] directly. Powers the vault
  /// "who has access" surface.
  List<Link> linksForRecord(String recordId) => shares
      .where((l) => l.status == 'active' && l.records.contains(recordId))
      .toList();

  /// Active links that currently expose [sectionId].
  List<Link> linksForSection(String sectionId) => shares
      .where((l) => l.status == 'active' && l.sections.contains(sectionId))
      .toList();

  @action
  Future<void> loadShares() async {
    isLoading = true;
    errorMessage = null;
    try {
      final result = await getAll();
      shares = ObservableList.of(result);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> createShare({
    required String slug,
    required String label,
    required String user,
    required String workspace,
    required List<String> sections,
    required List<String> records,
    String status = 'active',
    String? identityId,
    String? password,
    DateTime? expiresAt,
    int? maxViews,
    bool requireHandshake = false,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final link = await create(
        slug: slug,
        label: label,
        user: user,
        workspace: workspace,
        sections: sections,
        records: records,
        status: status,
        identityId: identityId,
        password: password,
        expiresAt: expiresAt,
        maxViews: maxViews,
        requireHandshake: requireHandshake,
      );
      shares.insert(0, link);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> updateShare(String id, Map<String, dynamic> updates) async {
    try {
      final updated = await update(id, updates);
      final idx = shares.indexWhere((s) => s.id == id);
      if (idx != -1) {
        shares[idx] = updated;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  @action
  Future<bool> deleteShare(String id) async {
    try {
      await delete(id);
      shares.removeWhere((s) => s.id == id);
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

  Future<List<Link>> getAll({int page = 1, int perPage = 50}) async {
    final data = await _api.get(
      _basePath,
      queryParams: {
        'page': page.toString(),
        'perPage': perPage.toString(),
        'sort': '-created',
      },
    );
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items.map((e) => Link.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Owner-side single fetch (sees viewCount, expiresAt, etc.).
  Future<Link> getById(String id) async {
    final data = await _api.get('$_basePath/$id');
    return Link.fromJson(data as Map<String, dynamic>);
  }

  /// Public probe — never returns the shared records, only the gates that
  /// must be satisfied (password? handshake? identity?).
  Future<Map<String, dynamic>> getPublicLinkProbe(
    String slug, {
    String? origin,
  }) async {
    shareOrigin = origin;
    final data = await _api.getFromOrigin(origin, '/api/public/links/$slug');
    return data as Map<String, dynamic>;
  }

  /// Public submission — supplies password / handshake / identity, returns the
  /// sanitized payload with headers so the caller can persist the
  /// `X-Handshake-Token` the server sets on a first handshake.
  Future<ApiResponse> submitPublicLink(
    String slug, {
    String? password,
    String? handshakeToken,
    String? identityId,
    String? challengeNonce,
    String? challengeSignature,
  }) async {
    return _api.postFromOrigin(
      shareOrigin,
      '/api/public/links/$slug',
      body: {
        'password': ?password,
        'handshakeToken': ?handshakeToken,
        'identityId': ?identityId,
        'challengeNonce': ?challengeNonce,
        'challengeSignature': ?challengeSignature,
      },
    );
  }

  Future<Link> create({
    required String slug,
    required String label,
    required String user,
    required String workspace,
    required List<String> sections,
    required List<String> records,
    String status = 'active',
    String? identityId,
    String? password,
    DateTime? expiresAt,
    int? maxViews,
    bool requireHandshake = false,
  }) async {
    final spec = createShareSpec(
      slug: slug,
      label: label,
      user: user,
      workspace: workspace,
      sections: sections,
      records: records,
      status: status,
      identityId: identityId,
      password: password,
      expiresAt: expiresAt,
      maxViews: maxViews,
      requireHandshake: requireHandshake,
    );
    final data = await _api.post(spec.path, body: spec.body);
    return Link.fromJson(data as Map<String, dynamic>);
  }

  /// Pass an empty-string `password` to clear it (the hook skips hashing);
  /// omit the key entirely to leave it unchanged.
  Future<Link> update(String id, Map<String, dynamic> body) async {
    final spec = updateShareSpec(id, body);
    final data = await _api.patch(spec.path, body: spec.body);
    return Link.fromJson(data as Map<String, dynamic>);
  }

  Future<bool> isSlugTaken(String slug) async {
    try {
      final data = await _api.get(
        _basePath,
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
      if (!taken) {
        return candidate;
      }
      counter++;
    }
  }

  Future<void> delete(String id) async {
    await _api.delete(deleteShareSpec(id).path);
  }

  /// The exact API request [create] issues — single source of truth shared
  /// with the in-app API preview.
  ApiRequestSpec createShareSpec({
    required String slug,
    required String label,
    required String user,
    required String workspace,
    required List<String> sections,
    required List<String> records,
    String status = 'active',
    String? identityId,
    String? password,
    DateTime? expiresAt,
    int? maxViews,
    bool requireHandshake = false,
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: '/api/collections/${AppConfig.linksCollection}/records',
      body: {
        'slug': slug,
        'label': label,
        'user': user,
        'workspace': workspace,
        'sections': sections,
        'records': records,
        'status': status,
        if (identityId != null && identityId.isNotEmpty) 'identity': identityId,
        if (password != null && password.isNotEmpty) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (maxViews != null && maxViews > 0) 'maxViews': maxViews,
        'requireHandshake': requireHandshake,
      },
    );
  }

  ApiRequestSpec updateShareSpec(String id, Map<String, dynamic> body) {
    return ApiRequestSpec(
      method: 'PATCH',
      path: '/api/collections/${AppConfig.linksCollection}/records/$id',
      body: body,
    );
  }

  ApiRequestSpec deleteShareSpec(String id) {
    return ApiRequestSpec(
      method: 'DELETE',
      path: '/api/collections/${AppConfig.linksCollection}/records/$id',
    );
  }
}
