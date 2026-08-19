import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';

/// Opens the link search drawer: paste a `revoked://` share/request link, then
/// either open it or verify it (DNS + link security) first.
Future<void> openLinkSearchSheet(BuildContext context) {
  return showAppSheet(
    context: context,
    builder: (_) => const LinkSearchSheet(),
  );
}

/// The body of the link search drawer.
///
/// Holds just the link path (the `revoked://` scheme is rendered as a fixed
/// prefix), so a pasted full link auto-strips the scheme. Two actions:
///   * **Open**   — navigates to the link's in-app viewer.
///   * **Verify** — probes the link and walks the DNS trust chain, rendering
///     the resulting [TrustVerdict] inline so the user can judge the sender
///     before opening.
class LinkSearchSheet extends StatefulWidget {
  const LinkSearchSheet({super.key});

  @override
  State<LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends State<LinkSearchSheet> {
  final _controller = TextEditingController();

  bool _verifying = false;
  TrustVerdict? _verdict;
  AppErrorMessage? _verifyError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_normalize);
  }

  @override
  void dispose() {
    _controller.removeListener(_normalize);
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the field holding just the path: if a pasted value includes the
  /// `revoked://` scheme (or leading slashes), drop it so it doesn't collide
  /// with the fixed prefix.
  void _normalize() {
    final cur = _controller.text;
    final stripped = _stripScheme(cur);
    if (stripped != cur) {
      _controller.value = TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(offset: stripped.length),
      );
    }
  }

  String _stripScheme(String v) {
    var s = v;
    final prefix = '${DeepLinks.scheme}://';
    if (s.toLowerCase().startsWith(prefix)) {
      s = s.substring(prefix.length);
    }
    return s.replaceFirst(RegExp(r'^/+'), '');
  }

  /// Parses the current input into the in-app location plus the link's type
  /// and slug, or null when it isn't a recognized `revoked://` link.
  ({String location, bool isRequest, String slug})? _resolve() {
    final path = _stripScheme(_controller.text.trim());
    if (path.isEmpty) return null;
    final uri = Uri.tryParse('${DeepLinks.scheme}://$path');
    if (uri == null) return null;
    final location = DeepLinks.locationFor(uri);
    if (location == null) return null;
    final host = uri.host;
    return (
      location: location,
      isRequest: host == 'r' || host == 'request',
      slug: uri.pathSegments.first,
    );
  }

  void _open() {
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
  Future<void> _verify() async {
    final resolved = _resolve();
    if (resolved == null) {
      AppToast.error(context, 'Enter a link path like s/<slug> or r/<slug>');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _verdict = null;
      _verifyError = null;
    });

    try {
      final TrustVerdict verdict;
      if (resolved.isRequest) {
        final probe = await Stores.requests.getPublicRequestProbe(
          resolved.slug,
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
        await Stores.shares.getPublicLinkProbe(resolved.slug);
        verdict = TrustVerdict.unverified(
          domain: '',
          reason:
              'This is a share link. Shares are passed app-to-app and carry '
              'no server domain to DNS-verify — but this link is live and '
              'reachable.',
        );
      }
      if (!mounted) return;
      setState(() {
        _verdict = verdict;
        _verifying = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifyError = AppErrorMessage.fromException(e);
        _verifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifyError = AppErrorMessage.fromException(e);
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _buildField(scheme),
            if (_verifying) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const AppSpinner(),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Checking DNS and link security…').muted.small,
                ],
              ),
            ],
            if (_verdict != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppTrustBadge(verdict: _verdict!),
            ],
            if (_verifyError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _ErrorBanner(message: _verifyError!),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    icon: AppIcons.shieldCheck,
                    label: 'Verify',
                    style: AppButtonStyle.accent,
                    busy: _verifying,
                    onTap: _verify,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.arrowRight,
                    label: 'Open',
                    onTap: _verifying ? null : _open,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(ColorScheme scheme) {
    return AppTextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (_) => _open(),
      hint: 's/<slug> or r/<slug>',
      // Fixed, always-visible scheme prefix — the user only types the path.
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
