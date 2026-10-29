import 'package:flutter/material.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/utils/versions.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';

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
