import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request_template.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Responder-facing screen for `/api/public/requests/:slug`.
///
/// Flow:
///   1. Probe → discover label, gates (password / identifier / handshake)
///      and the template the requester pinned. The requester's identity
///      (name + fingerprint) is rendered prominently at the top.
///   2. Render the template inputs. Required entries display the
///      requester's reason and cannot be removed. Optional entries can be
///      skipped. When the request allows extras, an "Add field" button
///      appears so the responder can submit ad-hoc keys.
///   3. Submission flow:
///        - requireHandshake → caller must be authenticated and use their
///          workspace identity (signed challenge against the identities
///          collection, persistent X-Handshake-Token returned).
///        - identifier-set without handshake → caller mints an ephemeral
///          RSA keypair + self-signed cert in-browser and signs a
///          challenge nonce against it. The server records the cert
///          fingerprint as the sender's provenance.
///        - neither → fully open submission.
class PublicRequestScreen extends StatefulWidget {
  final String requestSlug;

  /// host[:port] the link says it lives on; null = the signed-in server.
  final String? origin;

  const PublicRequestScreen({
    super.key,
    required this.requestSlug,
    this.origin,
  });

  @override
  State<PublicRequestScreen> createState() => _PublicRequestScreenState();
}

class _PublicRequestScreenState extends State<PublicRequestScreen> {
  static final _keyPattern = RegExp(r'^[a-z0-9_-]+$');

  RequestsStore get _store => Stores.requests;

  /// The in-flight domain check, so a submit can wait for it.
  Future<void>? _trustCheck;

  /// Per-template-entry controllers, keyed by the entry's server id.
  final Map<String, ObservableTextController> _templateCtrls = {};

  /// Optional / extra fields keyed by a synthetic uuid.
  final List<_ExtraField> _extraFields = [];

  @override
  void initState() {
    super.initState();
    // The store is a singleton, so the previous request's answers, links and
    // trust verdict are still in it.
    _store.resetPublicView();
    _probeRequest();
  }

  @override
  void dispose() {
    for (final c in _templateCtrls.values) {
      c.dispose();
    }
    for (final f in _extraFields) {
      f.dispose();
    }
    super.dispose();
  }

  /// True when the link lives on a server this session holds no account on.
  bool get _isForeign => !Stores.api.isOwnOrigin(widget.origin);

  String _handshakeKey() => 'handshake_request_${widget.requestSlug}';

  Future<String?> _loadStoredHandshake() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_handshakeKey());
  }

  Future<void> _persistHandshake(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handshakeKey(), token);
  }

  Future<void> _probeRequest() async {
    runInAction(() {
      _store.isLoadingPublic = true;
      _store.publicTerminalError = null;
    });
    try {
      final probe = await Stores.requests.getPublicRequestProbe(
        widget.requestSlug,
        origin: widget.origin,
      );
      final template = RequestsStore.parseTemplateFromProbe(probe);
      _templateCtrls
        ..clear()
        ..addEntries(
          template
              .where((t) => t.isRecord)
              .map((t) => MapEntry(t.key, ObservableTextController())),
        );
      runInAction(() {
        _store.publicProbe = probe;
        _store.publicTemplate
          ..clear()
          ..addAll(template);
        _store.isLoadingPublic = false;
      });
      // The probe is everything the form needs to render. The vault prefill
      // and the DNS walk are conveniences behind up to four more authenticated
      // round-trips; awaiting them here left the screen on its spinner for as
      // long as they took — or forever if a session had gone stale.
      unawaited(_prefillFromVault());
      _trustCheck = _verifyTrust();
      unawaited(_trustCheck!);
    } on ApiException catch (e) {
      runInAction(() {
        _store.publicTerminalError = AppErrorMessage.fromException(e);
        _store.isLoadingPublic = false;
      });
    } catch (e) {
      runInAction(() {
        _store.publicTerminalError = AppErrorMessage.fromException(e);
        _store.isLoadingPublic = false;
      });
    }
  }

  /// When signed in, pull the responder's vault and auto-link any field whose
  /// key already exists — so the value is prefilled and forwarded as a living
  /// reference rather than re-typed.
  Future<void> _prefillFromVault() async {
    // The vault, identities and any existing response live on the signed-in
    // server; against a foreign origin those lookups would be nonsense.
    if (_isForeign) return;
    if (!Stores.auth.isAuthenticated) return;
    try {
      await Stores.vault.loadRecords();
      if (!mounted) return;
      runInAction(() {
        _store.responderVault
          ..clear()
          ..addAll(Stores.vault.records);
      });

      await Stores.identities.loadIdentities();
      if (!mounted) return;
      runInAction(() {
        if (_store.publicIdentityId == null) _initSelectedIdentity();
        for (final item in _store.publicTemplate.where((t) => t.isRecord)) {
          // The form is already on screen, so never overwrite an answer the
          // responder has started typing or a choice they made.
          if (_answered(item.key)) continue;
          final match = _matchVaultRecord(item.key);
          if (match != null) _store.publicLinked[item.key] = match.id;
        }
      });

      // Already answered this request? Surface it and prefill from the existing
      // grant so re-submitting updates in place instead of creating a duplicate.
      final requestId = _store.publicProbe?['requestId'] as String? ?? '';
      if (requestId.isEmpty) return;
      final existing = await Stores.requests.getMyLinkForRequest(requestId);
      if (!mounted) return;
      if (existing == null ||
          (existing['status'] as String? ?? '') == 'revoked') {
        return;
      }
      runInAction(() {
        _store.publicExistingLink = existing;
        final grants = existing['grants'];
        if (grants is Map) {
          grants.forEach((k, v) {
            if (v is String && v.isNotEmpty && !_answered(k.toString())) {
              _store.publicLinked[k.toString()] = v;
            }
          });
        }
      });
    } catch (_) {
      // Vault / existing-link lookups are conveniences; ignore failures.
    }
  }

  /// Whether the responder has already put something in [key] themselves.
  bool _answered(String key) =>
      (_templateCtrls[key]?.text.trim().isNotEmpty ?? false) ||
      _store.publicLinked.containsKey(key) ||
      _store.publicExcluded.contains(key);

  Map<String, dynamic>? get _requester {
    final r = _store.publicProbe?['requester'];
    return r is Map<String, dynamic> ? r : null;
  }

  /// Walks the DNS trust chain for the requester's server claim. The
  /// probe carries `server.domain` (the requester's hub domain) and
  /// `requester.parentSignature` / `requester.fingerprint` — these are
  /// the inputs DomainVerificationService needs. A null verdict means
  /// the probe didn't carry the new fields (pre-DNS server); the badge
  /// renders as "unverified" in that case.
  /// The verdict, waiting for the in-flight check if there is one. Never
  /// returns null: a check that cannot produce an answer is `unverified`,
  /// which the caller gates on, rather than an absent verdict, which it
  /// cannot.
  Future<TrustVerdict> _awaitTrustVerdict() async {
    final pending = _trustCheck;
    if (pending != null) await pending;
    return _store.publicTrustVerdict ??
        TrustVerdict.unverified(
          domain: _serverDomain,
          reason:
              'The requester\'s domain could not be checked, so nothing '
              'confirms this request comes from who it claims to.',
        );
  }

  Future<void> _verifyTrust() async {
    final probe = _store.publicProbe;
    if (probe == null) return;
    final server = probe['server'];
    final requester = _requester;
    final domain = server is Map<String, dynamic>
        ? (server['domain'] as String? ?? '')
        : '';
    final fingerprint = requester?['fingerprint'] as String? ?? '';
    final parentSig = requester?['parentSignature'] as String? ?? '';

    runInAction(() => _store.isVerifyingTrust = true);
    TrustVerdict verdict;
    try {
      verdict = await Stores.domainVerification.verify(
        claimedDomain: domain,
        identityFingerprint: fingerprint,
        parentSignatureHex: parentSig,
      );
    } catch (e) {
      // An escaping exception used to leave the badge on "Checking domain…"
      // for good and the gate permanently disengaged. A failure to verify is
      // an unverified identity, not the absence of an opinion.
      verdict = TrustVerdict.unverified(
        domain: domain,
        reason: 'The domain check could not be completed: $e',
      );
    }
    if (!mounted) return;
    runInAction(() {
      _store.publicTrustVerdict = verdict;
      _store.isVerifyingTrust = false;
    });
  }

  bool get _requiresPassword =>
      _store.publicProbe?['requiresPassword'] as bool? ?? false;
  bool get _requireHandshake =>
      _store.publicProbe?['requireHandshake'] as bool? ?? false;
  bool get _allowExtraFields =>
      _store.publicProbe?['allowExtraFields'] as bool? ?? false;
  bool get _hasIdentifier =>
      _store.publicProbe?['requiresIdentifier'] as bool? ?? false;

  /// 'any' (default) or 'from_root' — which identities the request accepts.
  String get _identityScope =>
      _store.publicProbe?['identityScope'] as String? ?? 'any';

  /// The requester's server (root) domain, from the probe.
  String get _serverDomain {
    final s = _store.publicProbe?['server'];
    return s is Map<String, dynamic> ? (s['domain'] as String? ?? '') : '';
  }

  /// True when the requester's server is a local/dev host where public DNS
  /// trust verification cannot apply (localhost, loopback, LAN/private IPs).
  /// Submitting against such a server shouldn't be gated on a DNS proof that
  /// can never exist.
  bool get _isLocalServer {
    final d = _serverDomain.toLowerCase();
    if (d.isEmpty) return false;
    if (d == 'localhost' || d == '127.0.0.1' || d == '::1') return true;
    if (d.endsWith('.local')) return true;
    if (d.startsWith('192.168.') || d.startsWith('10.')) return true;
    return RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(d);
  }

  bool _selectedIdentityQualifies() {
    if (_identityScope != 'from_root') return true;
    for (final i in Stores.identities.identities) {
      if (i.id == _store.publicIdentityId) {
        return i.domainAtIssue == _serverDomain;
      }
    }
    return true; // no match → defer to the identity/auth checks
  }

  /// Picks a sensible default identity: a root-issued one when the request is
  /// root-restricted, otherwise the primary (falling back to the first).
  void _initSelectedIdentity() {
    final ids = Stores.identities.identities;
    if (ids.isEmpty) {
      _store.publicIdentityId = null;
      return;
    }
    final rootOnly = _identityScope == 'from_root';
    String? rootPick;
    String? primaryPick;
    String? firstId;
    for (final i in ids) {
      firstId ??= i.id;
      if (i.isPrimary) primaryPick ??= i.id;
      if (rootOnly && i.domainAtIssue == _serverDomain) rootPick ??= i.id;
    }
    _store.publicIdentityId =
        (rootOnly ? rootPick : null) ?? primaryPick ?? firstId;
  }

  Future<void> _submit() async {
    if (_store.publicProbe == null) return;

    // Trust gate. A spoofed verdict is a hard block — the requester is
    // actively lying about which domain they belong to and the user
    // should never submit data in that state. Any other non-verified
    // verdict (DNS missing, identity pre-DNS) gets a confirm-anyway
    // dialog so the user makes an explicit choice.
    // DNS domain-trust can't apply to a local/dev server (there's no public
    // _revoked.<host> TXT record for localhost or a LAN IP), so skip the gate
    // there — otherwise every local submit is interrupted by a warning.
    if (!_isLocalServer) {
      // Wait for the verdict rather than proceeding without one. Verification
      // is kicked off unawaited so the form renders immediately, so a fast
      // submit used to arrive while it was still in flight — and a gate that
      // only fires on a non-null verdict let that through unguarded, which is
      // precisely the case it exists to catch.
      final verdict = await _awaitTrustVerdict();

      if (verdict.state == TrustState.spoofed) {
        runInAction(
          () =>
              _store.publicFormError = 'Submission blocked: ${verdict.reason}',
        );
        return;
      }
      if (verdict.state != TrustState.verified &&
          !await _confirmUnverifiedSubmit(verdict)) {
        return;
      }
    }

    if (_requiresPassword && _store.responderPassword.text.trim().isEmpty) {
      runInAction(() => _store.publicFormError = 'Password is required.');
      return;
    }
    if (_hasIdentifier && _store.responderIdentifier.text.trim().isEmpty) {
      runInAction(() => _store.publicFormError = 'Identifier is required.');
      return;
    }
    if (_requireHandshake && !_selectedIdentityQualifies()) {
      runInAction(
        () => _store.publicFormError =
            'This request only accepts identities issued by '
            '${_serverDomain.isEmpty ? 'this server' : _serverDomain}. '
            'Pick a different identity.',
      );
      return;
    }

    // Required template fields must be satisfied — either linked to a vault
    // entry or typed in. (Required fields can't be stripped.)
    for (final item in _store.publicTemplate.where(
      (t) => t.isRecord && t.required,
    )) {
      if (_store.publicLinked.containsKey(item.key)) continue;
      final ctrl = _templateCtrls[item.key];
      if (ctrl?.text.trim().isEmpty ?? true) {
        runInAction(
          () => _store.publicFormError =
              'Required field "${item.label}" cannot be empty.',
        );
        return;
      }
    }

    // Extras must match the slug regex if the responder added any.
    for (final f in _extraFields) {
      final k = f.keyCtrl.text.trim();
      if (k.isEmpty) continue;
      if (!_keyPattern.hasMatch(k)) {
        runInAction(
          () => _store.publicFormError =
              'Extra field key "$k" must use lowercase letters, digits, '
              'underscores or hyphens only.',
        );
        return;
      }
    }

    runInAction(() {
      _store.isSubmittingPublic = true;
      _store.publicFormError = null;
    });

    final data = <String, dynamic>{};
    final mappings = <String, String>{};
    for (final item in _store.publicTemplate.where((t) => t.isRecord)) {
      if (_store.publicExcluded.contains(item.key)) {
        continue; // responder stripped it
      }
      final linkedId = _store.publicLinked[item.key];
      if (linkedId != null) {
        mappings[item.key] = linkedId; // forward a living vault reference
      } else {
        final v = _templateCtrls[item.key]?.text.trim() ?? '';
        if (v.isNotEmpty) data[item.key] = v;
      }
    }
    for (final f in _extraFields) {
      final k = f.keyCtrl.text.trim();
      final v = f.valueCtrl.text.trim();
      if (k.isNotEmpty) data[k] = v;
    }

    if (_requireHandshake && _isForeign) {
      // Identities live on the server that issued them; this link's server
      // has never seen any of this device's keys.
      _store.setPublicFormError(
        'This request requires a verified identity, and it lives on a '
        'different server than the one you are signed into. Cross-server '
        'verification is not supported yet.',
      );
      return;
    }

    try {
      final stored = await _loadStoredHandshake();
      String? guestCert;
      SignedChallenge? challenge;

      // In handshake mode, sign a fresh challenge every time. The stored token
      // (if any) is still sent as a fast-path, but always signing means a lost
      // or stale token can't lock the responder out — the signature alone
      // re-establishes the handshake on the server.
      final identityId = _requireHandshake
          ? (_store.publicIdentityId ?? Stores.identities.primaryIdentity?.id)
          : null;
      if (_requireHandshake) {
        if (identityId == null || identityId.isEmpty) {
          runInAction(() {
            _store.publicFormError =
                'This request requires authentication. Sign in and create an identity first.';
            _store.isSubmittingPublic = false;
          });
          return;
        }
        challenge = await Stores.handshake.prepare(
          scope: HandshakeService.scopeRequest,
          slug: widget.requestSlug,
          identityId: identityId,
        );
      }

      if (!_requireHandshake && _hasIdentifier) {
        final ephemeral = Stores.crypto.generateIdentity(
          commonName: _store.responderName.text.trim().isEmpty
              ? 'guest-${widget.requestSlug}'
              : _store.responderName.text.trim(),
        );
        guestCert = ephemeral.publicKeyPem;
        final fp = Stores.crypto.sha256Hex(ephemeral.publicKeyPem);
        challenge = await Stores.handshake.prepareGuest(
          slug: widget.requestSlug,
          publicKeyPem: ephemeral.publicKeyPem,
          privateKeyPem: ephemeral.privateKeyPem,
          fingerprint: fp,
        );
      }

      final response = await Stores.requests.submitPublicRequest(
        widget.requestSlug,
        password: _store.responderPassword.text.trim().isEmpty
            ? null
            : _store.responderPassword.text.trim(),
        identifier: _store.responderIdentifier.text.trim().isEmpty
            ? null
            : _store.responderIdentifier.text.trim(),
        handshakeToken: stored,
        identityId: identityId,
        challengeNonce: challenge?.nonce,
        challengeSignature: challenge?.signature,
        guestCertificate: guestCert,
        senderName: _store.responderName.text.trim().isEmpty
            ? null
            : _store.responderName.text.trim(),
        data: data,
        mappings: mappings.isEmpty ? null : mappings,
      );

      // The response is already recorded on the server at this point. Caching
      // the returned handshake token is a best-effort convenience for next
      // time — a failure here (e.g. SharedPreferences I/O) must NOT surface as
      // a failed submission, or the user sees an error for data that landed.
      final newHandshake = response.headers['x-handshake-token'];
      if (newHandshake != null && newHandshake.isNotEmpty) {
        try {
          await _persistHandshake(newHandshake);
        } catch (_) {
          // Non-fatal: response saved; we just couldn't cache the token.
        }
      }

      if (!mounted) return;
      runInAction(() {
        _store.publicSuccess = true;
        _store.isSubmittingPublic = false;
      });
      AppToast.success(
        context,
        _store.publicExistingLink != null ? 'Response updated' : 'Submitted',
      );
    } on ApiException catch (e) {
      debugPrint(
        '[request submit] ApiException ${e.statusCode} ${e.code}: ${e.message}',
      );
      final msg = AppErrorMessage.fromException(e);
      if (!mounted) return;
      runInAction(() {
        if (msg.isTerminal) {
          _store.publicTerminalError = msg;
        } else {
          _store.publicFormError = msg.description;
        }
        _store.isSubmittingPublic = false;
      });
    } catch (e, st) {
      debugPrint('[request submit] error: $e\n$st');
      if (!mounted) return;
      runInAction(() {
        _store.publicFormError = e.toString();
        _store.isSubmittingPublic = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    // The responder's own typing lives in TextEditingControllers the form
    // reads directly; this counter is what makes those edits observable.
    _store.publicRevision;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  AppButton(
                    icon: AppIcons.arrowLeft,
                    tooltip: 'Back to app',
                    style: AppButtonStyle.accent,
                    size: AppButtonSize.small,
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.vault);
                      }
                    },
                  ),
                  const Spacer(),
                  // When signed in, show which account/workspace this request
                  // will be filled as, with a quick switcher. Otherwise show
                  // the public trust badge.
                  Observer(
                    builder: (_) {
                      if (Stores.auth.isAuthenticated) {
                        return const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WorkspaceChip(),
                            SizedBox(width: AppSpacing.xs),
                            AccountButton(),
                          ],
                        );
                      }
                      return const AppBadge(
                        label: 'SECURE REQUEST',
                        variant: AppBadgeVariant.outline,
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_store.isLoadingPublic) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSpinner(large: true),
            const SizedBox(height: AppSpacing.md),
            const Text('Retrieving request…').muted,
          ],
        ),
      );
    }
    if (_store.publicTerminalError != null &&
        _store.publicTerminalError!.isTerminal) {
      return _buildTerminal(theme, _store.publicTerminalError!);
    }
    if (_store.publicSuccess) {
      return _buildSuccess(theme);
    }
    if (_store.publicProbe == null) {
      return _buildTerminal(
        theme,
        const AppErrorMessage(
          title: 'Could not load request',
          description: 'Try again later.',
          code: '',
        ),
      );
    }
    return _buildForm(theme);
  }

  Widget _buildTerminal(ThemeData theme, AppErrorMessage msg) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.exclamationOctagon,
                color: theme.colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(msg.title).header,
              const SizedBox(height: AppSpacing.sm),
              Text(msg.description, textAlign: TextAlign.center).muted.small,
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Try again',
                onTap: _probeRequest,
                style: AppButtonStyle.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.checkCircle,
                  color: theme.colorScheme.primary,
                  size: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Thanks — submission received').header,
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'The requester has been notified. You can close this window.',
                textAlign: TextAlign.center,
              ).muted.small,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final label = _store.publicProbe!['label'] as String? ?? 'Data request';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-pane on a wide window: your inputs on the left, everything the
        // request is/needs as hoverable tags on the right. Stacks to a single
        // column when there isn't room.
        final wide = constraints.maxWidth >= 900;
        final info = _buildInfoPanel(theme, label);
        final input = _buildInputPanel(theme);

        final Widget body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: input),
                  const SizedBox(width: AppSpacing.xxl),
                  SizedBox(width: 320, child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: AppSpacing.lg),
                  input,
                ],
              );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1060 : 640),
              child: body,
            ),
          ),
        );
      },
    );
  }

  /// Right-hand (or top, on mobile) panel: who is asking and everything this
  /// request is or needs — expressed as one consistent set of hoverable tags
  /// rather than a stack of differently-styled banners.
  Widget _buildInfoPanel(ThemeData theme, String label) {
    final scheme = theme.colorScheme;
    final requester = _requester;
    final name = requester?['name'] as String? ?? '';
    final domain = requester?['domainAtIssue'] as String? ?? '';
    final fp = requester?['fingerprint'] as String? ?? '';
    final shortFp = fp.length > 16
        ? '${fp.substring(0, 8)}…${fp.substring(fp.length - 8)}'
        : fp;

    final templateRecords = _store.publicTemplate
        .where((t) => t.isRecord)
        .toList();
    final fieldNames = templateRecords.map((t) => t.label).join(', ');

    final tags = <Widget>[
      _trustTag(theme),
      if (_requireHandshake)
        const _InfoTag(
          icon: AppIcons.shieldCheck,
          label: 'Verified identity',
          tooltip:
              'You must sign this response with a cryptographic identity, so '
              'the requester knows it really came from you.',
        ),
      if (_requireHandshake && _identityScope == 'from_root')
        _InfoTag(
          icon: AppIcons.shieldLock,
          label:
              'Issued by ${_serverDomain.isEmpty ? 'this server' : _serverDomain}',
          tooltip:
              'Only identities issued by this server are accepted for this '
              'request.',
        ),
      if (_hasIdentifier)
        const _InfoTag(
          icon: AppIcons.tag,
          label: 'Identifier',
          tooltip:
              'The requester gave you a secret identifier — enter it exactly '
              'to prove this request is meant for you.',
        ),
      if (_requiresPassword)
        const _InfoTag(
          icon: AppIcons.lock,
          label: 'Password',
          tooltip: 'A password the requester gave you is required to submit.',
        ),
      if (templateRecords.isNotEmpty)
        _InfoTag(
          icon: AppIcons.cardList,
          label:
              '${templateRecords.length} ${templateRecords.length == 1 ? 'field' : 'fields'}',
          tooltip: 'Requested: $fieldNames',
        ),
      if (_store.publicExistingLink != null)
        _InfoTag(
          icon: AppIcons.checkCircle,
          label: 'Already responded',
          accent: scheme.primary,
          tooltip:
              'You already have a live response. Submitting again updates it '
              'in place — no duplicate is created.',
        ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _trustProven ? AppIcons.shieldCheck : AppIcons.exclamation,
                color: _trustProven ? scheme.primary : scheme.danger,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label).header),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Your submission is private to the requester, and you can revoke '
            'it at any time.',
          ).muted.small,

          if (name.isNotEmpty)
            _section('Requested by', [
              _requesterLine(theme, name, domain),
              if (shortFp.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(shortFp).muted.mono.small,
              ],
            ]),

          _section('This request', [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: tags,
            ),
          ]),

          if (_store.publicExistingLink != null)
            _section('Already answered', [
              AppButton(
                icon: AppIcons.xCircle,
                label: 'Revoke my response',
                style: AppButtonStyle.destructive,
                size: AppButtonSize.small,
                onTap: _revokeExisting,
              ),
            ]),
        ],
      ),
    );
  }

  /// Whether DNS actually proved the requester owns the domain they claim.
  /// Everything else — no verdict yet, no TXT record, an outright mismatch —
  /// is unproven, and the screen must not decorate it as if it were proven.
  bool get _trustProven =>
      _isLocalServer || _store.publicTrustVerdict?.state == TrustState.verified;

  /// The "Requested by" line.
  ///
  /// The name and the domain both arrive inside the request; neither is worth
  /// anything until DNS confirms the domain. Rendering `Name (example.com)` in
  /// plain text is the whole phishing primitive this product exists to stop —
  /// it lends a stranger's claim the typography of a fact. So the domain is
  /// only ever printed as a domain once it is proven; until then it is labelled
  /// as a claim, and when it is provably false it is not printed at all.
  Widget _requesterLine(ThemeData theme, String name, String domain) {
    final scheme = theme.colorScheme;

    if (_trustProven) {
      return Text(domain.isEmpty ? name : '$name ($domain)').small;
    }

    final spoofed = _store.publicTrustVerdict?.state == TrustState.spoofed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name).small,
        const SizedBox(height: AppSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.exclamationTriangle, size: 13, color: scheme.danger),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                spoofed
                    // Repeating a domain that failed verification only helps
                    // whoever chose it.
                    ? 'The domain this request claims failed verification.'
                    : domain.isEmpty
                    ? 'Claims no domain. Nothing here has been verified.'
                    : 'Claims to be “$domain” — unverified. Anyone can put '
                          'any name and domain here.',
              ).small,
            ),
          ],
        ),
      ],
    );
  }

  Widget _trustTag(ThemeData theme) {
    final scheme = theme.colorScheme;
    if (_isLocalServer) {
      return const _InfoTag(
        icon: AppIcons.server,
        label: 'Local server',
        tooltip:
            'This is a local/development server, so public domain '
            'verification does not apply.',
      );
    }
    if (_store.isVerifyingTrust && _store.publicTrustVerdict == null) {
      return const _InfoTag(
        icon: AppIcons.arrowRepeat,
        label: 'Checking domain…',
        tooltip: 'Verifying the requester\'s domain against public DNS.',
      );
    }
    final v = _store.publicTrustVerdict;
    if (v == null) {
      return _InfoTag(
        icon: AppIcons.exclamationTriangle,
        accent: theme.colorScheme.danger,
        label: 'Unverified',
        tooltip: 'The requester\'s domain has not been verified.',
      );
    }
    switch (v.state) {
      case TrustState.verified:
        return _InfoTag(
          icon: AppIcons.shieldCheck,
          label: 'Domain verified',
          accent: scheme.primary,
          tooltip: v.reason,
        );
      case TrustState.spoofed:
        return _InfoTag(
          icon: AppIcons.exclamationTriangle,
          label: 'Domain spoofed',
          accent: scheme.danger,
          tooltip: v.reason,
        );
      case TrustState.dnsMissing:
      case TrustState.unverified:
        return _InfoTag(
          icon: AppIcons.exclamationTriangle,
          accent: scheme.danger,
          label: 'Unverified domain',
          tooltip: v.reason,
        );
    }
  }

  /// Left-hand (or bottom, on mobile) panel: everything the responder fills in.
  Widget _buildInputPanel(ThemeData theme) {
    final templateRecords = _store.publicTemplate
        .where((t) => t.isRecord)
        .toList();

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your response').header,
          const SizedBox(height: AppSpacing.xxs),
          const Text('Only the requester can see what you submit.').muted.small,

          if (_requiresPassword || _hasIdentifier)
            _section('Access', [_accessInputs(theme)]),

          if (_requireHandshake)
            _section('Signing identity', [_buildIdentityPicker(theme)]),

          _section('About you', [
            _field(
              'Your name',
              optional: true,
              child: AppTextField(
                controller: _store.responderName,
                hint: 'Anonymous',
              ),
            ),
          ]),

          if (templateRecords.isNotEmpty)
            _section('Requested information', [
              for (final item in templateRecords)
                _buildTemplateField(theme, item),
            ]),

          if (_allowExtraFields) _section('Anything else', [_extraFieldRows()]),

          if (_store.publicFormError != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _inlineError(_store.publicFormError!),
          ],

          const SizedBox(height: AppSpacing.xl),
          AppButton(
            icon: AppIcons.send,
            label: _store.publicExistingLink != null
                ? 'Update response'
                : 'Submit response',
            busy: _store.isSubmittingPublic,
            onTap: _submit,
          ),
        ],
      ),
    );
  }

  /// One labelled group inside a panel. Every group owns the space above its
  /// own heading, so the panels keep one rhythm no matter which groups a
  /// particular request happens to show.
  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(title).small.muted,
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }

  /// A label sitting directly on top of its input, at one fixed gap.
  Widget _field(String label, {required Widget child, bool optional = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label).small,
            if (optional) ...[
              const SizedBox(width: AppSpacing.xs),
              const Text('optional').muted.small,
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }

  Widget _extraFieldRows() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._extraFields.asMap().entries.map((entry) {
          final i = entry.key;
          final f = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: AppTextField(
                    controller: f.keyCtrl,
                    hint: 'field-name',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 6,
                  child: AppTextField(controller: f.valueCtrl, hint: 'Value'),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  icon: AppIcons.x,
                  tooltip: 'Remove field',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    _extraFields[i].dispose();
                    _extraFields.removeAt(i);
                    _store.touchPublic();
                  },
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            icon: AppIcons.plus,
            label: 'Add another field',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              _extraFields.add(_ExtraField());
              _store.touchPublic();
            },
          ),
        ),
      ],
    );
  }

  /// Access gates the responder must satisfy (password / identifier). These are
  /// inputs, so they live with the form rather than the info panel.
  Widget _accessInputs(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_requiresPassword)
          _field(
            'Password',
            child: AppTextField(
              controller: _store.responderPassword,
              obscureText: true,
              hint: 'Password the requester gave you',
            ),
          ),
        if (_requiresPassword && _hasIdentifier)
          const SizedBox(height: AppSpacing.md),
        if (_hasIdentifier)
          _field(
            'Identifier',
            child: AppTextField(
              controller: _store.responderIdentifier,
              hint: 'Identifier the requester gave you',
            ),
          ),
        if (_hasIdentifier && !_requireHandshake) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'A one-time identity is generated on this device to sign your '
            'submission — no account needed.',
          ).muted.small,
        ],
      ],
    );
  }

  Widget _inlineError(String message) {
    return AppAlert(
      destructive: true,
      leading: const Icon(AppIcons.exclamationTriangle),
      content: Text(message).small,
    );
  }

  Future<void> _revokeExisting() async {
    final id = _store.publicExistingLink?['id'] as String?;
    if (id == null) return;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke your response?',
      message:
          'The requester immediately loses access to the data you shared. '
          'You can respond again later.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await Stores.requests.revokeMyLink(id);
      if (!mounted) return;
      runInAction(() => _store.publicExistingLink = null);
      AppToast.success(context, 'Your response was revoked');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not revoke', subtitle: e.toString());
    }
  }

  /// Modal confirming the user wants to submit despite the trust chain
  /// not being fully verified. Defaults to "Cancel" so an accidental
  /// tap doesn't leak data.
  Future<bool> _confirmUnverifiedSubmit(TrustVerdict verdict) async {
    return showAppDialog(
      context: context,
      title: 'Submit without verification?',
      icon: AppIcons.exclamationTriangle,
      iconColor: Theme.of(context).colorScheme.error,
      message: verdict.reason,
      content: const Text(
        'You can still submit, but the requester\'s domain has '
        'not been cryptographically verified. Only continue if '
        'you trust the source out-of-band.',
      ).muted.small,
      confirmLabel: 'Submit anyway',
    );
  }

  /// Lets the signed-in responder choose which identity signs this response.
  /// Shown only when the request requires a verified identity.
  Widget _buildIdentityPicker(ThemeData theme) {
    final scheme = theme.colorScheme;
    final rootOnly = _identityScope == 'from_root';
    final domainLabel = _serverDomain.isEmpty ? 'this server' : _serverDomain;

    if (Stores.identities.identities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              AppIcons.shieldCheck,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                Stores.auth.isAuthenticated
                    ? 'This request needs a verified identity. Create one in '
                          'Account → Identities.'
                    : 'This request needs a verified identity. Sign in and '
                          'create one to respond.',
              ).muted.small,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdentityPicker(
          selectedId: _store.publicIdentityId,
          onChanged: (v) => runInAction(() => _store.publicIdentityId = v),
          requireDomain: rootOnly ? _serverDomain : null,
        ),
        if (rootOnly) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Only identities issued by $domainLabel are accepted.',
          ).muted.small,
        ],
      ],
    );
  }

  Widget _buildTemplateField(ThemeData theme, RequestTemplateItem item) {
    final ctrl = _templateCtrls.putIfAbsent(item.key, () {
      return ObservableTextController();
    });
    final linkedId = _store.publicLinked[item.key];
    final linked = linkedId == null ? null : _recordById(linkedId);
    final excluded = _store.publicExcluded.contains(item.key);
    final canUseVault =
        Stores.auth.isAuthenticated && _store.responderVault.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(child: Text(item.label).small),
              if (item.required) ...[
                const SizedBox(width: AppSpacing.xs),
                const AppBadge(
                  label: 'REQUIRED',
                  variant: AppBadgeVariant.primary,
                ),
              ],
              const Spacer(),
              if (!item.required)
                _ShareToggle(
                  shared: !excluded,
                  onTap: () => runInAction(() {
                    if (excluded) {
                      _store.publicExcluded.remove(item.key);
                    } else {
                      _store.publicExcluded.add(item.key);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(item.key).muted.mono.small,
          if (item.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(item.reason).muted.small,
          ],
          const SizedBox(height: AppSpacing.xs),
          if (excluded)
            _excludedBox(theme, item)
          else if (linked != null)
            _linkedBox(theme, item, linked)
          else ...[
            AppTextField(
              controller: ctrl,
              obscureText: item.format == 'hidden',
              keyboardType: item.type == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
              hint: item.required
                  ? 'Required value'
                  : 'Optional value — leave blank to skip',
            ),
            // Only offer the vault picker for keys you DON'T already hold —
            // you can't alias a different record onto a key you have.
            if (canUseVault && _matchVaultRecord(item.key) == null)
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  icon: AppIcons.link,
                  label: 'Use a vault entry',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () => _openVaultPicker(item),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Read-only display for a field linked to a vault record (a living grant).
  Widget _linkedBox(
    ThemeData theme,
    RequestTemplateItem item,
    models.Record linked,
  ) {
    final aliased = linked.key != item.key;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(AppIcons.link, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayValue(linked)).small,
                const SizedBox(height: 1),
                Text(
                  aliased
                      ? 'Aliased from "${linked.key}" in your vault'
                      : 'Linked from your vault',
                ).muted.small,
              ],
            ),
          ),
          // Exact-key matches are locked to your real record — you can't swap a
          // different value onto a field you already hold. Aliased picks (from
          // a key you don't have) can still be changed.
          if (aliased)
            AppButton(
              icon: AppIcons.xCircle,
              tooltip: 'Use a different value',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () =>
                  runInAction(() => _store.publicLinked.remove(item.key)),
            )
          else
            Icon(
              AppIcons.lock,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// Placeholder shown when the responder has opted out of forwarding an
  /// optional field.
  Widget _excludedBox(ThemeData theme, RequestTemplateItem item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.linkSlash,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Not shared — left blank for the requester.',
            ).muted.small,
          ),
          AppButton(
            label: 'Share',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () =>
                runInAction(() => _store.publicExcluded.remove(item.key)),
          ),
        ],
      ),
    );
  }

  models.Record? _recordById(String id) {
    for (final r in _store.responderVault) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// First vault record whose key equals [key], preferring a value-carrier
  /// (non-alias) over an alias.
  models.Record? _matchVaultRecord(String key) {
    models.Record? alias;
    for (final r in _store.responderVault) {
      if (r.key != key) continue;
      if (!r.isAlias) return r;
      alias ??= r;
    }
    return alias;
  }

  /// Display value for a (possibly alias) record — dereferences to the parent
  /// and masks hidden formats.
  String _displayValue(models.Record r) {
    var rec = r;
    if (r.isAlias) {
      final parent = _recordById(r.aliasOf ?? '');
      if (parent != null) rec = parent;
    }
    if (rec.isHidden) return '••••••••';
    return rec.value.isEmpty ? '—' : rec.value;
  }

  /// Bottom sheet to link any vault record into a field. If its key differs
  /// from the requested one the backend creates an alias on submit, so the
  /// responder's data stays in a single place and updates flow through.
  Future<void> _openVaultPicker(RequestTemplateItem item) async {
    await showAppSheet(
      context: context,
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxs,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Use a vault entry for "${item.label}"').header,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Pick one of your records. If its key differs from "${item.key}", '
                'an alias forwards it to this field — your data stays in one '
                'place and edits flow through automatically.',
              ).muted.small,
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: _store.responderVault.isEmpty
                    ? const Text('Your vault has no records yet.').muted.small
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final r in _store.responderVault)
                            AppTile(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              title: Text(r.label.isEmpty ? r.key : r.label),
                              subtitle: Text(
                                '${r.key}${r.key == item.key ? ' · exact match' : ''}  ·  ${_displayValue(r)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ).muted.small,
                              onTap: () {
                                runInAction(() {
                                  _store.publicLinked[item.key] = r.id;
                                  _store.publicExcluded.remove(item.key);
                                });
                                Navigator.of(sheetCtx).pop();
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Editable key/value pair for the "Add field" extras.
class _ExtraField {
  final ObservableTextController keyCtrl = ObservableTextController();
  final ObservableTextController valueCtrl = ObservableTextController();
  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

/// A compact, hoverable info pill used across the request's info panel — one
/// consistent design for the requester, trust, security requirements and
/// status. The trailing dot hints that hovering (or long-pressing on touch)
/// reveals the [tooltip].
class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? accent;

  const _InfoTag({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: AppBadge(
        icon: icon,
        label: label,
        variant: AppBadgeVariant.outline,
        accent: accent,
      ),
    );
  }
}

/// A tappable pill that toggles whether an optional field is forwarded — a
/// connected link icon when sharing, a cut link when not.
class _ShareToggle extends StatelessWidget {
  final bool shared;
  final VoidCallback onTap;

  const _ShareToggle({required this.shared, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: AppRadius.allPill,
      onTap: onTap,
      child: AppBadge(
        icon: shared ? AppIcons.link : AppIcons.linkSlash,
        label: shared ? 'Sharing' : 'Not shared',
        accent: shared ? scheme.primary : null,
      ),
    );
  }
}
