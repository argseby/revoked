import 'package:flutter/material.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/utils/versions.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

/// "App v0.22.0 · Server v0.22.0": how every screen names both releases.
String describeVersions(String? serverVersion) =>
    'App ${AppConfig.appVersion} · Server ${serverVersion ?? 'unknown'}';

/// A green tick when app and server are on one release, an amber warning
/// naming the one behind, and nothing when either version is unknown.
AppBadge? versionStandingBadge(BuildContext context, VersionStanding standing) {
  final scheme = Theme.of(context).colorScheme;
  return switch (standing) {
    VersionStanding.inStep => AppBadge(
      label: 'In step',
      icon: AppIcons.checkCircle,
      accent: scheme.success,
    ),
    VersionStanding.appBehind => AppBadge(
      label: 'App behind',
      icon: AppIcons.exclamationTriangle,
      accent: scheme.warning,
    ),
    VersionStanding.serverBehind => AppBadge(
      label: 'Server behind',
      icon: AppIcons.exclamationTriangle,
      accent: scheme.warning,
    ),
    VersionStanding.unknown => null,
  };
}

/// Both releases on one line, with the badge saying whether they match.
class VersionSummary extends StatelessWidget {
  final String? serverVersion;
  final WrapAlignment alignment;

  const VersionSummary({
    super.key,
    required this.serverVersion,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final badge = versionStandingBadge(
      context,
      compareVersions(AppConfig.appVersion, serverVersion),
    );
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [Text(describeVersions(serverVersion)).small.muted, ?badge],
    );
  }
}

/// The server in effect and how its release relates to this app's, as one
/// tappable pill. Matching releases collapse to a single version; a mismatch
/// names both and turns the pill amber.
class ServerPill extends StatelessWidget {
  final String host;
  final String? serverVersion;
  final VoidCallback onTap;

  const ServerPill({
    super.key,
    required this.host,
    required this.serverVersion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final standing = compareVersions(AppConfig.appVersion, serverVersion);
    final behind =
        standing == VersionStanding.appBehind ||
        standing == VersionStanding.serverBehind;
    final versions = standing == VersionStanding.inStep
        ? serverVersion!
        : describeVersions(serverVersion);
    final status = switch (standing) {
      VersionStanding.inStep => Icon(
        AppIcons.checkCircle,
        size: 14,
        color: scheme.success,
      ),
      VersionStanding.appBehind || VersionStanding.serverBehind => Icon(
        AppIcons.exclamationTriangle,
        size: 14,
        color: scheme.warning,
      ),
      VersionStanding.unknown => null,
    };
    final label = switch (standing) {
      VersionStanding.appBehind => 'App behind',
      VersionStanding.serverBehind => 'Server behind',
      _ => null,
    };

    return Semantics(
      button: true,
      label: ['Change server', host, versions, ?label].join(', '),
      excludeSemantics: true,
      child: AppFocusRing(
        borderRadius: AppRadius.allPill,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.allPill,
            child: Ink(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: behind ? scheme.warning : scheme.outlineVariant,
                ),
                borderRadius: AppRadius.allPill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.server,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  AppSpacing.gapSm,
                  Flexible(
                    child: AppText(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small,
                  ),
                  const AppText(' · ').small.muted,
                  Flexible(
                    child: behind
                        ? DefaultTextStyle.merge(
                            style: TextStyle(color: scheme.warning),
                            child: AppText(
                              versions,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small,
                          )
                        : AppText(
                            versions,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).small.muted,
                  ),
                  if (status != null) ...[AppSpacing.gapXs, status],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
