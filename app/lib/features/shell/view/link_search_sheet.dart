import 'dart:async';

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
import 'package:revoked_app/features/shell/store/link_search_store.dart';

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
              'Paste a Revoked share or request link. Verify checks the '
              'sender\'s DNS and the link\'s security before you open it.',
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
              _verdictPanel(scheme, _store.verdict!),
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

  /// The verdict in full: what was checked, what came back, and what it means
  /// for opening the link. A pill alone said "Unverified" without saying that
  /// the sender's domain is unproven, which is the part that matters.
  Widget _verdictPanel(ColorScheme scheme, TrustVerdict verdict) {
    final proven = verdict.state == TrustState.verified;
    final accent = proven ? scheme.primary : scheme.danger;

    final String headline;
    final String meaning;
    switch (verdict.state) {
      case TrustState.verified:
        headline = 'DNS confirms ${verdict.domain}';
        meaning =
            'This link was signed by a key that ${verdict.domain} publishes in '
            'its own DNS. The sender is who they claim to be.';
      case TrustState.spoofed:
        headline = 'This link is impersonating someone';
        meaning =
            'The domain it claims does not match the key that signed it. Do '
            'not open it or send anything.';
      case TrustState.dnsMissing:
        headline = 'No DNS record to check against';
        meaning =
            'The sender\'s server publishes no `_revoked` DNS record, so there '
            'is nothing to prove who they are. Only open this if you already '
            'trust whoever gave you the link.';
      case TrustState.unverified:
        headline = 'Nobody has verified this sender';
        meaning =
            'The domain on this link is an unproven claim. Only open it if you '
            'already trust whoever gave you the link.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                proven ? AppIcons.shieldCheck : AppIcons.exclamationTriangle,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: accent),
                  child: Text(headline).small,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(meaning).muted.small,
          if (verdict.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(verdict.reason).muted.small,
          ],
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, ColorScheme scheme) {
    return AppTextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (_) => _open(context),
      hint: 's/<slug> or r/<slug>',
      trailing: _controller.text.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AppButton(
                icon: AppIcons.x,
                tooltip: 'Clear',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: _store.clear,
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
