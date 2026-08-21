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
import 'package:revoked_app/core/files/file_saver.dart';
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
import 'package:revoked_app/core/widgets/identity_summary_card.dart';
import 'package:revoked_app/core/widgets/requirement_list.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PublicShareScreen extends StatefulWidget {
  final String shareSlug;
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

  List<RequirementItem> _gateRequirements() {
    final requiresPassword =
        _store.shareProbe?['requiresPassword'] as bool? ?? false;
    final hasIdentities = Stores.identities.identities.isNotEmpty;

    return [
      if (requiresPassword)
        RequirementItem(
          icon: AppIcons.lock,
          title: 'Password Required',
          status: _store.sharePassword.text.isNotEmpty
              ? RequirementStatus.ready
              : RequirementStatus.pending,
          description: _store.sharePassword.text.isNotEmpty
              ? 'Password entered.'
              : 'Enter the password provided by the sender.',
        ),
      if (_requiresHandshake)
        RequirementItem(
          icon: AppIcons.personBoundingBox,
          title: 'Identity Verification',
          status: _isForeign
              ? RequirementStatus.blocked
              : _store.shareIdentityId != null
              ? RequirementStatus.ready
              : hasIdentities
              ? RequirementStatus.pending
              : RequirementStatus.blocked,
          description: _isForeign
              ? 'Cross-server identity verification is not supported yet.'
              : _store.shareIdentityId != null
              ? 'Identity selected.'
              : hasIdentities
              ? 'Select an identity to verify ownership.'
              : 'No identity found on this server.',
        ),
    ];
  }

  List<TrustCheck> _shareTrustChecks() {
    final sharer = _store.shareProbe?['sharer'];
    final fp = sharer is Map ? (sharer['fingerprint'] as String? ?? '') : '';
    final signed = fp.isNotEmpty;

    if (!signed) {
      return const [
        TrustCheck(
          label: 'Sender identity',
          value: 'Unsigned',
          state: TrustCheckState.failed,
          detail: 'No identity is attached to verify the creator.',
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
        value: domain.isEmpty ? 'No domain declared' : domain,
        state: state,
        detail: checking ? null : verdict?.reason,
      ),
      TrustCheck(
        label: 'Sender identity',
        value: shortFp,
        state: state,
        detail: state == TrustCheckState.verified
            ? 'Signed by the key published in DNS.'
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
              : 'Link origin mismatches sender declaration.',
        ),
    ];
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
          reason: 'Domain verification could not complete.',
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
      unawaited(_verifyShareTrust());

      final requiresPassword =
          _store.shareProbe!['requiresPassword'] as bool? ?? false;
      final requireHandshake =
          _store.shareProbe!['requireHandshake'] as bool? ?? false;

      if (!requiresPassword && !requireHandshake) {
        await _unlock();
        return;
      }
      if (requireHandshake && !_isForeign) {
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
                vertical: AppSpacing.md,
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
                    label: 'Exit',
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
                  const AppBadge(
                    label: 'READ-ONLY SHARE',
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
            const Text('Loading secure share…').muted,
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
                size: 40,
              ),
              AppSpacing.gapMd,
              Text(msg.title).header,
              AppSpacing.gapXs,
              Text(msg.description, textAlign: TextAlign.center).muted.small,
              AppSpacing.gapLg,
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
    final label = _store.shareProbe?['label'] as String? ?? 'Protected Share';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppRadius.allMd,
                      ),
                      child: Icon(
                        AppIcons.shieldLock,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    AppSpacing.gapSm,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label).header,
                          const Text('Vault Verification').muted.small,
                        ],
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapLg,
                TrustPanel(checks: _shareTrustChecks()),
                AppSpacing.gapMd,
                RequirementList(items: _gateRequirements()),
                if (requiresPassword) ...[
                  AppSpacing.gapLg,
                  const Text('Enter Share Password').small,
                  AppSpacing.gapXs,
                  AppTextField(
                    controller: _store.sharePassword,
                    obscureText: true,
                    hint: 'Password',
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (_store.sharePasswordHint != null) ...[
                    AppSpacing.gapXs,
                    Text(
                      _store.sharePasswordHint!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ).small,
                  ],
                ],
                if (_requiresHandshake && _isForeign) ...[
                  AppSpacing.gapMd,
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: AppRadius.allMd,
                    ),
                    child: const Text(
                      'This share lives on another server. Cross-server verification is currently not supported.',
                    ).small,
                  ),
                ] else if (_requiresHandshake) ...[
                  AppSpacing.gapMd,
                  const Text('Select Your Identity').small,
                  AppSpacing.gapXs,
                  IdentityPicker(
                    selectedId: _store.shareIdentityId,
                    onChanged: (v) =>
                        runInAction(() => _store.shareIdentityId = v),
                  ),
                ],
                AppSpacing.gapXl,
                AppButton(
                  label: 'Unlock Vault',
                  icon: AppIcons.lock,
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
      ),
    );
  }

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
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.shieldCheck, size: 18, color: scheme.primary),
              AppSpacing.gapSm,
              const Text('Share Provenance').header,
            ],
          ),
          AppSpacing.gapMd,
          TrustPanel(checks: _shareTrustChecks()),
          if (signed) ...[
            AppSpacing.gapLg,
            const Text('Sharer Details').muted.small,
            AppSpacing.gapSm,
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

  Widget _buildContent(ThemeData theme, Map<String, dynamic> data) {
    final label = data['label'] as String? ?? 'Shared Items';
    final rawSections = (data['sections'] as List<dynamic>?) ?? [];
    final rawRecords = (data['records'] as List<dynamic>?) ?? [];

    final records = rawRecords.whereType<Map<String, dynamic>>().toList();
    final sections = rawSections.whereType<Map<String, dynamic>>().toList();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: AppRadius.allMd,
                ),
                child: Icon(
                  AppIcons.folder,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label).header,
                    AppSpacing.gapXxs,
                    const Text('Read-only items shared with you.').muted.small,
                  ],
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        if (records.isNotEmpty) ...[
          _RecordGroupCard(
            title: 'General Records',
            icon: AppIcons.fileText,
            records: records,
            slug: widget.shareSlug,
            origin: widget.origin,
          ),
          AppSpacing.gapLg,
        ],

        if (sections.isNotEmpty) ...[
          ...sections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _PublicSectionCard(
                section: s,
                slug: widget.shareSlug,
                origin: widget.origin,
              ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 940;
        final info = _buildInfoPanel(theme);

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH(context),
            vertical: AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1120 : 680),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: content),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(flex: 4, child: info),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        info,
                        const SizedBox(height: AppSpacing.lg),
                        content,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _RecordGroupCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Map<String, dynamic>> records;
  final String slug;
  final String? origin;

  const _RecordGroupCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.records,
    required this.slug,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                AppSpacing.gapSm,
                Expanded(
                  child: Row(
                    children: [
                      Text(title).header,
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        AppSpacing.gapXs,
                        Text(subtitle!).muted.small.mono,
                      ],
                    ],
                  ),
                ),
                AppBadge(
                  label:
                      '${records.length} ${records.length == 1 ? 'item' : 'items'}',
                  variant: AppBadgeVariant.outline,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: const Text('No records inside this section.').muted.small,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return _PublicRecordRow(
                  record: records[index],
                  slug: slug,
                  origin: origin,
                );
              },
            ),
        ],
      ),
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
    final name = section['name'] as String? ?? 'Section';
    final key = section['key'] as String? ?? '';
    final recordsList = section['records'];
    final List<Map<String, dynamic>> inline = recordsList is List
        ? recordsList.whereType<Map<String, dynamic>>().toList(growable: false)
        : <Map<String, dynamic>>[];

    return _RecordGroupCard(
      title: name,
      subtitle: key.isNotEmpty ? '($key)' : null,
      icon: AppIcons.folder,
      records: inline,
      slug: slug,
      origin: origin,
    );
  }
}

class _PublicRecordRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final String slug;
  final String? origin;

  const _PublicRecordRow({
    required this.record,
    required this.slug,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _buildRow(context));
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
        subtitle: 'The download token may have expired or been used.',
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

  Widget _buildRow(BuildContext context) {
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
    final size = (record['size'] as num?)?.toInt() ?? 0;
    final mime = (record['mime'] as String? ?? '').split(';').first;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              AppSpacing.gapSm,
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (key.isNotEmpty) ...[
                      Flexible(
                        child: AppBadge(
                          label: key,
                          mono: true,
                          variant: AppBadgeVariant.sunken,
                        ),
                      ),
                      AppSpacing.gapXs,
                    ],
                    if (isFile) ...[
                      AppBadge(label: formatBytes(size)),
                      AppSpacing.gapXs,
                      if (mime.isNotEmpty) ...[
                        AppBadge(label: mime),
                        AppSpacing.gapXs,
                      ],
                    ],
                    AppBadge(label: type.toUpperCase()),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          if (isFile)
            _buildFileBox(
              context: context,
              theme: theme,
              obscured: isObscured,
              hidden: isHiddenFormat,
            )
          else
            _buildValueBox(
              context: context,
              theme: theme,
              keyName: key,
              value: value,
              obscured: isObscured,
              hidden: isHiddenFormat,
            ),
        ],
      ),
    );
  }

  Widget _buildValueBox({
    required BuildContext context,
    required ThemeData theme,
    required String keyName,
    required String value,
    required bool obscured,
    required bool hidden,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: AppRadius.allMd,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              obscured ? '••••••••••••••••' : (value.isEmpty ? '—' : value),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: obscured
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          AppSpacing.gapSm,
          if (hidden)
            AppButton(
              icon: obscured ? AppIcons.eye : AppIcons.eyeSlash,
              tooltip: obscured ? 'Reveal value' : 'Hide value',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => Stores.shares.toggleShareValue(keyName),
            ),
          AppSpacing.gapXs,
          AppButton(
            icon: AppIcons.copy,
            label: 'Copy',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              AppToast.success(context, 'Copied value to clipboard');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileBox({
    required BuildContext context,
    required ThemeData theme,
    required bool obscured,
    required bool hidden,
  }) {
    final recordId = record['id'] as String? ?? '';
    final filename = record['filename'] as String? ?? 'file';
    final busy = Stores.shares.downloadingShareRecordIds.contains(recordId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        children: [
          Icon(AppIcons.fileText, size: 18, color: theme.colorScheme.primary),
          AppSpacing.gapSm,
          Expanded(
            child: Text(
              obscured ? '••••••••••••' : filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).mono.small,
          ),
          if (hidden) ...[
            AppSpacing.gapSm,
            AppButton(
              icon: obscured ? AppIcons.eye : AppIcons.eyeSlash,
              tooltip: obscured ? 'Reveal filename' : 'Hide filename',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => Stores.shares.toggleShareValue(
                record['key'] as String? ?? '',
              ),
            ),
          ],
          AppSpacing.gapXs,
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
}
