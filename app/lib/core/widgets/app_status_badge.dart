import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/status_colors.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';

/// A link's or request's status as a badge — "Active" green, "Paused" amber,
/// "Revoked" red — the same everywhere a status is shown.
class AppStatusBadge extends StatelessWidget {
  final String status;

  const AppStatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: StatusColors.displayLabel(status),
      accent: StatusColors.foreground(Theme.of(context), status),
    );
  }
}
