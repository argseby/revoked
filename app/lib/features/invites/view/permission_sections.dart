import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';

/// Presents the permission catalogue in groups that describe the work each
/// group controls. Unknown future permissions remain visible at the end.
class PermissionSections extends StatelessWidget {
  final List<InvitePermission> permissions;
  final bool Function(InvitePermission permission) selected;
  final ValueChanged<({InvitePermission permission, bool selected})> onChanged;
  final bool showEmpty;

  const PermissionSections({
    super.key,
    required this.permissions,
    required this.selected,
    required this.onChanged,
    this.showEmpty = false,
  });

  static const _sections = <({String title, String description, Set<String> keys})>[
    (title: 'Vault', description: 'Read, change, or share workspace records.', keys: {'vault:read', 'vault:write', 'vault:publish'}),
    (title: 'Sharing', description: 'Create and manage links that share information.', keys: {'shares:read', 'shares:manage'}),
    (title: 'Requests and responses', description: 'Collect information and manage what people submit.', keys: {'requests:read', 'requests:manage', 'responses:read', 'responses:manage'}),
    (title: 'Templates', description: 'View and maintain reusable request forms.', keys: {'templates:read', 'templates:manage'}),
    (title: 'People and trust', description: 'Manage contacts, signing identities, and trusted statements.', keys: {'contacts:read', 'contacts:manage', 'identities:read', 'identities:manage', 'attestations:read', 'attestations:issue'}),
    (title: 'Workspace administration', description: 'Control membership, workspace settings, and integrations.', keys: {'members:read', 'members:add', 'members:remove', 'settings:manage', 'webhooks:manage'}),
  ];

  @override
  Widget build(BuildContext context) {
    final remaining = permissions.toList();
    final groups = <({String title, String description, List<InvitePermission> items})>[];
    for (final section in _sections) {
      final items = remaining.where((p) => section.keys.contains(p.key)).toList();
      remaining.removeWhere((p) => section.keys.contains(p.key));
      if (items.isNotEmpty) {
        groups.add((title: section.title, description: section.description, items: items));
      }
    }
    if (remaining.isNotEmpty) {
      groups.add((title: 'Other access', description: 'Additional workspace capabilities.', items: remaining));
    }
    if (groups.isEmpty && !showEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Text(
            'Permissions control what someone can do in the workspace. Choose only the access they need; you can change it later.',
          ).muted.small,
        ),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            child: Text('No permissions are available to grant.').muted.small,
          ),
        for (final group in groups) ...[
          AppFormSectionHeader(group.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xs),
            child: Text(group.description).muted.small,
          ),
          for (final permission in group.items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: PermissionCheckRow(
                permission: permission,
                selected: selected(permission),
                onChanged: (value) => onChanged((permission: permission, selected: value)),
              ),
            ),
        ],
      ],
    );
  }
}
