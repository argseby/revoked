import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';

/// A credential's standing as a pill in the colour of its verdict: green
/// when it verifies, amber when something could not be checked, red when it
/// can no longer be used.
Widget? verdictBadge(BuildContext context, CredentialVerdict? verdict) {
  if (verdict == null) return null;
  final scheme = Theme.of(context).colorScheme;
  if (verdict.isVerified) {
    return AppBadge(
      icon: AppIcons.shieldCheck,
      label: verdict.label,
      accent: scheme.success,
    );
  }
  if (verdict.isUnusable) {
    return AppBadge(
      icon: AppIcons.shieldSlash,
      label: verdict.label,
      variant: AppBadgeVariant.destructive,
    );
  }
  return AppBadge(
    icon: AppIcons.exclamation,
    label: verdict.label,
    accent: scheme.warning,
  );
}
