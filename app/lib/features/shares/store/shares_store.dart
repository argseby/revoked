import 'dart:typed_data';

import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/stores.dart';

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
  final ObservableTextController draftWatermarkText =
      ObservableTextController();

  /// Watermarking is on exactly when there is text to stamp, the way a share
  /// is gated exactly when it has a password.
  @computed
  bool get draftWatermark => draftWatermarkText.text.trim().isNotEmpty;

  @observable
  DateTime? draftExpiresAt;

  /// What a new link shares, picked in the form itself rather than in the
  /// vault after the link already exists.
  final ObservableSet<String> draftRecords = ObservableSet<String>();
  final ObservableSet<String> draftSections = ObservableSet<String>();

  @action
  void toggleDraftRecord(String id) => draftRecords.contains(id)
      ? draftRecords.remove(id)
      : draftRecords.add(id);

  @action
  void toggleDraftSection(String id) => draftSections.contains(id)
      ? draftSections.remove(id)
      : draftSections.add(id);

  @observable
  String? draftIdentityId;

  @observable
  bool draftRequireHandshake = false;

  @observable
  String? draftSlugWarning;

  @observable
  bool isSubmittingShare = false;

  /// Editing only: the gate should be lifted on save. A blank password field
  /// means "keep what is stored", so removing one needs to be said explicitly.
  @observable
  bool draftRemovePassword = false;

  @action
  void setDraftRemovePassword(bool value) => draftRemovePassword = value;

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
    String watermarkText = '',
    Iterable<String> records = const [],
    Iterable<String> sections = const [],
  }) {
    draftRecords
      ..clear()
      ..addAll(records);
    draftSections
      ..clear()
      ..addAll(sections);
    draftLabel.text = label;
    draftWatermarkText.text = watermarkText;
    draftSlug.text = slug;
    draftPassword.clear();
    draftMaxViews.text = maxViews;
    draftExpiresAt = expiresAt;
    draftIdentityId = identityId;
    draftRequireHandshake = requireHandshake;
    draftSlugWarning = null;
    draftRemovePassword = false;
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

  /// The key the open link's address ended in, which opens its end-to-end
  /// encrypted entries. In memory only, for as long as the view is open.
  Uint8List? shareLinkKey;

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
  /// Bytes already fetched for the open share. A download token is
  /// single-use, so View and then Download must not each spend one; the
  /// bytes stay in memory only until the share view is left.
  final Map<String, Uint8List> _sharedFileBytes = {};

  /// Why the last [downloadSharedFile] was refused, when the server gave a
  /// reason worth repeating: a stamped share does not hand out a file it
  /// cannot stamp. Null for any other failure.
  AppErrorMessage? sharedFileFailure;

  @action
  Future<Uint8List?> downloadSharedFile({
    required String? origin,
    required String slug,
    required String recordId,
    required String token,
  }) async {
    final cached = _sharedFileBytes[recordId];
    if (cached != null) return cached;
    downloadingShareRecordIds.add(recordId);
    sharedFileFailure = null;
    try {
      final bytes = await _api.getPublicBytes(
        origin,
        '/api/public/links/$slug/files/$recordId',
        queryParams: {'dl': token},
      );
      _sharedFileBytes[recordId] = bytes;
      return bytes;
    } catch (e) {
      errorMessage = describeError(e);
      if (e is ApiException && e.code == AppErrorCode.fileNotWatermarkable) {
        sharedFileFailure = AppErrorMessage.fromException(e);
      }
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
    shareLinkKey = null;
    shareTrustVerdict = null;
    isVerifyingShareTrust = false;
    shareData = null;
    shareTerminalError = null;
    sharePasswordHint = null;
    shareIdentityId = null;
    revealedShareValues.clear();
    _sharedFileBytes.clear();
  }

  /// This person's own shares.
  @observable
  ObservableList<Link> shares = ObservableList<Link>();

  /// Shares other members opened to this person (VISIBILITY.md). Listed
  /// apart, and read-only here.
  @observable
  ObservableList<Link> sharedShares = ObservableList<Link>();

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

  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [loadShares], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await loadShares();
  }

  @action
  Future<void> loadShares() async {
    isLoading = true;
    errorMessage = null;
    final ticket = loadState.begin();
    try {
      final me = Stores.auth.userId;
      final result = await getAll(filter: me.isEmpty ? null : 'user = "$me"');
      if (!loadState.isCurrent(ticket)) return;
      shares = ObservableList.of(result);
      loadState.succeed(ticket);
      // Its own failure: the person's own shares still show.
      if (me.isNotEmpty) {
        try {
          final others = await getAll(filter: 'user != "$me"');
          if (loadState.isCurrent(ticket)) {
            sharedShares = ObservableList.of(others);
          }
        } catch (_) {
          sharedShares = ObservableList<Link>();
        }
      }
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      errorMessage = describeError(e);
      loadState.fail(ticket, errorMessage!);
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
    bool watermark = false,
    String watermarkText = '',
    String purpose = '',
    String connection = '',
    String ref = '',
    bool handedOver = false,
    String audienceKind = '',
    List<String> audienceGroups = const [],
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
        watermark: watermark,
        watermarkText: watermarkText,
        purpose: purpose,
        connection: connection,
        ref: ref,
        handedOver: handedOver,
        audienceKind: audienceKind,
        audienceGroups: audienceGroups,
      );
      shares.insert(0, link);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
      // A colleague's share, changed by someone it is open to for editing.
      final shared = sharedShares.indexWhere((s) => s.id == id);
      if (shared != -1) sharedShares[shared] = updated;
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  @action
  Future<bool> deleteShare(String id) async {
    try {
      await delete(id);
      shares.removeWhere((s) => s.id == id);
      sharedShares.removeWhere((s) => s.id == id);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  @action
  void clearError() {
    errorMessage = null;
  }

  Future<List<Link>> getAll({
    int page = 1,
    int perPage = AppConfig.listPageSize,
    String? filter,
  }) async {
    final data = await _api.get(
      _basePath,
      queryParams: {
        'page': page.toString(),
        'perPage': perPage.toString(),
        'sort': '-created',
        'filter': ?filter,
      },
    );
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items.map((e) => Link.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Whether this person may change a colleague's share, as the server
  /// answers (VISIBILITY.md); null until asked. Their own they always may.
  Future<bool> canEditShare(String id) async {
    try {
      final access = await Stores.vault.loadAccess('links', id);
      return access['canEdit'] == true;
    } catch (_) {
      return false;
    }
  }

  /// A share by id, among this person's own or those opened to them.
  Link? findById(String id) {
    for (final l in shares) {
      if (l.id == id) return l;
    }
    for (final l in sharedShares) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Sets who sees one of this person's shares beside them, and whether
  /// those members may change it (VISIBILITY.md). Only the owner can.
  Future<bool> setShareAudience(
    String id, {
    required String kind,
    required String editing,
    List<String> groups = const [],
  }) async {
    final ok = await updateShare(id, {
      'audienceKind': kind,
      'editing': editing,
      'audienceGroups': groups,
    });
    if (ok) await _offerLinkKeyToAudience(id);
    return ok;
  }

  /// Gives the members who now see a link the means to show its address: the
  /// link's key under the workspace's key. Left undone when this device
  /// can't, which costs those members the full address and nothing else; the
  /// server takes that copy away by itself once the link is private again.
  Future<void> _offerLinkKeyToAudience(String id) async {
    final link = findById(id);
    if (link == null ||
        !link.hasKey ||
        link.audienceKind == 'private' ||
        link.sealedKeyWraps.containsKey(link.workspace)) {
      return;
    }
    final keys = Stores.keys;
    final linkKey = keys.openLinkKey(
      link: link.id,
      workspace: link.workspace,
      wraps: link.sealedKeyWraps,
    );
    if (linkKey == null) return;
    final wraps = keys.wrapLinkKey(
      linkKey: linkKey,
      link: link.id,
      workspace: link.workspace,
      forAccount: false,
      forWorkspace: true,
    );
    if (wraps == null) return;
    try {
      await _api.put(
        '/api/sealed/links/$id',
        body: {'keyWraps': wraps, 'expectedKeyWraps': link.sealedKeyWraps},
      );
      _replaceInLists(await getById(id));
    } catch (_) {
      // The link itself is as its owner set it.
    }
  }

  void _replaceInLists(Link link) {
    final own = shares.indexWhere((s) => s.id == link.id);
    if (own != -1) shares[own] = link;
    final shared = sharedShares.indexWhere((s) => s.id == link.id);
    if (shared != -1) sharedShares[shared] = link;
  }

  /// What follows `#k=` in a link's address, or null: the link carries
  /// nothing encrypted, or its key does not open on this device. Check
  /// [Link.hasKey] to tell the two apart.
  String? linkKeyText(Link link) {
    if (!link.hasKey) return null;
    final key = Stores.keys.openLinkKey(
      link: link.id,
      workspace: link.workspace,
      wraps: link.sealedKeyWraps,
    );
    return key == null ? null : SealedFormats.linkKeyText(key);
  }

  String? _addressChanged;

  /// Whether the last change gave this existing link a key, and with it a
  /// longer address: copies handed out before do not open what is encrypted.
  /// Answers once, so that one screen says so once.
  bool takeAddressChanged(String id) {
    final changed = _addressChanged == id;
    if (changed) _addressChanged = null;
    return changed;
  }

  /// The end-to-end encrypted records among [ids], as this device holds them.
  List<models.Record> _sealedAmong(Iterable<String> ids) {
    final sealed = <models.Record>[];
    for (final id in ids) {
      final record = Stores.vault.visibleRecord(id);
      if (record == null || !record.sealed) continue;
      if (record.isLocked) {
        throw const UserFacingException(
          'An encrypted record that is not readable on this device cannot '
          'be shared from it.',
        );
      }
      sealed.add(record);
    }
    return sealed;
  }

  /// Puts encrypted records on [link] (design/e2ee-sharing.md §3.3): for
  /// each, its current value key wrapped for the link, sent together with
  /// the link's key for its owner's devices when this is the link's first.
  /// The server adds the records in the same transaction.
  Future<Link> _sealOnto(
    Link link,
    List<models.Record> sealed, {
    required bool existing,
  }) async {
    final keys = Stores.keys;
    var linkKey = keys.openLinkKey(
      link: link.id,
      workspace: link.workspace,
      wraps: link.sealedKeyWraps,
    );
    Map<String, dynamic>? keyWraps;
    if (linkKey == null) {
      if (link.hasKey) {
        throw const UserFacingException(
          'The key of this link is not readable on this device, so nothing '
          'encrypted can be added from it.',
        );
      }
      if (link.user != Stores.auth.userId) {
        throw const UserFacingException(
          'The first encrypted record of a link is added by the link\'s '
          'owner.',
        );
      }
      if (!await keys.ensureAccountKey()) {
        throw const UserFacingException(
          'Encryption is not ready on this device.',
        );
      }
      linkKey = keys.newLinkKey();
      keyWraps =
          keys.wrapLinkKey(
            linkKey: linkKey,
            link: link.id,
            workspace: link.workspace,
            forWorkspace: link.audienceKind != 'private',
          ) ??
          keys.wrapLinkKey(
            linkKey: linkKey,
            link: link.id,
            workspace: link.workspace,
          );
      if (keyWraps == null) {
        throw const UserFacingException(
          'Encryption is not ready on this device.',
        );
      }
    }
    final seals = [
      for (final record in sealed)
        keys.sealForLink(linkKey: linkKey, link: link.id, record: record) ??
            (throw const UserFacingException(
              'An encrypted record that is not readable on this device '
              'cannot be shared from it.',
            )),
    ];
    await _api.put(
      '/api/sealed/links/${link.id}',
      body: {
        'seals': seals,
        'keyWraps': ?keyWraps,
        'expectedKeyWraps': link.sealedKeyWraps,
      },
    );
    if (existing && keyWraps != null) _addressChanged = link.id;
    return getById(link.id);
  }

  /// Prepares links already holding a plain record for its first encrypted
  /// version. Invisible links are never returned; a link whose key cannot
  /// be opened is left to the server's explicit drop confirmation.
  Future<List<Map<String, dynamic>>> prepareRecordLinks(String record) async {
    final dynamic data;
    try {
      data = await _api.get('/api/sealed/records/$record/links');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
    final prepared = <Map<String, dynamic>>[];
    for (final raw
        in (data as Map<String, dynamic>)['links'] as List? ?? const []) {
      final link = Link.fromJson({
        'slug': '',
        'label': '',
        ...raw as Map<String, dynamic>,
      });
      final keys = Stores.keys;
      var key = keys.openLinkKey(
        link: link.id,
        workspace: link.workspace,
        wraps: link.sealedKeyWraps,
      );
      Map<String, dynamic>? wraps;
      if (key == null) {
        if (link.hasKey || link.user != Stores.auth.userId) continue;
        if (!await keys.ensureAccountKey()) continue;
        key = keys.newLinkKey();
        wraps = keys.wrapLinkKey(
          linkKey: key,
          link: link.id,
          workspace: link.workspace,
          forWorkspace: link.audienceKind != 'private',
        );
        if (wraps == null) continue;
      }
      prepared.add({
        'link': link.id,
        'key': key,
        'expectedKeyWraps': link.sealedKeyWraps,
        'keyWraps': ?wraps,
      });
    }
    return prepared;
  }

  /// Replaces one link's address key and every encrypted entry atomically.
  Future<bool> replaceLinkKey(String id) async {
    errorMessage = null;
    try {
      final link = await getById(id);
      if (link.user != Stores.auth.userId || !link.hasKey) {
        throw const UserFacingException(
          'Only the owner can replace this link’s key.',
        );
      }
      await Stores.vault.loadRecords();
      if (Stores.vault.errorMessage != null) {
        throw UserFacingException(Stores.vault.errorMessage!);
      }
      final records = <models.Record>[];
      for (final recordID in link.records) {
        final record = Stores.vault.visibleRecord(recordID);
        if (record == null || record.isLocked) {
          throw const UserFacingException(
            'Every entry on this link must be readable on this device before its key can be replaced.',
          );
        }
        if (record.sealed) records.add(record);
      }
      final keys = Stores.keys;
      if (!await keys.ensureAccountKey()) {
        throw const UserFacingException(
          'Encryption is not ready on this device.',
        );
      }
      final key = keys.newLinkKey();
      final wraps = keys.wrapLinkKey(
        linkKey: key,
        link: link.id,
        workspace: link.workspace,
        forWorkspace: link.audienceKind != 'private',
      );
      if (wraps == null) {
        throw const UserFacingException(
          'Encryption is not ready on this device.',
        );
      }
      final seals = [
        for (final record in records)
          keys.sealForLink(linkKey: key, link: link.id, record: record) ??
              (throw const UserFacingException(
                'An encrypted entry could not be opened on this device.',
              )),
      ];
      await _api.put(
        '/api/sealed/links/$id',
        body: {
          'replaceKey': true,
          'expectedKeyWraps': link.sealedKeyWraps,
          'keyWraps': wraps,
          'seals': seals,
        },
      );
      _replaceInLists(await getById(id));
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  /// The server appends what it adds; the owner's order is put back.
  Future<Link> _inOrder(Link link, List<String> wanted) async =>
      listEquals(link.records, wanted)
      ? link
      : _patch(link.id, {'records': wanted});

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
    bool watermark = false,
    String watermarkText = '',
    String purpose = '',
    String connection = '',
    String ref = '',
    bool handedOver = false,
    String audienceKind = '',
    List<String> audienceGroups = const [],
  }) async {
    // Encrypted records join the link in a second request, each with its
    // key for the link: the server takes none without one.
    final sealed = _sealedAmong(records);
    final sealedIds = {for (final r in sealed) r.id};
    final spec = createShareSpec(
      slug: slug,
      label: label,
      user: user,
      workspace: workspace,
      sections: sections,
      records: [
        for (final id in records)
          if (!sealedIds.contains(id)) id,
      ],
      status: status,
      identityId: identityId,
      password: password,
      expiresAt: expiresAt,
      maxViews: maxViews,
      requireHandshake: requireHandshake,
      watermark: watermark,
      watermarkText: watermarkText,
      purpose: purpose,
      connection: connection,
      ref: ref,
      handedOver: handedOver,
      audienceKind: audienceKind,
      audienceGroups: audienceGroups,
    );
    final data = await _api.post(spec.path, body: spec.body);
    final link = Link.fromJson(data as Map<String, dynamic>);
    if (sealed.isEmpty) return link;
    try {
      return await _inOrder(
        await _sealOnto(link, sealed, existing: false),
        records,
      );
    } catch (_) {
      // Nobody holds its address yet, and it would lack what it was made
      // to share.
      try {
        await delete(link.id);
      } catch (_) {}
      rethrow;
    }
  }

  /// Pass an empty-string `password` to clear it (the hook skips hashing);
  /// omit the key entirely to leave it unchanged.
  ///
  /// Encrypted records added by [body] go on in a request of their own, each
  /// with its key for the link; everything else is one update as before.
  Future<Link> update(String id, Map<String, dynamic> body) async {
    final wanted = body['records'];
    if (wanted is! List) return _patch(id, body);
    final records = wanted.cast<String>().toList();
    final current = findById(id) ?? await getById(id);
    final added = _sealedAmong(
      records.where((r) => !current.records.contains(r)),
    );
    if (added.isEmpty) return _patch(id, body);
    final addedIds = {for (final r in added) r.id};
    final link = await _patch(id, {
      ...body,
      'records': [
        for (final r in records)
          if (!addedIds.contains(r)) r,
      ],
    });
    return _inOrder(await _sealOnto(link, added, existing: true), records);
  }

  Future<Link> _patch(String id, Map<String, dynamic> body) async {
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
    bool watermark = false,
    String watermarkText = '',
    String purpose = '',
    String connection = '',
    String ref = '',
    bool handedOver = false,
    String audienceKind = '',
    List<String> audienceGroups = const [],
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: '/api/collections/${AppConfig.linksCollection}/records',
      body: {
        'slug': slug,
        'label': label,
        'user': user,
        'workspace': workspace,
        // Who sees it; empty leaves it to the workspace's default.
        if (audienceKind.isNotEmpty) 'audienceKind': audienceKind,
        if (audienceGroups.isNotEmpty) 'audienceGroups': audienceGroups,
        'sections': sections,
        'records': records,
        'status': status,
        if (identityId != null && identityId.isNotEmpty) 'identity': identityId,
        if (password != null && password.isNotEmpty) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (maxViews != null && maxViews > 0) 'maxViews': maxViews,
        'requireHandshake': requireHandshake,
        if (watermark) 'watermark': true,
        if (watermark && watermarkText.isNotEmpty)
          'watermarkText': watermarkText,
        if (purpose.isNotEmpty) 'purpose': purpose,
        if (connection.isNotEmpty) ...{
          'connection': connection,
          if (ref.isNotEmpty) 'ref': ref,
          'handedOver': handedOver,
        },
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
