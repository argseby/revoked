import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';

/// Renders a [TrustVerdict] as a colored pill. Tapping opens a detail
/// dialog so the user can see *why* the badge says what it says — that
/// transparency is critical: a green badge with no audit trail is just
/// as bad as no badge at all.
///
/// State → color mapping:
///   verified    → primary (typically green/blue)
///   dnsMissing  → warning (caution, not failure)
///   unverified  → warning
///   spoofed     → destructive (red)
///   revoked     → destructive (red)
class AppTrustBadge extends StatelessWidget {
  final TrustVerdict verdict;

  /// When true the badge is rendered as a compact pill suitable for
  /// embedding inside a list row. When false it expands to a full-width
  /// banner with the explanation visible — appropriate for the top of
  /// the request-fill screen where the user is about to make a trust
  /// decision.
  final bool compact;

  const AppTrustBadge({super.key, required this.verdict, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette(theme, verdict.state);

    if (compact) {
      return _Pill(
        palette: palette,
        icon: palette.icon,
        label: _shortLabel(verdict),
        onTap: () => _showDetails(context),
      );
    }

    return InkWell(
      onTap: () => _showDetails(context),
      borderRadius: AppRadius.allMd,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(palette.icon, color: palette.foreground, size: 18),
            AppSpacing.gapSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(color: palette.foreground),
                    child: Text(_longLabel(verdict)).small,
                  ),
                  AppSpacing.gapXxs,
                  Text(verdict.reason).muted.small,
                ],
              ),
            ),
            Icon(
              Icons.info_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final palette = _palette(Theme.of(context), verdict.state);
    showAppDialog(
      context: context,
      title: _longLabel(verdict),
      icon: palette.icon,
      iconColor: palette.foreground,
      message: verdict.reason,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DetailRow(
            label: 'Domain',
            value: verdict.domain.isEmpty ? '—' : verdict.domain,
          ),
          if (verdict.rootFingerprint != null)
            _DetailRow(
              label: 'Root key fingerprint',
              value: verdict.rootFingerprint!,
              monospace: true,
            ),
          if (verdict.identityFingerprint != null)
            _DetailRow(
              label: 'Identity fingerprint',
              value: verdict.identityFingerprint!,
              monospace: true,
            ),
        ],
      ),
      confirmLabel: 'Close',
      cancelLabel: null,
    );
  }

  static String _shortLabel(TrustVerdict v) {
    switch (v.state) {
      case TrustState.verified:
        return 'Verified ${v.domain}';
      case TrustState.spoofed:
        return 'SPOOF DETECTED';
      case TrustState.revoked:
        return 'REVOKED';
      case TrustState.dnsMissing:
      case TrustState.unverified:
        return 'Unverified';
    }
  }

  static String _longLabel(TrustVerdict v) {
    switch (v.state) {
      case TrustState.verified:
        return 'Verified — ${v.domain}';
      case TrustState.spoofed:
        return 'Domain spoof detected';
      case TrustState.revoked:
        return 'Revoked by ${v.domain}';
      case TrustState.dnsMissing:
        return 'DNS verification missing';
      case TrustState.unverified:
        return 'Identity not domain-verified';
    }
  }

  static _BadgePalette _palette(ThemeData theme, TrustState state) {
    switch (state) {
      case TrustState.verified:
        return _BadgePalette(
          background: theme.colorScheme.primary.withValues(alpha: 0.1),
          border: theme.colorScheme.primary.withValues(alpha: 0.4),
          foreground: theme.colorScheme.primary,
          icon: Icons.verified_outlined,
        );
      case TrustState.spoofed:
        return _BadgePalette(
          background: theme.colorScheme.danger.withValues(alpha: 0.12),
          border: theme.colorScheme.danger.withValues(alpha: 0.5),
          foreground: theme.colorScheme.danger,
          icon: Icons.gpp_bad_outlined,
        );
      // Nothing was forged here, so it does not get the spoof icon — but it is
      // just as much a stop, and the palette has to say so.
      case TrustState.revoked:
        return _BadgePalette(
          background: theme.colorScheme.danger.withValues(alpha: 0.12),
          border: theme.colorScheme.danger.withValues(alpha: 0.5),
          foreground: theme.colorScheme.danger,
          icon: Icons.block_outlined,
        );
      case TrustState.dnsMissing:
      case TrustState.unverified:
        return _BadgePalette(
          background: theme.colorScheme.danger.withValues(alpha: 0.12),
          border: theme.colorScheme.danger.withValues(alpha: 0.5),
          foreground: theme.colorScheme.danger,
          icon: Icons.warning_amber,
        );
    }
  }
}

class _BadgePalette {
  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
  const _BadgePalette({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });
}

class _Pill extends StatelessWidget {
  final _BadgePalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Pill({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allXs,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: AppRadius.allXs,
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: palette.foreground),
            AppSpacing.gapXxs,
            DefaultTextStyle.merge(
              style: TextStyle(color: palette.foreground),
              child: Text(label).small,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  const _DetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label).muted.small,
          AppSpacing.gapXxs,
          if (monospace)
            Text(value).mono.small.selectable
          else
            Text(value).selectable,
        ],
      ),
    );
  }
}
