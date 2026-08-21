import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/core/widgets/requirement_list.dart';
import 'package:revoked_app/core/widgets/identity_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revoked_app/core/files/file_saver.dart';

/// Public link viewer.
///
/// The viewer flow uses the dedicated `/api/public/links/:slug` endpoints
/// (see `cmd/revoked/routes/publicLinks.go`):
///   1. GET → probe. Returns the visible label and which gates apply
///      (password, handshake, expiry).
///   2. POST → submission. Sends password + identity + handshake token,
///      receives the sanitized section/record payload back.
///
/// First-visit handshakes return an `X-Handshake-Token` header; we persist
/// it per slug so return visits can re-authenticate transparently.
class PublicShareScreen extends StatefulWidget {
  final String shareSlug;

  /// host[:port] the link says it lives on; null = the signed-in server.
  final String? origin;

  const PublicShareScreen({super.key, required this.shareSlug, this.origin});

  @override
  State<PublicShareScreen> createState() => _PublicShareScreenState();
}

class _PublicShareScreenState extends State<PublicShareScreen> {
  SharesStore get _store => Stores.shares;

  bool get _requiresHandshake =>
      _store.shareProbe?['requireHandshake'] as bool? ?? false;

  @override
  void initState() {
    super.initState();
    // The store is a singleton, so the previous share's password, payload and
    // revealed values are still in it.
    // The link names its server, and neither DNS hop needs anything
    // from the probe - so start them now, alongside it.
    if (widget.origin != null) {
      Stores.domainVerification.prewarm(
        Uri.tryParse('https://${widget.origin!}')?.host ?? '',
      );
    }
    _store.resetShareView();
    _probeLink();
  }

  bool get _isForeign => !Stores.api.isOwnOrigin(widget.origin);

  String _handshakeKey() => 'handshake_link_${widget.shareSlug}';

  Future<String?> _loadStoredHandshake() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_handshakeKey());
  }

  Future<void> _persistHandshake(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handshakeKey(), token);
  }

  /// Walks the DNS chain over the sharer's signing identity, exactly as the
  /// public request screen does. An unsigned share has nothing to walk, and
  /// says so rather than staying silent.
  /// Whether DNS proved the sharer owns the domain they signed from. An
  /// unsigned share is never proven — there is no claim to check.
  /// The sharer's issuing domain is proven only when the DNS walk verified
  /// that exact domain.
  TrustCheckState _sharerDomainState() {
    final verdict = _store.shareTrustVerdict;
    if (_store.isVerifyingShareTrust && verdict == null) {
      return TrustCheckState.checking;
    }
    final sharer = _store.shareProbe?['sharer'];
    final claimed = sharer is Map
        ? (sharer['domainAtIssue'] as String? ?? '')
        : '';
    if (verdict?.state == TrustState.spoofed) return TrustCheckState.spoofed;
    if (verdict?.state == TrustState.verified && verdict?.domain == claimed) {
      return TrustCheckState.verified;
    }
    return TrustCheckState.failed;
  }

  /// Live status per gate, from the viewer's side of the door.
  List<RequirementItem> _gateRequirements() {
    final requiresPassword =
        _store.shareProbe?['requiresPassword'] as bool? ?? false;
    final hasIdentities = Stores.identities.identities.isNotEmpty;

    return [
      if (requiresPassword)
        RequirementItem(
          icon: AppIcons.lock,
          title: 'Password',
          status: _store.sharePassword.text.isNotEmpty
              ? RequirementStatus.ready
              : RequirementStatus.pending,
          description: _store.sharePassword.text.isNotEmpty
              ? 'Entered - checked by the server on unlock.'
              : 'Enter the password the sender gave you.',
        ),
      if (_requiresHandshake)
        RequirementItem(
          icon: AppIcons.personBoundingBox,
          title: 'Verified identity',
          status: _isForeign
              ? RequirementStatus.blocked
              : _store.shareIdentityId != null
              ? RequirementStatus.ready
              : hasIdentities
              ? RequirementStatus.pending
              : RequirementStatus.blocked,
          description: _isForeign
              ? 'This share lives on a different server than you are signed '
                    'into; cross-server verification is not supported yet.'
              : _store.shareIdentityId != null
              ? 'You verify with this identity; the sender authorized your '
                    'key on a first visit.'
              : hasIdentities
              ? 'Pick the identity to verify with below.'
              : 'You have no identity yet - sign in and create one under '
                    'Account.',
        ),
    ];
  }

  /// One row per link of the chain; an unsigned share is a failed check, not
  /// a blank - absence of a signature is the finding.
  List<TrustCheck> _shareTrustChecks() {
    final sharer = _store.shareProbe?['sharer'];
    final fp = sharer is Map ? (sharer['fingerprint'] as String? ?? '') : '';
    final signed = fp.isNotEmpty;

    if (!signed) {
      return const [
        TrustCheck(
          label: 'Sender identity',
          value: '',
          state: TrustCheckState.failed,
          detail:
              'No identity is attached to this share, so nothing proves who '
              'created it.',
        ),
      ];
    }

    final verdict = _store.shareTrustVerdict;
    final checking = _store.isVerifyingShareTrust && verdict == null;
    final domain = verdict?.domain ?? '';

    final TrustCheckState state;
    if (checking) {
      state = TrustCheckState.checking;
    } else if (verdict?.state == TrustState.verified) {
      state = TrustCheckState.verified;
    } else if (verdict?.state == TrustState.spoofed) {
      state = TrustCheckState.spoofed;
    } else {
      state = TrustCheckState.failed;
    }

    final shortFp = fp.length > 16 ? '${fp.substring(0, 8)}…' : fp;
    return [
      TrustCheck(
        label: 'Server domain',
        value: domain.isEmpty ? 'no domain declared' : domain,
        state: state,
        detail: checking ? null : verdict?.reason,
      ),
      TrustCheck(
        label: 'Sender identity',
        value: shortFp,
        state: state,
        detail: state == TrustCheckState.verified
            ? 'Signed by the key that domain publishes in DNS.'
            : null,
      ),
      if (widget.origin != null)
        TrustCheck(
          label: 'Link origin',
          value: widget.origin!,
          state: checking
              ? TrustCheckState.checking
              : Uri.tryParse('https://${widget.origin!}')?.host == domain
              ? state
              : TrustCheckState.failed,
          detail: Uri.tryParse('https://${widget.origin!}')?.host == domain
              ? null
              : 'The link points at a different server than the sender '
                    'claims to be.',
        ),
    ];
  }

  /// A band across the top for anything unproven, matching the request screen.
  /// Right-hand (or top, on mobile) panel: who shared this and what DNS says
  /// about them. An unsigned share is stated outright — absence of an identity
  /// is the finding, not a blank.
  Widget _buildInfoPanel(ThemeData theme) {
    final scheme = theme.colorScheme;
    final sharer = _store.shareProbe?['sharer'];
    final name = sharer is Map ? (sharer['name'] as String? ?? '') : '';
    final fp = sharer is Map ? (sharer['fingerprint'] as String? ?? '') : '';
    final signed = fp.isNotEmpty;
    final shortFp = fp.length > 16
        ? '${fp.substring(0, 8)}…${fp.substring(fp.length - 8)}'
        : fp;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.shieldLock,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('About this share')),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          const Text('Security').small.muted,
          const SizedBox(height: AppSpacing.sm),
          TrustPanel(checks: _shareTrustChecks()),
          if (signed) ...[
            const SizedBox(height: AppSpacing.xl),
            const Text('Shared by').small.muted,
            const SizedBox(height: AppSpacing.sm),
            IdentitySummaryCard(
              name: name,
              fingerprint: shortFp,
              domain: sharer is Map
                  ? (sharer['domainAtIssue'] as String? ?? '')
                  : '',
              domainState: _sharerDomainState(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _verifyShareTrust() async {
    final probe = _store.shareProbe;
    final sharer = probe?['sharer'];
    if (sharer is! Map || sharer['fingerprint'] == null) {
      _store.finishShareTrust(null);
      return;
    }
    final serverBlock = probe?['server'];
    final domain = serverBlock is Map
        ? (serverBlock['domain'] as String? ?? '')
        : '';

    // Seed from the stored verdict so the gate renders a verdict at once;
    // the fresh check runs regardless and overwrites it when it lands.
    final cached = Stores.domainVerification.cachedVerdict(
      claimedDomain: domain,
      identityFingerprint: sharer['fingerprint'] as String? ?? '',
    );
    _store.startShareTrust();
    if (cached != null) _store.seedShareTrust(cached);
    try {
      final verdict = await Stores.domainVerification.verify(
        claimedDomain: domain,
        identityFingerprint: sharer['fingerprint'] as String? ?? '',
        parentSignatureHex: sharer['parentSignature'] as String? ?? '',
      );
      _store.finishShareTrust(verdict);
    } catch (e) {
      _store.finishShareTrust(
        TrustVerdict.unverified(
          domain: domain,
          reason: 'The domain check could not complete.',
        ),
      );
    }
  }

  Future<void> _probeLink() async {
    runInAction(() {
      _store.isLoadingShare = true;
      _store.shareTerminalError = null;
    });

    try {
      _store.shareProbe = await Stores.shares.getPublicLinkProbe(
        widget.shareSlug,
        origin: widget.origin,
      );
      // A signed share carries the sharer's identity and this server's root
      // claim, so it can walk the same DNS chain a request does. Unawaited:
      // the payload must not wait on DNS.
      unawaited(_verifyShareTrust());
      // If neither password nor handshake is required, auto-submit so the
      // payload loads immediately (no extra tap for the viewer).
      final requiresPassword =
          _store.shareProbe!['requiresPassword'] as bool? ?? false;
      final requireHandshake =
          _store.shareProbe!['requireHandshake'] as bool? ?? false;
      if (!requiresPassword && !requireHandshake) {
        await _unlock();
        return;
      }
      if (requireHandshake && !_isForeign) {
        // Default to the viewer's primary identity so the handshake can sign
        // straight away; they can switch in the gate. Never against a foreign
        // server - it has never seen this device's keys.
        await Stores.identities.loadIdentities();
        _store.shareIdentityId ??= Stores.identities.primaryIdentity?.id;
      }
      runInAction(() => _store.isLoadingShare = false);
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      runInAction(() {
        _store.shareTerminalError = msg;
        _store.isLoadingShare = false;
      });
    } catch (e) {
      runInAction(() {
        _store.shareTerminalError = AppErrorMessage.fromException(e);
        _store.isLoadingShare = false;
      });
    }
  }

  Future<void> _unlock() async {
    runInAction(() {
      _store.isUnlockingShare = true;
      _store.sharePasswordHint = null;
    });

    try {
      final handshake = await _loadStoredHandshake();
      // First contact (no stored token yet) needs a freshly signed
      // challenge so the server can prove the responder controls the
      // identity's private key before issuing a persistent token.
      SignedChallenge? challenge;
      final requireHandshake =
          _store.shareProbe?['requireHandshake'] as bool? ?? false;
      if (requireHandshake &&
          handshake == null &&
          _store.shareIdentityId != null &&
          _store.shareIdentityId!.isNotEmpty) {
        challenge = await Stores.handshake.prepare(
          scope: HandshakeService.scopeLink,
          slug: widget.shareSlug,
          identityId: _store.shareIdentityId!,
        );
      }

      final response = await Stores.shares.submitPublicLink(
        widget.shareSlug,
        password: _store.sharePassword.text.isEmpty
            ? null
            : _store.sharePassword.text,
        handshakeToken: handshake,
        identityId: _store.shareIdentityId,
        challengeNonce: challenge?.nonce,
        challengeSignature: challenge?.signature,
      );

      final newHandshake = response.headers['x-handshake-token'];
      if (newHandshake != null && newHandshake.isNotEmpty) {
        await _persistHandshake(newHandshake);
      }

      runInAction(() {
        _store.shareData = response.body as Map<String, dynamic>;
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      runInAction(() {
        if (msg.isTerminal) {
          _store.shareTerminalError = msg;
        } else {
          _store.sharePasswordHint = msg.description;
        }
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    } catch (e) {
      runInAction(() {
        _store.sharePasswordHint = e.toString();
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH(context),
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
                    style: AppButtonStyle.accent,
                    tooltip: 'Back to app',
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.vault);
                      }
                    },
                  ),
                  AppSpacing.gapXxs,
                  const Spacer(),
                  const AppBadge(
                    label: 'PUBLIC VIEW',
                    variant: AppBadgeVariant.outline,
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
    if (_store.isLoadingShare) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSpinner(large: true),
            AppSpacing.gapMd,
            const Text('Retrieving shared vault…').muted,
          ],
        ),
      );
    }

    if (_store.shareTerminalError != null) {
      return _buildTerminal(theme, _store.shareTerminalError!);
    }

    if (_store.shareData != null) {
      return _buildContent(theme, _store.shareData!);
    }

    // Probe succeeded but gating remains.
    if (_store.shareProbe != null) {
      final requiresPassword =
          _store.shareProbe!['requiresPassword'] as bool? ?? false;
      return _buildPasswordGate(theme, requiresPassword);
    }

    return const SizedBox.shrink();
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
              AppSpacing.gapLg,
              Text(msg.title).header,
              AppSpacing.gapSm,
              Text(msg.description, textAlign: TextAlign.center).muted.small,
              AppSpacing.gapXl,
              AppButton(
                label: 'Try Again',
                style: AppButtonStyle.accent,
                onTap: _probeLink,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordGate(ThemeData theme, bool requiresPassword) {
    final label = _store.shareProbe?['label'] as String? ?? 'Protected share';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.shieldLock,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                  AppSpacing.gapSm,
                  Expanded(child: Text(label).header),
                ],
              ),
              AppSpacing.gapSm,
              // The verdict must be readable before anything is typed in:
              // a password entered into a spoofed share is already lost.
              TrustPanel(checks: _shareTrustChecks()),
              AppSpacing.gapMd,
              RequirementList(items: _gateRequirements()),
              AppSpacing.gapMd,
              if (requiresPassword) ...[
                const Text(
                  'This share is password-protected. Enter the password the sender provided to view its contents.',
                ).muted.small,
                AppSpacing.gapLg,
                AppTextField(
                  controller: _store.sharePassword,
                  obscureText: true,
                  hint: 'Password',
                  onSubmitted: (_) => _unlock(),
                ),
                if (_store.sharePasswordHint != null) ...[
                  AppSpacing.gapXs,
                  Text(_store.sharePasswordHint!).small,
                ],
              ],
              if (_requiresHandshake && _isForeign) ...[
                if (requiresPassword) AppSpacing.gapLg,
                // Identities live on the server that issued them. This link's
                // server has never seen any of this device's keys, so a
                // handshake against it cannot succeed yet.
                const Text(
                  'This share requires a verified identity, and it lives on a '
                  'different server than the one you are signed into. '
                  'Cross-server verification is not supported yet — ask the '
                  'sender for access from their server.',
                ).muted.small,
              ] else if (_requiresHandshake) ...[
                if (requiresPassword) AppSpacing.gapLg,
                const Text(
                  'This share is bound to a cryptographic identity. Pick the '
                  'identity to verify with — the sender authorized your key on '
                  'a first visit.',
                ).muted.small,
                AppSpacing.gapMd,
                IdentityPicker(
                  selectedId: _store.shareIdentityId,
                  onChanged: (v) =>
                      runInAction(() => _store.shareIdentityId = v),
                ),
              ],
              AppSpacing.gapXl,
              AppButton(
                label: 'Unlock',
                busy: _store.isUnlockingShare,
                onTap:
                    (_requiresHandshake &&
                        (_isForeign || _store.shareIdentityId == null))
                    ? null
                    : _unlock,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, Map<String, dynamic> data) {
    final label = data['label'] as String? ?? 'Shared Items';
    final sections = (data['sections'] as List<dynamic>?) ?? [];
    final records = (data['records'] as List<dynamic>?) ?? [];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.share,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  AppSpacing.gapSm,
                  Expanded(child: Text(label).header),
                ],
              ),
              AppSpacing.gapSm,
              const Text(
                'A read-only secure view of shared items from a Revoked vault.',
              ).muted.small,
            ],
          ),
        ),
        AppSpacing.gapXxl,
        if (records.isNotEmpty) ...[
          const Text('Shared Records').header,
          AppSpacing.gapMd,
          ...records.map(
            (r) => _PublicRecordCard(
              record: r as Map<String, dynamic>,
              slug: widget.shareSlug,
              origin: widget.origin,
            ),
          ),
          AppSpacing.gapXxl,
        ],
        if (sections.isNotEmpty) ...[
          const Text('Shared Sections').header,
          AppSpacing.gapMd,
          ...sections.map(
            (s) => _PublicSectionCard(
              section: s as Map<String, dynamic>,
              slug: widget.shareSlug,
              origin: widget.origin,
            ),
          ),
        ],
        if (records.isEmpty && sections.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.gigantic,
              ),
              child: const Text('No items are shared in this link.').muted,
            ),
          ),
      ],
    );

    // Two-pane on a wide window: the shared data on the left, who shared
    // it and what DNS says about them on the right. Stacks when narrow so
    // the provenance still renders before the data.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final info = _buildInfoPanel(theme);
        final Widget body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  const SizedBox(width: AppSpacing.xxl),
                  SizedBox(width: 320, child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: AppSpacing.lg),
                  content,
                ],
              );
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH(context),
            vertical: AppSpacing.xxl,
          ),
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
}

class _PublicSectionCard extends StatelessWidget {
  final Map<String, dynamic> section;
  final String slug;
  final String? origin;

  const _PublicSectionCard({
    required this.section,
    required this.slug,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = section['name'] as String? ?? 'Section';
    final key = section['key'] as String? ?? '';
    // The public endpoint returns section records as IDs the viewer cannot
    // dereference (records are owner-only, by design); render only records the
    // server chose to inline as maps.
    final recordsList = section['records'];
    final List<Map<String, dynamic>> inline = recordsList is List
        ? recordsList.whereType<Map<String, dynamic>>().toList(growable: false)
        : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.folder, color: theme.colorScheme.primary, size: 18),
              AppSpacing.gapSm,
              Text(name).header,
              AppSpacing.gapXs,
              Text('($key)').muted.small.mono,
            ],
          ),
          AppSpacing.gapSm,
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: Column(
              children: inline.isEmpty
                  ? [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          'No records inside this section.',
                        ).muted.small,
                      ),
                    ]
                  : inline
                        .map(
                          (r) => _PublicRecordCard(
                            record: r,
                            slug: slug,
                            origin: origin,
                          ),
                        )
                        .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String slug;
  final String? origin;

  const _PublicRecordCard({
    required this.record,
    required this.slug,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Future<void> _downloadFile(BuildContext context) async {
    final recordId = record['id'] as String? ?? '';
    final token = record['downloadToken'] as String? ?? '';
    final filename = record['filename'] as String? ?? 'file';
    if (recordId.isEmpty || token.isEmpty) {
      AppToast.error(
        context,
        'Download unavailable',
        subtitle: 'Reopen the link to request a new download.',
      );
      return;
    }
    final bytes = await Stores.shares.downloadSharedFile(
      origin: origin,
      slug: slug,
      recordId: recordId,
      token: token,
    );
    if (!context.mounted) return;
    if (bytes == null) {
      AppToast.error(
        context,
        'Could not download file',
        subtitle:
            'The download may have been used already — reopen the link to request a new one.',
      );
      return;
    }
    final ok = await saveFileToDevice(
      bytes: bytes,
      filename: filename,
      mime: record['mime'] as String?,
    );
    if (ok && context.mounted) AppToast.success(context, 'File saved');
  }

  Widget _fileBody(
    BuildContext context, {
    required bool obscured,
    required bool hidden,
  }) {
    final theme = Theme.of(context);
    final recordId = record['id'] as String? ?? '';
    final filename = record['filename'] as String? ?? '';
    final size = (record['size'] as num?)?.toInt() ?? 0;
    final mime = (record['mime'] as String? ?? '').split(';').first;
    final busy = Stores.shares.downloadingShareRecordIds.contains(recordId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.fileText,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Text(
              obscured
                  ? '••••••••••••'
                  : '$filename · ${formatBytes(size)}'
                        '${mime.isEmpty ? '' : ' · $mime'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).mono.small,
          ),
          if (hidden) ...[
            AppSpacing.gapSm,
            AppButton(
              icon: obscured ? AppIcons.eye : AppIcons.eyeSlash,
              tooltip: obscured ? 'Show' : 'Hide',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => Stores.shares.toggleShareValue(
                record['key'] as String? ?? '',
              ),
            ),
          ],
          AppSpacing.gapSm,
          AppButton(
            icon: AppIcons.download,
            label: 'Download',
            size: AppButtonSize.small,
            busy: busy,
            onTap: busy ? null : () => _downloadFile(context),
          ),
        ],
      ),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final label = record['label'] as String? ?? 'Record';
    final key = record['key'] as String? ?? '';
    final value = record['value'] as String? ?? '';
    final type = record['type'] as String? ?? 'text';
    final format = record['format'] as String? ?? 'default';
    final isFile = type == 'file';
    final isHiddenFormat = format == 'hidden';
    final isObscured =
        isHiddenFormat && !Stores.shares.revealedShareValues.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      AppSpacing.gapXxs,
                      Text(key).mono.muted.small,
                    ],
                  ),
                ),
                AppBadge(label: type),
                if (!isFile) ...[
                  AppSpacing.gapSm,
                  AppButton(
                    icon: AppIcons.copy,
                    style: AppButtonStyle.accent,
                    tooltip: 'Copy value',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      AppToast.success(context, 'Copied to clipboard');
                    },
                  ),
                ],
              ],
            ),
            AppSpacing.gapMd,
            if (isFile)
              _fileBody(context, obscured: isObscured, hidden: isHiddenFormat)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.allMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: isObscured
                          ? const Text('••••••••••••••••').mono.small.muted
                          : Text(value).mono.small,
                    ),
                    if (isHiddenFormat) ...[
                      AppSpacing.gapSm,
                      AppButton(
                        icon: isObscured ? AppIcons.eye : AppIcons.eyeSlash,
                        tooltip: isObscured ? 'Show' : 'Hide',
                        style: AppButtonStyle.accent,
                        size: AppButtonSize.small,
                        onTap: () => Stores.shares.toggleShareValue(key),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
