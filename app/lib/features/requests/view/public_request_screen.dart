import 'dart:async';

import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/models/request_template.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';

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

  const PublicRequestScreen({super.key, required this.requestSlug});

  @override
  State<PublicRequestScreen> createState() => _PublicRequestScreenState();
}

class _PublicRequestScreenState extends State<PublicRequestScreen> {
  static final _keyPattern = RegExp(r'^[a-z0-9_-]+$');

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _success = false;

  Map<String, dynamic>? _probe;
  List<RequestTemplateItem> _template = const [];
  AppErrorMessage? _terminalError;
  String? _formError;

  /// Result of DomainVerificationService against the probe's server
  /// claim. Null while the lookup is in flight; populated even on
  /// failure so the badge can explain *why* it failed.
  TrustVerdict? _trustVerdict;

  /// The in-flight domain check, so a submit can wait for it.
  Future<void>? _trustCheck;
  bool _verifyingTrust = false;

  final _senderNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();

  /// Per-template-entry controllers, keyed by the entry's server id.
  final Map<String, TextEditingController> _templateCtrls = {};

  /// Optional / extra fields keyed by a synthetic uuid.
  final List<_ExtraField> _extraFields = [];

  /// The signed-in responder's vault records (empty for guests). Powers
  /// key-match prefill and the "use a vault entry" alias picker.
  List<models.Record> _vaultRecords = const [];

  /// templateKey → linked vault record id. A linked field forwards a living
  /// reference (the server aliases it when the keys differ) instead of a copy.
  final Map<String, String> _linked = {};

  /// Optional templateKeys the responder chose NOT to forward.
  final Set<String> _excluded = {};

  /// The responder's existing response link for this request, if any — so we
  /// can show "already responded" and update it in place instead of duplicating.
  Map<String, dynamic>? _existingLink;

  /// The identity the responder signs with when the request requires a verified
  /// identity. Defaults to the primary, or a root-issued one when the request
  /// is restricted to this server's root.
  String? _selectedIdentityId;

  @override
  void initState() {
    super.initState();
    _probeRequest();
  }

  @override
  void dispose() {
    _senderNameCtrl.dispose();
    _passwordCtrl.dispose();
    _identifierCtrl.dispose();
    for (final c in _templateCtrls.values) {
      c.dispose();
    }
    for (final f in _extraFields) {
      f.dispose();
    }
    super.dispose();
  }

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
    setState(() {
      _isLoading = true;
      _terminalError = null;
    });
    try {
      _probe = await Stores.requests.getPublicRequestProbe(widget.requestSlug);
      _template = RequestsStore.parseTemplateFromProbe(_probe!);
      _templateCtrls
        ..clear()
        ..addEntries(
          _template
              .where((t) => t.isRecord)
              .map((t) => MapEntry(t.key, TextEditingController())),
        );
      await _prefillFromVault();
      setState(() => _isLoading = false);
      // Fire-and-forget the trust verification so the form is usable
      // while DNS is in flight. The submit button defers to the verdict
      // once it lands.
      _trustCheck = _verifyTrust();
      unawaited(_trustCheck!);
    } on ApiException catch (e) {
      setState(() {
        _terminalError = AppErrorMessage.fromException(e);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _terminalError = AppErrorMessage.fromException(e);
        _isLoading = false;
      });
    }
  }

  /// When signed in, pull the responder's vault and auto-link any field whose
  /// key already exists — so the value is prefilled and forwarded as a living
  /// reference rather than re-typed.
  Future<void> _prefillFromVault() async {
    if (!Stores.auth.isAuthenticated) return;
    try {
      await Stores.vault.loadRecords();
      _vaultRecords = Stores.vault.records.toList();
      await Stores.identities.loadIdentities();
      _initSelectedIdentity();
      for (final item in _template.where((t) => t.isRecord)) {
        final match = _matchVaultRecord(item.key);
        if (match != null) _linked[item.key] = match.id;
      }

      // Already answered this request? Surface it and prefill from the existing
      // grant so re-submitting updates in place instead of creating a duplicate.
      final requestId = _probe?['requestId'] as String? ?? '';
      if (requestId.isNotEmpty) {
        final existing = await Stores.requests.getMyLinkForRequest(requestId);
        if (existing != null &&
            (existing['status'] as String? ?? '') != 'revoked') {
          _existingLink = existing;
          final grants = existing['grants'];
          if (grants is Map) {
            grants.forEach((k, v) {
              if (v is String && v.isNotEmpty) _linked[k.toString()] = v;
            });
          }
        }
      }
    } catch (_) {
      // Vault / existing-link lookups are conveniences; ignore failures.
    }
  }

  Map<String, dynamic>? get _requester {
    final r = _probe?['requester'];
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
    return _trustVerdict ??
        TrustVerdict.unverified(
          domain: _serverDomain,
          reason:
              'The requester\'s domain could not be checked, so nothing '
              'confirms this request comes from who it claims to.',
        );
  }

  Future<void> _verifyTrust() async {
    final probe = _probe;
    if (probe == null) return;
    final server = probe['server'];
    final requester = _requester;
    final domain = server is Map<String, dynamic>
        ? (server['domain'] as String? ?? '')
        : '';
    final fingerprint = requester?['fingerprint'] as String? ?? '';
    final parentSig = requester?['parentSignature'] as String? ?? '';

    setState(() => _verifyingTrust = true);
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
    setState(() {
      _trustVerdict = verdict;
      _verifyingTrust = false;
    });
  }

  bool get _requiresPassword => _probe?['requiresPassword'] as bool? ?? false;
  bool get _requireHandshake => _probe?['requireHandshake'] as bool? ?? false;
  bool get _allowExtraFields => _probe?['allowExtraFields'] as bool? ?? false;
  bool get _hasIdentifier => _probe?['requiresIdentifier'] as bool? ?? false;

  /// 'any' (default) or 'from_root' — which identities the request accepts.
  String get _identityScope => _probe?['identityScope'] as String? ?? 'any';

  /// The requester's server (root) domain, from the probe.
  String get _serverDomain {
    final s = _probe?['server'];
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
      if (i.id == _selectedIdentityId) return i.domainAtIssue == _serverDomain;
    }
    return true; // no match → defer to the identity/auth checks
  }

  /// Picks a sensible default identity: a root-issued one when the request is
  /// root-restricted, otherwise the primary (falling back to the first).
  void _initSelectedIdentity() {
    final ids = Stores.identities.identities;
    if (ids.isEmpty) {
      _selectedIdentityId = null;
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
    _selectedIdentityId =
        (rootOnly ? rootPick : null) ?? primaryPick ?? firstId;
  }

  Future<void> _submit() async {
    if (_probe == null) return;

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
        setState(() => _formError = 'Submission blocked: ${verdict.reason}');
        return;
      }
      if (verdict.state != TrustState.verified &&
          !await _confirmUnverifiedSubmit(verdict)) {
        return;
      }
    }

    if (_requiresPassword && _passwordCtrl.text.trim().isEmpty) {
      setState(() => _formError = 'Password is required.');
      return;
    }
    if (_hasIdentifier && _identifierCtrl.text.trim().isEmpty) {
      setState(() => _formError = 'Identifier is required.');
      return;
    }
    if (_requireHandshake && !_selectedIdentityQualifies()) {
      setState(
        () => _formError =
            'This request only accepts identities issued by '
            '${_serverDomain.isEmpty ? 'this server' : _serverDomain}. '
            'Pick a different identity.',
      );
      return;
    }

    // Required template fields must be satisfied — either linked to a vault
    // entry or typed in. (Required fields can't be stripped.)
    for (final item in _template.where((t) => t.isRecord && t.required)) {
      if (_linked.containsKey(item.key)) continue;
      final ctrl = _templateCtrls[item.key];
      if (ctrl?.text.trim().isEmpty ?? true) {
        setState(
          () => _formError = 'Required field "${item.label}" cannot be empty.',
        );
        return;
      }
    }

    // Extras must match the slug regex if the responder added any.
    for (final f in _extraFields) {
      final k = f.keyCtrl.text.trim();
      if (k.isEmpty) continue;
      if (!_keyPattern.hasMatch(k)) {
        setState(
          () => _formError =
              'Extra field key "$k" must use lowercase letters, digits, '
              'underscores or hyphens only.',
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final data = <String, dynamic>{};
    final mappings = <String, String>{};
    for (final item in _template.where((t) => t.isRecord)) {
      if (_excluded.contains(item.key)) continue; // responder stripped it
      final linkedId = _linked[item.key];
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

    try {
      final stored = await _loadStoredHandshake();
      String? guestCert;
      SignedChallenge? challenge;

      // In handshake mode, sign a fresh challenge every time. The stored token
      // (if any) is still sent as a fast-path, but always signing means a lost
      // or stale token can't lock the responder out — the signature alone
      // re-establishes the handshake on the server.
      final identityId = _requireHandshake
          ? (_selectedIdentityId ?? Stores.identities.primaryIdentity?.id)
          : null;
      if (_requireHandshake) {
        if (identityId == null || identityId.isEmpty) {
          setState(() {
            _formError =
                'This request requires authentication. Sign in and create an identity first.';
            _isSubmitting = false;
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
          commonName: _senderNameCtrl.text.trim().isEmpty
              ? 'guest-${widget.requestSlug}'
              : _senderNameCtrl.text.trim(),
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
        password: _passwordCtrl.text.trim().isEmpty
            ? null
            : _passwordCtrl.text.trim(),
        identifier: _identifierCtrl.text.trim().isEmpty
            ? null
            : _identifierCtrl.text.trim(),
        handshakeToken: stored,
        identityId: identityId,
        challengeNonce: challenge?.nonce,
        challengeSignature: challenge?.signature,
        guestCertificate: guestCert,
        senderName: _senderNameCtrl.text.trim().isEmpty
            ? null
            : _senderNameCtrl.text.trim(),
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
      setState(() {
        _success = true;
        _isSubmitting = false;
      });
      AppToast.success(
        context,
        _existingLink != null ? 'Response updated' : 'Submitted',
      );
    } on ApiException catch (e) {
      debugPrint(
        '[request submit] ApiException ${e.statusCode} ${e.code}: ${e.message}',
      );
      final msg = AppErrorMessage.fromException(e);
      if (!mounted) return;
      setState(() {
        if (msg.isTerminal) {
          _terminalError = msg;
        } else {
          _formError = msg.description;
        }
        _isSubmitting = false;
      });
    } catch (e, st) {
      debugPrint('[request submit] error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  const SizedBox(width: AppSpacing.xxs),
                  const Text('Revoked').header,
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
    if (_isLoading) {
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
    if (_terminalError != null && _terminalError!.isTerminal) {
      return _buildTerminal(theme, _terminalError!);
    }
    if (_success) {
      return _buildSuccess(theme);
    }
    if (_probe == null) {
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
    final label = _probe!['label'] as String? ?? 'Data request';

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

    final templateRecords = _template.where((t) => t.isRecord).toList();
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
      if (_existingLink != null)
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.shieldCheck, color: scheme.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label).header),
            ],
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Requested by').muted.small,
            const SizedBox(height: AppSpacing.xxs),
            Text(domain.isEmpty ? name : '$name ($domain)').small,
            if (shortFp.isNotEmpty) Text(shortFp).muted.mono.small,
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 8, runSpacing: 8, children: tags),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Fill out the requested fields. Your submission is private to the '
            'requester, and you can revoke it at any time.',
          ).muted.small,
          if (_existingLink != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                icon: AppIcons.xCircle,
                label: 'Revoke my response',
                style: AppButtonStyle.destructive,
                size: AppButtonSize.small,
                onTap: _revokeExisting,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The DNS trust verdict rendered as one of the info tags, for consistency
  /// with everything else in the panel.
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
    if (_verifyingTrust && _trustVerdict == null) {
      return const _InfoTag(
        icon: AppIcons.arrowRepeat,
        label: 'Checking domain…',
        tooltip: 'Verifying the requester\'s domain against public DNS.',
      );
    }
    final v = _trustVerdict;
    if (v == null) {
      return const _InfoTag(
        icon: AppIcons.shieldCheck,
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
          accent: scheme.error,
          tooltip: v.reason,
        );
      case TrustState.dnsMissing:
      case TrustState.unverified:
        return _InfoTag(
          icon: AppIcons.exclamation,
          label: 'Unverified domain',
          tooltip: v.reason,
        );
    }
  }

  /// Left-hand (or bottom, on mobile) panel: everything the responder fills in.
  Widget _buildInputPanel(ThemeData theme) {
    final templateRecords = _template.where((t) => t.isRecord).toList();
    final allowExtras = _allowExtraFields;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your response').header,
          const SizedBox(height: AppSpacing.xxs),
          const Text('Only the requester can see what you submit.').muted.small,
          const SizedBox(height: AppSpacing.lg),

          if (_requiresPassword || _hasIdentifier) ...[
            _accessInputs(theme),
            const SizedBox(height: AppSpacing.lg),
          ],

          if (_requireHandshake) ...[
            _buildIdentityPicker(theme),
            const SizedBox(height: AppSpacing.lg),
          ],

          const Text('Your name (optional)').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(controller: _senderNameCtrl, hint: 'Anonymous'),

          if (templateRecords.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Requested information').small,
            const SizedBox(height: AppSpacing.sm),
            ...templateRecords.map((item) => _buildTemplateField(theme, item)),
          ],

          if (allowExtras) ...[
            const SizedBox(height: AppSpacing.xxs),
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
                      child: AppTextField(
                        controller: f.valueCtrl,
                        hint: 'Value',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    AppButton(
                      icon: AppIcons.x,
                      tooltip: 'Remove field',
                      style: AppButtonStyle.accent,
                      onTap: () => setState(() {
                        _extraFields[i].dispose();
                        _extraFields.removeAt(i);
                      }),
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
                onTap: () => setState(() => _extraFields.add(_ExtraField())),
              ),
            ),
          ],

          if (_formError != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _inlineError(_formError!),
          ],

          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              icon: AppIcons.send,
              label: _existingLink != null
                  ? 'Update response'
                  : 'Submit response',
              busy: _isSubmitting,
              onTap: _submit,
            ),
          ),
        ],
      ),
    );
  }

  /// Access gates the responder must satisfy (password / identifier). These are
  /// inputs, so they live with the form rather than the info panel.
  Widget _accessInputs(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_requiresPassword) ...[
          const Text('Password').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _passwordCtrl,
            obscureText: true,
            hint: 'Password the requester gave you',
          ),
          if (_hasIdentifier) const SizedBox(height: AppSpacing.md),
        ],
        if (_hasIdentifier) ...[
          const Text('Identifier').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _identifierCtrl,
            hint: 'Identifier the requester gave you',
          ),
          if (!_requireHandshake) ...[
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'A one-time identity is generated on this device to sign your '
              'submission — no account needed.',
            ).muted.small,
          ],
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
    final id = _existingLink?['id'] as String?;
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
      setState(() => _existingLink = null);
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
      iconColor: Theme.of(context).colorScheme.warning,
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
    final identities = Stores.identities.identities;
    final rootOnly = _identityScope == 'from_root';
    final domainLabel = _serverDomain.isEmpty ? 'this server' : _serverDomain;

    if (identities.isEmpty) {
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
                    ? 'This request needs a verified identity. Create one in Account → Identities.'
                    : 'This request needs a verified identity. Sign in and create one to respond.',
              ).muted.small,
            ),
          ],
        ),
      );
    }

    // A single identity isn't a choice — show it read-only instead of a picker.
    if (identities.length == 1) {
      final only = identities.first;
      final bad = rootOnly && only.domainAtIssue != _serverDomain;
      final note = bad ? 'other server' : (only.isPrimary ? 'primary' : '');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Signing as').small,
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: AppRadius.allMd,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(AppIcons.shieldCheck, size: 16, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    only.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small,
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  bad ? Text('· $note').small : Text('· $note').muted.small,
                ],
              ],
            ),
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

    final ids = identities.map((i) => i.id).toList();
    final value = ids.contains(_selectedIdentityId)
        ? _selectedIdentityId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sign as').small,
        const SizedBox(height: AppSpacing.xs),
        AppSelect<String>(
          value: value,
          placeholder: 'Choose an identity',
          items: [
            for (final i in identities)
              AppSelectItem(
                i.id,
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        i.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small,
                    ),
                    if (rootOnly && i.domainAtIssue != _serverDomain) ...[
                      AppSpacing.gapSm,
                      const Text('· other server').small,
                    ] else if (i.isPrimary) ...[
                      AppSpacing.gapSm,
                      const Text('· primary').muted.small,
                    ],
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _selectedIdentityId = v),
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
      return TextEditingController();
    });
    final linkedId = _linked[item.key];
    final linked = linkedId == null ? null : _recordById(linkedId);
    final excluded = _excluded.contains(item.key);
    final canUseVault = Stores.auth.isAuthenticated && _vaultRecords.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  onTap: () => setState(() {
                    if (excluded) {
                      _excluded.remove(item.key);
                    } else {
                      _excluded.add(item.key);
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
              onTap: () => setState(() => _linked.remove(item.key)),
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
            onTap: () => setState(() => _excluded.remove(item.key)),
          ),
        ],
      ),
    );
  }

  models.Record? _recordById(String id) {
    for (final r in _vaultRecords) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// First vault record whose key equals [key], preferring a value-carrier
  /// (non-alias) over an alias.
  models.Record? _matchVaultRecord(String key) {
    models.Record? alias;
    for (final r in _vaultRecords) {
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
                child: _vaultRecords.isEmpty
                    ? const Text('Your vault has no records yet.').muted.small
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final r in _vaultRecords)
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
                                setState(() {
                                  _linked[item.key] = r.id;
                                  _excluded.remove(item.key);
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
  final TextEditingController keyCtrl = TextEditingController();
  final TextEditingController valueCtrl = TextEditingController();
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
