import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

/// The one vocabulary for trust across the app. Every screen that states
/// whether something is proven renders it through [TrustPanel] or
/// [TrustClaimText] with these exact words — the same fact must never read
/// differently on two screens.
abstract final class TrustCopy {
  static const verified = 'DNS verified';
  static const unverified = 'Not verified';
  static const spoofed = 'Spoofed';
  static const unsigned = 'Not signed';
  static const checking = 'Checking…';

  static const allGood = 'Verified';
  static const allGoodDetail = 'Every check passed. Safe to continue.';
  static const problem = 'Not verified';
  static const problemDetail =
      'At least one check failed. Only continue if you already trust '
      'whoever sent you this link.';
  static const spoofedDetail =
      'The claimed domain does not match the signing key. Do not send '
      'anything.';
}

/// Outcome of one verification step.
enum TrustCheckState {
  /// Proven against something the claimant does not control.
  verified,

  /// Nothing proves it — missing DNS record, no signature, no verdict.
  failed,

  /// Provably false — worse than missing.
  spoofed,

  /// Still being checked.
  checking,
}

/// One row inside a [TrustPanel]: what was checked, what came back.
class TrustCheck {
  final String label;
  final String value;
  final TrustCheckState state;
  final String? detail;

  const TrustCheck({
    required this.label,
    required this.value,
    required this.state,
    this.detail,
  });
}

/// The security summary for anything that makes claims — a request, a share,
/// a pasted link.
///
/// Collapsed to a single green line when every check passed; anything less
/// starts expanded and red, because a problem must not hide behind a tap.
/// The reader gets the one answer they came for — safe or not — and the
/// expanded rows say exactly which link of the chain broke.
class TrustPanel extends StatefulWidget {
  final List<TrustCheck> checks;

  const TrustPanel({super.key, required this.checks});

  @override
  State<TrustPanel> createState() => _TrustPanelState();
}

class _TrustPanelState extends State<TrustPanel> {
  /// null until the reader decides for themselves; the default follows the
  /// verdict. Derived rather than written on the first build, so the
  /// Observer always has this to depend on - a null field left it tracking
  /// nothing, repainting only because its parent happened to rebuild it.
  final Local<bool?> _userToggled = Local(null);

  bool get _allVerified =>
      widget.checks.every((c) => c.state == TrustCheckState.verified);

  bool get _anyChecking =>
      widget.checks.any((c) => c.state == TrustCheckState.checking);

  bool get _anySpoofed =>
      widget.checks.any((c) => c.state == TrustCheckState.spoofed);

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final scheme = Theme.of(context).colorScheme;
        // Fine collapses, broken opens - until the reader says otherwise.
        final open = _userToggled.value ?? (!_anyChecking && !_allVerified);

        final Color accent;
        final IconData icon;
        final String headline;
        final String detail;
        if (_anyChecking) {
          accent = scheme.onSurfaceVariant;
          icon = AppIcons.shieldCheck;
          headline = TrustCopy.checking;
          detail = 'Verifying against public DNS…';
        } else if (_allVerified) {
          accent = scheme.primary;
          icon = AppIcons.shieldCheck;
          headline = TrustCopy.allGood;
          detail = TrustCopy.allGoodDetail;
        } else if (_anySpoofed) {
          accent = scheme.danger;
          icon = AppIcons.exclamationTriangle;
          headline = TrustCopy.spoofed;
          detail = TrustCopy.spoofedDetail;
        } else {
          accent = scheme.danger;
          icon = AppIcons.exclamationTriangle;
          headline = TrustCopy.problem;
          detail = TrustCopy.problemDetail;
        }

        return Container(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: AppRadius.allMd,
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: AppRadius.allMd,
                onTap: _anyChecking ? null : () => _userToggled.value = !open,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_anyChecking)
                        const AppSpinner()
                      else
                        Icon(icon, size: 18, color: accent),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DefaultTextStyle.merge(
                              style: TextStyle(color: accent),
                              child: Text(headline).small,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(detail).muted.small,
                          ],
                        ),
                      ),
                      if (!_anyChecking)
                        Icon(
                          open ? AppIcons.chevronUp : AppIcons.chevronDown,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.duration,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final check in widget.checks) ...[
                              if (check != widget.checks.first)
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppSpacing.xs,
                                  ),
                                  child: AppDivider(),
                                )
                              else
                                const SizedBox(height: AppSpacing.xs),
                              _CheckRow(check: check),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CheckRow extends StatelessWidget {
  final TrustCheck check;

  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, stateLabel) = switch (check.state) {
      TrustCheckState.verified => (
        AppIcons.checkCircle,
        scheme.primary,
        TrustCopy.verified,
      ),
      TrustCheckState.failed => (
        AppIcons.exclamationTriangle,
        scheme.danger,
        TrustCopy.unverified,
      ),
      TrustCheckState.spoofed => (
        AppIcons.exclamationTriangle,
        scheme.danger,
        TrustCopy.spoofed,
      ),
      TrustCheckState.checking => (
        AppIcons.arrowRepeat,
        scheme.onSurfaceVariant,
        TrustCopy.checking,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(check.label).small),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: color),
                    child: Text(stateLabel).small,
                  ),
                ],
              ),
              if (check.value.isNotEmpty)
                Text(
                  check.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).muted.mono.small,
              if (check.detail != null && check.detail!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(check.detail!).muted.small,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// An inline domain claim, colored by proof — never rendered as bare fact.
///
/// "issued by example.com" in plain text reads as proven; anyone can write
/// anything there. This is the only sanctioned way to print such a claim.
class TrustClaimText extends StatelessWidget {
  final String domain;
  final TrustCheckState state;

  const TrustClaimText({super.key, required this.domain, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, suffix) = switch (state) {
      TrustCheckState.verified => (scheme.primary, TrustCopy.verified),
      TrustCheckState.spoofed => (scheme.danger, TrustCopy.spoofed),
      TrustCheckState.checking => (scheme.onSurfaceVariant, TrustCopy.checking),
      TrustCheckState.failed => (scheme.danger, TrustCopy.unverified),
    };
    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: Text('$domain · $suffix').small,
    );
  }
}
