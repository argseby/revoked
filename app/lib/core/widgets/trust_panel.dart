import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

/// The one vocabulary for trust across the app. Every screen that states
/// whether something is proven renders it through [TrustPanel] or
/// [TrustClaimText] / [TrustClaimBadge] with these exact words — the same fact must never read
/// differently on two screens.
abstract final class TrustCopy {
  static const verified = 'DNS verified';
  static const unverified = 'Not verified';
  static const spoofed = 'Spoofed';
  static const revoked = 'Revoked';
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
  static const revokedDetail =
      'Every signature checks out, and the domain has withdrawn this '
      'identity. Whoever holds the key no longer speaks for it.';
}

/// Outcome of one verification step.
enum TrustCheckState {
  /// Proven against something the claimant does not control.
  verified,

  /// Nothing proves it — missing DNS record, no signature, no verdict.
  failed,

  /// Provably false — worse than missing.
  spoofed,

  /// Proven, and withdrawn since. Not a failed check: every signature holds,
  /// and the issuer has stopped standing behind the thing they signed.
  revoked,

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

  bool get _anyRevoked =>
      widget.checks.any((c) => c.state == TrustCheckState.revoked);

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
          accent = scheme.success;
          icon = AppIcons.shieldCheck;
          headline = TrustCopy.allGood;
          detail = TrustCopy.allGoodDetail;
        } else if (_anySpoofed) {
          accent = scheme.danger;
          icon = AppIcons.exclamationTriangle;
          headline = TrustCopy.spoofed;
          detail = TrustCopy.spoofedDetail;
        } else if (_anyRevoked) {
          accent = scheme.danger;
          icon = AppIcons.shieldSlash;
          headline = TrustCopy.revoked;
          detail = TrustCopy.revokedDetail;
        } else {
          accent = scheme.danger;
          icon = AppIcons.exclamationTriangle;
          headline = TrustCopy.problem;
          detail = TrustCopy.problemDetail;
        }

        final problem = !_anyChecking && !_allVerified;

        // The same card as the web page's sender panel: one verdict on top,
        // then each check with its own result. A failure turns the whole
        // card red, so it cannot be mistaken for the fine case at a glance.
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.allLg,
            border: Border.all(
              color: problem ? accent : scheme.outlineVariant,
              width: problem ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: problem
                    ? accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.zero,
                  onTap: _anyChecking ? null : () => _userToggled.value = !open,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: problem
                                ? accent
                                : accent.withValues(alpha: 0.12),
                            borderRadius: AppRadius.allMd,
                          ),
                          child: Center(
                            child: _anyChecking
                                ? const AppSpinner()
                                : Icon(
                                    icon,
                                    size: 20,
                                    color: problem ? scheme.onError : accent,
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DefaultTextStyle.merge(
                                style: TextStyle(
                                  color: problem ? accent : null,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: Text(headline),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(detail).muted.small,
                            ],
                          ),
                        ),
                        if (!_anyChecking) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            open ? AppIcons.chevronUp : AppIcons.chevronDown,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.duration,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: open
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final check in widget.checks) ...[
                            const AppDivider(),
                            _CheckRow(check: check),
                          ],
                        ],
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

/// One check: what was checked on the left, its result on the right, and the
/// value that was checked under it — marked in the result's color when it
/// cannot be trusted.
class _CheckRow extends StatelessWidget {
  final TrustCheck check;

  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, stateLabel) = switch (check.state) {
      TrustCheckState.verified => (
        AppIcons.checkCircle,
        scheme.success,
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
      TrustCheckState.revoked => (
        AppIcons.shieldSlash,
        scheme.danger,
        TrustCopy.revoked,
      ),
      TrustCheckState.checking => (
        AppIcons.arrowRepeat,
        scheme.onSurfaceVariant,
        TrustCopy.checking,
      ),
    };
    final bad =
        check.state != TrustCheckState.verified &&
        check.state != TrustCheckState.checking;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(check.label)),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(label: stateLabel, accent: color),
            ],
          ),
          if (check.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 18 + AppSpacing.md,
                top: AppSpacing.xxs,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: bad ? color : null,
                  fontWeight: bad ? FontWeight.w600 : null,
                ),
                child: Text(
                  check.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).mono.small,
              ),
            ),
          if (check.detail != null && check.detail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 18 + AppSpacing.md,
                top: AppSpacing.xxs,
              ),
              child: Text(check.detail!).muted.small,
            ),
        ],
      ),
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
    final (color, suffix) = _claimStyle(Theme.of(context).colorScheme, state);
    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: Text('$domain · $suffix').small,
    );
  }
}

/// [TrustClaimText] as a tag, for the tag row of an entity card.
class TrustClaimBadge extends StatelessWidget {
  final String domain;
  final TrustCheckState state;

  const TrustClaimBadge({super.key, required this.domain, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, suffix) = _claimStyle(Theme.of(context).colorScheme, state);
    return AppBadge(
      icon: AppIcons.globe,
      label: '$domain · $suffix',
      accent: color,
    );
  }
}

(Color, String) _claimStyle(ColorScheme scheme, TrustCheckState state) =>
    switch (state) {
      TrustCheckState.verified => (scheme.success, TrustCopy.verified),
      TrustCheckState.spoofed => (scheme.danger, TrustCopy.spoofed),
      TrustCheckState.revoked => (scheme.danger, TrustCopy.revoked),
      TrustCheckState.checking => (scheme.onSurfaceVariant, TrustCopy.checking),
      TrustCheckState.failed => (scheme.danger, TrustCopy.unverified),
    };
