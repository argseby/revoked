import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/identity_status_assertion.dart';
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
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/requirement_list.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
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
///   3. Submission flow — always as a signed-in account on the request's
///      server, so the response link lands in the responder's workspace
///      where they can update or revoke it:
///        - requireHandshake → the responder additionally proves their
///          workspace identity (signed challenge against the identities
///          collection, persistent X-Handshake-Token returned).
///        - otherwise the session JWT alone carries the submission.
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
    // The link names its server, and neither DNS hop needs anything
    // from the probe - so start them now, alongside it.
    if (widget.origin != null) {
      Stores.domainVerification.prewarm(
        Uri.tryParse('https://${widget.origin!}')?.host ?? '',
      );
    }
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

    // Seed from the stored verdict so the form renders at once; the fresh
    // check runs regardless and the submit gate waits on that one.
    final cached = Stores.domainVerification.cachedVerdict(
      claimedDomain: domain,
      identityFingerprint: fingerprint,
    );
    if (cached != null) {
      runInAction(() => _store.publicTrustVerdict = cached);
    }
    runInAction(() => _store.isVerifyingTrust = true);
    TrustVerdict verdict;
    try {
      verdict = await Stores.domainVerification.verify(
        claimedDomain: domain,
        identityFingerprint: fingerprint,
        parentSignatureHex: parentSig,
        statusAssertion: IdentityStatusAssertion.fromJson(
          requester?['statusAssertion'],
        ),
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

  /// True while the first verdict is still outstanding. Sending is the
  /// only thing that waits on it.
  bool get _verificationPending =>
      !_isLocalServer &&
      _store.isVerifyingTrust &&
      _store.publicTrustVerdict == null;

  /// The chain, one row per link: who signed, whether DNS stands behind the
  /// domain they claim, and whether this link even points at that server.
  List<TrustCheck> _trustChecks() {
    if (_isLocalServer) {
      return const [
        TrustCheck(
          label: 'Server',
          value: 'local server',
          state: TrustCheckState.verified,
          detail: 'Local/development server; public DNS does not apply.',
        ),
      ];
    }

    final verdict = _store.publicTrustVerdict;
    final checking = _store.isVerifyingTrust && verdict == null;
    final domain = _serverDomain.isEmpty ? 'no domain declared' : _serverDomain;

    final TrustCheckState chainState;
    if (checking) {
      chainState = TrustCheckState.checking;
    } else if (verdict?.state == TrustState.verified) {
      chainState = TrustCheckState.verified;
    } else if (verdict?.state == TrustState.spoofed) {
      chainState = TrustCheckState.spoofed;
    } else if (verdict?.state == TrustState.revoked) {
      chainState = TrustCheckState.revoked;
    } else {
      chainState = TrustCheckState.failed;
    }

    final fp = _requester?['fingerprint'] as String? ?? '';
    final shortFp = fp.length > 16 ? '${fp.substring(0, 8)}…' : fp;
    final name = _requester?['name'] as String? ?? '';

    return [
      TrustCheck(
        label: 'Server domain',
        value: domain,
        state: chainState,
        detail: checking ? null : verdict?.reason,
      ),
      TrustCheck(
        label: 'Requester identity',
        value: name.isEmpty ? shortFp : '$name · $shortFp',
        state: chainState,
        detail: chainState == TrustCheckState.verified
            ? 'Signed by the key that domain publishes in DNS.'
            : null,
      ),
      if (widget.origin != null)
        TrustCheck(
          label: 'Link origin',
          value: widget.origin!,
          state: checking
              ? TrustCheckState.checking
              : Uri.tryParse('https://${widget.origin!}')?.host == _serverDomain
              ? chainState
              : TrustCheckState.failed,
          detail:
              Uri.tryParse('https://${widget.origin!}')?.host == _serverDomain
              ? null
              : 'The link points at a different server than the sender '
                    'claims to be.',
        ),
    ];
  }

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

      // allowsSubmit rather than a state comparison: it is the one predicate
      // that decides this, and a gate spelling out its own list drifts from it
      // the moment a state is added — which is exactly how a revoked identity
      // came to be offered a confirm-anyway dialog instead of a block.
      if (!verdict.allowsSubmit) {
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

    try {
      final stored = await _loadStoredHandshake();
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
    final label = _store.publicProbe?['label'] as String? ?? '';
    final filling =
        !_store.isLoadingPublic &&
        !(_store.publicTerminalError?.isTerminal ?? false) &&
        !_store.publicSuccess &&
        _store.publicProbe != null &&
        !_isForeign &&
        Stores.auth.isAuthenticated;

    final fields = _store.publicTemplate.where((t) => t.isRecord).length;
    return AppFlowScaffold(
      title: label.isEmpty ? 'Data request' : label,
      subtitle: [
        'Data request',
        if (fields > 0) '$fields ${fields == 1 ? 'field' : 'fields'}',
        if (_store.publicExistingLink != null) 'already answered',
      ].join(' · '),
      closeLabel: 'Close',
      onClose: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.vault);
        }
      },
      // Which account and workspace the answer is given as, with a switcher.
      actions: [if (Stores.auth.isAuthenticated) const WorkspaceChip()],
      bottomBar: filling ? _submitBar() : null,
      body: _buildBody(theme),
    );
  }

  /// The one action of the form, pinned to the bottom. It waits for the
  /// sender check, and says so on the button itself.
  Widget _submitBar() {
    return AppActionBar(
      note: const Text(
        'Only the requester sees what you send, and you can revoke it at any '
        'time.',
      ).muted.small,
      children: [
        if (_verificationPending)
          const AppButton(
            icon: AppIcons.shieldCheck,
            label: 'Verifying the sender…',
            onTap: null,
          )
        else
          AppButton(
            icon: AppIcons.send,
            label: _store.publicExistingLink != null
                ? 'Update response'
                : 'Submit response',
            busy: _store.isSubmittingPublic,
            onTap: _submit,
          ),
      ],
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
            const Text('Loading the request…').muted,
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
          title: 'Couldn’t load the request',
          description: 'Please try again in a moment.',
          code: '',
        ),
      );
    }
    // Responding requires an account on the request's server: the answer is
    // minted as a link in the responder's workspace, where they can update
    // or revoke it later. Without one there is nothing to hold their side
    // of the grant.
    if (_isForeign || !Stores.auth.isAuthenticated) {
      return _buildAccountGate(theme);
    }
    return _buildForm(theme);
  }

  Widget _buildAccountGate(ThemeData theme) {
    return AppStatusMessage(
      icon: AppIcons.personBoundingBox,
      title: 'Sign in to respond',
      message: _isForeign
          ? 'This request lives on ${widget.origin}. Your answer is kept as a '
                'revocable link in your account there, so please sign in with '
                'an account on that server to respond.'
          : 'Your answer is kept in your account as a revocable link, so you '
                'can update or withdraw it at any time. Please sign in to '
                'respond.',
      actions: [
        AppButton(
          icon: AppIcons.boxArrowInRight,
          label: 'Sign in',
          onTap: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }

  Widget _buildTerminal(ThemeData theme, AppErrorMessage msg) {
    return AppStatusMessage(
      icon: AppIcons.exclamationOctagon,
      accent: theme.colorScheme.error,
      title: msg.title,
      message: msg.description,
      actions: [
        AppButton(
          icon: AppIcons.arrowClockwise,
          label: 'Try again',
          style: AppButtonStyle.accent,
          onTap: _probeRequest,
        ),
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return AppStatusMessage(
      icon: AppIcons.checkCircle,
      accent: theme.colorScheme.success,
      title: 'Your response was sent',
      message:
          'The requester has been notified. Your answer is kept as a link in '
          'your account, where you can update or revoke it at any time.',
      actions: [
        AppButton(
          icon: AppIcons.check,
          label: 'Done',
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.vault),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    // Side by side on a wide window: what you fill in, and who is asking.
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final info = _buildInfoPanel(theme);
    final input = _buildInputPanel(theme);
    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: input),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 2, child: info),
            ],
          )
        else ...[
          info,
          input,
        ],
      ],
    );
  }

  /// Who is asking, what it takes to answer, and an earlier answer to revoke.
  Widget _buildInfoPanel(ThemeData theme) {
    // Live status per gate: whether THIS responder can pass it right now.
    // Green needs nothing, grey is a field still to fill, red names whose
    // problem it is - the sender's restriction or the reader's account.
    // The account gate runs before this panel, so the responder is always
    // signed in on this server by the time it renders.
    final hasIdentities = Stores.identities.identities.isNotEmpty;
    final hasRootIdentity = Stores.identities.identities.any(
      (i) => i.domainAtIssue == _serverDomain,
    );

    final requirements = <RequirementItem>[
      if (_requireHandshake)
        RequirementItem(
          icon: AppIcons.personBoundingBox,
          title: 'Verified identity',
          status: hasIdentities
              ? RequirementStatus.ready
              : RequirementStatus.blocked,
          description: hasIdentities
              ? 'Your response is signed with your identity, so the '
                    'requester knows it came from you.'
              : 'You don’t have an identity yet. Create one under Account '
                    'before you respond.',
        ),
      if (_requireHandshake && _identityScope == 'from_root')
        RequirementItem(
          icon: AppIcons.server,
          title:
              'Identity issued by '
              '${_serverDomain.isEmpty ? 'this server' : _serverDomain}',
          status: hasRootIdentity
              ? RequirementStatus.ready
              : RequirementStatus.blocked,
          description: hasRootIdentity
              ? 'One of your identities was issued by that server.'
              : 'None of your identities was issued by that server, so this '
                    'request can’t accept them.',
        ),
      if (_hasIdentifier)
        RequirementItem(
          icon: AppIcons.tag,
          title: 'Identifier',
          status: _store.responderIdentifier.text.trim().isNotEmpty
              ? RequirementStatus.ready
              : RequirementStatus.pending,
          description: _store.responderIdentifier.text.trim().isNotEmpty
              ? 'Entered. The server checks it when you submit.'
              : 'Enter the identifier the requester gave you, exactly as '
                    'written.',
        ),
      if (_requiresPassword)
        RequirementItem(
          icon: AppIcons.lock,
          title: 'Password',
          status: _store.responderPassword.text.isNotEmpty
              ? RequirementStatus.ready
              : RequirementStatus.pending,
          description: _store.responderPassword.text.isNotEmpty
              ? 'Entered. The server checks it when you submit.'
              : 'You need the password the requester gave you to submit.',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Requester', [TrustPanel(checks: _trustChecks())]),
        if (requirements.isNotEmpty)
          _section('To respond', [RequirementList(items: requirements)]),
        if (_store.publicExistingLink != null)
          AppListGroup(
            title: 'Your earlier answer',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'Submitting again updates it in place, so no duplicate is '
              'created.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.checkCircle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    AppSpacing.gapMd,
                    const Expanded(child: Text('You already answered this')),
                    AppButton(
                      icon: AppIcons.xCircle,
                      label: 'Revoke my response',
                      style: AppButtonStyle.destructive,
                      size: AppButtonSize.small,
                      onTap: _revokeExisting,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Everything the responder fills in, one card per group.
  Widget _buildInputPanel(ThemeData theme) {
    final templateRecords = _store.publicTemplate
        .where((t) => t.isRecord)
        .toList();
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_requiresPassword || _hasIdentifier)
          AppListGroup(
            title: 'Access',
            trailing: const SizedBox.shrink(),
            children: [cell(_accessInputs(theme))],
          ),
        if (_requireHandshake)
          AppListGroup(
            title: 'Signing identity',
            trailing: const SizedBox.shrink(),
            children: [cell(_buildIdentityPicker(theme))],
          ),
        AppListGroup(
          title: 'About you',
          trailing: const SizedBox.shrink(),
          children: [
            cell(
              _field(
                'Your name',
                optional: true,
                child: AppTextField(
                  controller: _store.responderName,
                  hint: 'Anonymous',
                ),
              ),
            ),
          ],
        ),
        if (templateRecords.isNotEmpty)
          AppListGroup(
            title: 'Requested information',
            children: [
              for (final item in templateRecords)
                cell(_buildTemplateField(theme, item)),
            ],
          ),
        if (_allowExtraFields)
          AppListGroup(
            title: 'Anything else',
            trailing: const SizedBox.shrink(),
            children: [cell(_extraFieldRows())],
          ),
        if (_store.publicFormError != null)
          _inlineError(_store.publicFormError!),
      ],
    );
  }

  /// A titled block that holds its own widgets — a panel or a list — rather
  /// than rows in a card.
  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListHeader(title: title),
          ...children,
        ],
      ),
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
      confirmIcon: AppIcons.xCircle,
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
      confirmIcon: AppIcons.send,
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
              child: const Text(
                'This request needs a verified identity. Create one in '
                'Account → Identities.',
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
    final canUseVault = _store.responderVault.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: AppBadge(
                      label: item.key,
                      mono: true,
                      variant: AppBadgeVariant.sunken,
                    ),
                  ),
                  if (item.required) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const AppBadge(
                      label: 'Required',
                      variant: AppBadgeVariant.primary,
                    ),
                  ],
                  if (!item.required) ...[
                    const SizedBox(width: AppSpacing.xs),
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
                ],
              ),
            ),
          ],
        ),
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
          if (canUseVault && _matchVaultRecord(item.key) == null) ...[
            AppSpacing.gapSm,
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
      ],
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
            icon: AppIcons.share,
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
      borderRadius: AppRadius.allMd,
      onTap: onTap,
      child: AppBadge(
        icon: shared ? AppIcons.link : AppIcons.linkSlash,
        label: shared ? 'Sharing' : 'Not shared',
        accent: shared ? scheme.primary : null,
      ),
    );
  }
}
