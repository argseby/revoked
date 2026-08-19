import 'package:flutter/material.dart';

import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';

/// One grantable permission with its explanation. Invites, member editing and
/// API keys pick from the same catalogue, so they pick from it the same way —
/// including which permissions are marked as able to widen someone's access.
class PermissionCheckRow extends StatelessWidget {
  final InvitePermission permission;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  const PermissionCheckRow({
    super.key,
    required this.permission,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCheckRow(
      label: permission.label,
      subtitle: permission.description,
      badge: permission.destructive
          ? AppBadge(label: 'Sensitive', variant: AppBadgeVariant.destructive)
          : null,
      value: selected,
      onChanged: onChanged,
    );
  }
}
