import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';
import 'package:revoked_app/features/shell/view/qr_scan_sheet.dart';

/// Opens the link search drawer: paste a `revoked://` share/request link, then
/// either open it or verify it (DNS + link security) first.
Future<void> openLinkSearchSheet(BuildContext context) async {
  final store = Stores.linkSearch;
  if (store.isDrawerOpen) return;
  store.isDrawerOpen = true;
  // Read the clipboard exactly here - opening this drawer is the one
  // moment a revoked:// link on it is almost certainly why we were opened.
  final adoption = await store.adoptClipboardLink();
  if (adoption == ClipboardAdoption.adopted && context.mounted) {
    AppToast.success(context, 'Link taken from your clipboard');
  }
  if (!context.mounted) {
    store.isDrawerOpen = false;
    return;
  }
  try {
    await showAppSheet(
      context: context,
      builder: (_) => const LinkSearchSheet(),
    );
  } finally {
    store.isDrawerOpen = false;
  }
}

/// The body of the link search drawer.
///
/// Holds just the link path (the `revoked://` scheme is rendered as a fixed
/// prefix), so a pasted full link auto-strips the scheme. Two actions:
///   * **Open**   — navigates to the link's in-app viewer.
///   * **Verify** — probes the link and walks the DNS trust chain, rendering
///     the resulting [TrustVerdict] inline so the user can judge the sender
///     before opening.
class LinkSearchSheet extends StatelessWidget {
  const LinkSearchSheet({super.key});

  LinkSearchStore get _store => Stores.linkSearch;
  TextEditingController get _controller => _store.controller;

  /// Parses the current input into the in-app location plus the link's type
  /// and slug, or null when it isn't a recognized `revoked://` link.
  ({String location, bool isRequest, String slug, String? origin})? _resolve() {
    final path = _store.stripScheme(_controller.text.trim());
    if (path.isEmpty) return null;
    final uri = Uri.tryParse('${DeepLinks.scheme}://$path');
    if (uri == null) return null;
    final link = DeepLinks.parse(uri);
    if (link == null) return null;
    return (
      location: DeepLinks.locationFor(uri)!,
      isRequest: link.kind == 'r',
      slug: link.slug,
      origin: link.origin,
    );
  }

  void _open(BuildContext context) {
    final resolved = _resolve();
    if (resolved == null) {
      AppToast.error(context, 'Enter a link path like s/<slug> or r/<slug>');
      return;
    }
    // Capture the router before popping — the sheet's context is gone after.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(resolved.location);
  }

  /// Probes the link and walks the DNS trust chain. Request links carry the
  /// requester's `server.domain` + signature, so they get a full verdict;
  /// share links carry no domain claim, so we confirm the link is live and
  /// report that it can't be DNS-verified.
  Future<void> _verify(BuildContext context) async {
    final resolved = _resolve();
    if (resolved == null) {
      AppToast.error(context, 'Enter a link path like s/<slug> or r/<slug>');
      return;
    }

    FocusScope.of(context).unfocus();
    _store.startVerifying();

    try {
      final TrustVerdict verdict;
      if (resolved.isRequest) {
        final probe = await Stores.requests.getPublicRequestProbe(
          resolved.slug,
          origin: resolved.origin,
        );
        final server = probe['server'];
        final requester = probe['requester'];
        final domain = server is Map<String, dynamic>
            ? (server['domain'] as String? ?? '')
            : '';
        final fingerprint = requester is Map<String, dynamic>
            ? (requester['fingerprint'] as String? ?? '')
            : '';
        final parentSig = requester is Map<String, dynamic>
            ? (requester['parentSignature'] as String? ?? '')
            : '';
        verdict = await Stores.domainVerification.verify(
          claimedDomain: domain,
          identityFingerprint: fingerprint,
          parentSignatureHex: parentSig,
        );
      } else {
        // A successful probe proves the share is live (not revoked / expired /
        // fake). Shares are distributed app-to-app and declare no domain, so
        // there's nothing to DNS-verify.
        await Stores.shares.getPublicLinkProbe(
          resolved.slug,
          origin: resolved.origin,
        );
        verdict = TrustVerdict.unverified(
          domain: '',
          reason:
              'This is a share link. Shares are passed app-to-app and carry '
              'no server domain to DNS-verify — but this link is live and '
              'reachable.',
        );
      }
      _store.finishVerifying(verdict);
    } catch (e) {
      _store.failVerifying(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Verifying flips several parts of this drawer at once — the spinner, the
    // badge, the error banner and both buttons — so the whole body is
    // reactive rather than four fragments of it.
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.sm,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Open a link').header,
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'Paste a Revoked share or request link. Use CTRL + V to open this Dialog from anywhere in this app. Verify checks the '
              'sender\'s DNS and the link\'s security before you open it. ',
            ).muted.small,
            const SizedBox(height: AppSpacing.lg),
            _buildField(context, scheme),
            if (_store.fromClipboard) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(AppIcons.copy, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: const Text(
                      'Link taken from your clipboard',
                    ).muted.small,
                  ),
                ],
              ),
            ],
            // Which server the pasted link names, before anything is
            // fetched from it. A foreign origin is the whole decision.
            if (_resolve()?.origin case final String origin) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    AppIcons.server,
                    size: 13,
                    color: Stores.api.isOwnOrigin(origin)
                        ? scheme.onSurfaceVariant
                        : scheme.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      Stores.api.isOwnOrigin(origin)
                          ? 'Lives on your server ($origin)'
                          : 'Lives on another server: $origin',
                    ).muted.small,
                  ),
                ],
              ),
            ],
            if (_store.isVerifying) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const AppSpinner(),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Checking DNS and link security…').muted.small,
                ],
              ),
            ],
            if (_store.verdict != null) ...[
              const SizedBox(height: AppSpacing.lg),
              TrustPanel(checks: _verdictChecks(_store.verdict!)),
            ],
            if (_store.verifyError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _ErrorBanner(message: _store.verifyError!),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    icon: AppIcons.shieldCheck,
                    label: 'Verify',
                    style: AppButtonStyle.accent,
                    busy: _store.isVerifying,
                    onTap: () => _verify(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.arrowRight,
                    label: 'Open',
                    onTap: _store.isVerifying ? null : () => _open(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The verify result through the same panel every other trust surface
  /// uses - one vocabulary, wherever the reader meets it.
  List<TrustCheck> _verdictChecks(TrustVerdict verdict) {
    final resolved = _resolve();
    final state = switch (verdict.state) {
      TrustState.verified => TrustCheckState.verified,
      TrustState.spoofed => TrustCheckState.spoofed,
      TrustState.revoked => TrustCheckState.revoked,
      _ => TrustCheckState.failed,
    };
    return [
      TrustCheck(
        label: 'Server domain',
        value: verdict.domain.isEmpty ? 'no domain declared' : verdict.domain,
        state: state,
        detail: verdict.reason,
      ),
      if (resolved?.origin != null)
        TrustCheck(
          label: 'Link origin',
          value: resolved!.origin!,
          state:
              Uri.tryParse('https://${resolved.origin!}')?.host ==
                  verdict.domain
              ? state
              : TrustCheckState.failed,
          detail:
              Uri.tryParse('https://${resolved.origin!}')?.host ==
                  verdict.domain
              ? null
              : 'The link points at a different server than the sender '
                    'claims to be.',
        ),
    ];
  }

  Widget _buildField(BuildContext context, ColorScheme scheme) {
    return AppTextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (_) => _open(context),
      hint: 's/<slug> or r/<slug>',
      trailing: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.text.isNotEmpty)
              AppButton(
                icon: AppIcons.x,
                tooltip: 'Clear',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: _store.clear,
              ),
            // The scanner plugin has no desktop implementation; on
            // desktop the QR story is showing codes, not reading them.
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                icon: AppIcons.qrScan,
                tooltip: 'Scan a QR code',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: () => openQrScanSheet(context, onCode: _store.adoptLink),
              ),
            ],
          ],
        ),
      ),

      leading: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xs, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.link, size: 16, color: scheme.onSurfaceVariant),
            AppSpacing.gapXs,
            Text('${DeepLinks.scheme}://').mono.muted,
          ],
        ),
      ),
    );
  }
}

/// Inline banner shown when the link probe fails outright (not found, revoked,
/// expired). That's a security-relevant outcome in its own right.
class _ErrorBanner extends StatelessWidget {
  final AppErrorMessage message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.exclamationOctagon, color: scheme.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppErrorText(message.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(message.description).small.muted,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
