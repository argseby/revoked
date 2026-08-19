import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
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

  const PublicShareScreen({super.key, required this.shareSlug});

  @override
  State<PublicShareScreen> createState() => _PublicShareScreenState();
}

class _PublicShareScreenState extends State<PublicShareScreen> {
  bool _isLoading = true;
  bool _isUnlocking = false;

  /// Probe result.
  Map<String, dynamic>? _probe;

  /// Successful submission result with records/sections.
  Map<String, dynamic>? _data;

  /// Terminal failure state — wrong slug, revoked, expired, max views hit.
  AppErrorMessage? _terminalError;

  final _passwordCtrl = TextEditingController();
  String? _passwordHint;
  String? _identityIdInput;

  bool get _requiresHandshake => _probe?['requireHandshake'] as bool? ?? false;

  @override
  void initState() {
    super.initState();
    _probeLink();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _handshakeKey() => 'handshake_link_${widget.shareSlug}';

  Future<String?> _loadStoredHandshake() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_handshakeKey());
  }

  Future<void> _persistHandshake(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handshakeKey(), token);
  }

  Future<void> _probeLink() async {
    setState(() {
      _isLoading = true;
      _terminalError = null;
    });

    try {
      _probe = await Stores.shares.getPublicLinkProbe(widget.shareSlug);
      // If neither password nor handshake is required, auto-submit so the
      // payload loads immediately (no extra tap for the viewer).
      final requiresPassword = _probe!['requiresPassword'] as bool? ?? false;
      final requireHandshake = _probe!['requireHandshake'] as bool? ?? false;
      if (!requiresPassword && !requireHandshake) {
        await _unlock();
        return;
      }
      if (requireHandshake) {
        // Default to the viewer's primary identity so the handshake can sign
        // straight away; they can switch in the gate.
        await Stores.identities.loadIdentities();
        _identityIdInput ??= Stores.identities.primaryIdentity?.id;
      }
      setState(() => _isLoading = false);
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      setState(() {
        _terminalError = msg;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _terminalError = AppErrorMessage.fromException(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _unlock() async {
    setState(() {
      _isUnlocking = true;
      _passwordHint = null;
    });

    try {
      final handshake = await _loadStoredHandshake();
      // First contact (no stored token yet) needs a freshly signed
      // challenge so the server can prove the responder controls the
      // identity's private key before issuing a persistent token.
      SignedChallenge? challenge;
      final requireHandshake = _probe?['requireHandshake'] as bool? ?? false;
      if (requireHandshake &&
          handshake == null &&
          _identityIdInput != null &&
          _identityIdInput!.isNotEmpty) {
        challenge = await Stores.handshake.prepare(
          scope: HandshakeService.scopeLink,
          slug: widget.shareSlug,
          identityId: _identityIdInput!,
        );
      }

      final response = await Stores.shares.submitPublicLink(
        widget.shareSlug,
        password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
        handshakeToken: handshake,
        identityId: _identityIdInput,
        challengeNonce: challenge?.nonce,
        challengeSignature: challenge?.signature,
      );

      final newHandshake = response.headers['x-handshake-token'];
      if (newHandshake != null && newHandshake.isNotEmpty) {
        await _persistHandshake(newHandshake);
      }

      setState(() {
        _data = response.body as Map<String, dynamic>;
        _isUnlocking = false;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      setState(() {
        if (msg.isTerminal) {
          _terminalError = msg;
        } else {
          _passwordHint = msg.description;
        }
        _isUnlocking = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _passwordHint = e.toString();
        _isUnlocking = false;
        _isLoading = false;
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
                  const Text('Revoked').header,
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
    if (_isLoading) {
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

    if (_terminalError != null) {
      return _buildTerminal(theme, _terminalError!);
    }

    if (_data != null) {
      return _buildContent(theme, _data!);
    }

    // Probe succeeded but gating remains.
    if (_probe != null) {
      final requiresPassword = _probe!['requiresPassword'] as bool? ?? false;
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
    final label = _probe?['label'] as String? ?? 'Protected share';

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
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  AppSpacing.gapSm,
                  Expanded(child: Text(label).header),
                ],
              ),
              AppSpacing.gapMd,
              if (requiresPassword) ...[
                const Text(
                  'This share is password-protected. Enter the password the sender provided to view its contents.',
                ).muted.small,
                AppSpacing.gapLg,
                AppTextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  hint: 'Password',
                  onSubmitted: (_) => _unlock(),
                ),
                if (_passwordHint != null) ...[
                  AppSpacing.gapXs,
                  Text(_passwordHint!).small,
                ],
              ],
              if (_requiresHandshake) ...[
                if (requiresPassword) AppSpacing.gapLg,
                const Text(
                  'This share is bound to a cryptographic identity. Pick the '
                  'identity to verify with — the sender authorized your key on '
                  'a first visit.',
                ).muted.small,
                AppSpacing.gapMd,
                IdentityPicker(
                  selectedId: _identityIdInput,
                  onChanged: (v) => setState(() => _identityIdInput = v),
                ),
              ],
              AppSpacing.gapXl,
              AppButton(
                label: 'Unlock',
                busy: _isUnlocking,
                onTap: (_requiresHandshake && _identityIdInput == null)
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

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH(context),
        vertical: AppSpacing.xxl,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
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
                          color: theme.colorScheme.primary,
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
                  (r) => _PublicRecordCard(record: r as Map<String, dynamic>),
                ),
                AppSpacing.gapXxl,
              ],
              if (sections.isNotEmpty) ...[
                const Text('Shared Sections').header,
                AppSpacing.gapMd,
                ...sections.map(
                  (s) => _PublicSectionCard(section: s as Map<String, dynamic>),
                ),
              ],
              if (records.isEmpty && sections.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.gigantic,
                    ),
                    child: const Text(
                      'No items are shared in this link.',
                    ).muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicSectionCard extends StatelessWidget {
  final Map<String, dynamic> section;

  const _PublicSectionCard({required this.section});

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
                  : inline.map((r) => _PublicRecordCard(record: r)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicRecordCard extends StatefulWidget {
  final Map<String, dynamic> record;

  const _PublicRecordCard({required this.record});

  @override
  State<_PublicRecordCard> createState() => _PublicRecordCardState();
}

class _PublicRecordCardState extends State<_PublicRecordCard> {
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    final format = widget.record['format'] as String? ?? 'default';
    _isObscured = format == 'hidden';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.record['label'] as String? ?? 'Record';
    final key = widget.record['key'] as String? ?? '';
    final value = widget.record['value'] as String? ?? '';
    final type = widget.record['type'] as String? ?? 'text';
    final format = widget.record['format'] as String? ?? 'default';
    final isHiddenFormat = format == 'hidden';

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
            ),
            AppSpacing.gapMd,
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
                    child: _isObscured
                        ? const Text('••••••••••••••••').mono.small.muted
                        : Text(value).mono.small,
                  ),
                  if (isHiddenFormat) ...[
                    AppSpacing.gapSm,
                    AppButton(
                      icon: _isObscured ? AppIcons.eye : AppIcons.eyeSlash,
                      tooltip: _isObscured ? 'Show' : 'Hide',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: () => setState(() {
                        _isObscured = !_isObscured;
                      }),
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
