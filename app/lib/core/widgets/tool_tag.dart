import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';

/// A tool's short ID as a chip beside its name: tools name themselves, so
/// two may share a name, never an ID.
class ToolIdChip extends StatelessWidget {
  final String id;

  /// What the tool is to the thing the chip sits on, such as a plug for a
  /// section it keeps.
  final IconData? icon;

  /// Stands in for the ID, such as a count of several tools.
  final String? label;

  final String? tooltip;
  final VoidCallback? onTap;

  const ToolIdChip(
    this.id, {
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = AppBadge(
      icon: icon,
      label: label ?? Connection.shortIdOf(id),
      variant: AppBadgeVariant.outline,
      mono: label == null,
    );
    return Tooltip(
      message: tooltip ?? 'ID $id',
      child: onTap == null
          ? badge
          : Semantics(
              button: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: AppRadius.allMd,
                  child: badge,
                ),
              ),
            ),
    );
  }
}
