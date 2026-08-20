import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';

/// Edits what one member may do.
///
/// Only permissions the caller holds are offered: the server refuses a grant
/// that exceeds the granter's own access, so showing the rest would just invite
/// a rejection.
Future<bool?> showMemberPermissionsSheet({
  required BuildContext context,
  required String workspaceId,
  required WorkspaceMemberDetail member,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (_) =>
        _MemberPermissionsSheet(workspaceId: workspaceId, member: member),
  );
}

class _MemberPermissionsSheet extends StatefulWidget {
  final String workspaceId;
  final WorkspaceMemberDetail member;

  const _MemberPermissionsSheet({
    required this.workspaceId,
    required this.member,
  });

  @override
  State<_MemberPermissionsSheet> createState() =>
      _MemberPermissionsSheetState();
}

class _MemberPermissionsSheetState extends State<_MemberPermissionsSheet> {
  @override
  void initState() {
    super.initState();
    Stores.invites.startMemberEdit(widget.member.permissionKeys);
  }

  /// Permissions the member holds that the caller cannot grant. They stay
  /// selected and are shown read-only, so saving never silently strips access
  /// the caller was not able to see.
  late final List<InvitePermission> _beyondCaller = widget.member.permissions
      .where((p) => !Stores.invites.grantable.any((g) => g.key == p.key))
      .toList();

  bool get _wouldDropAdmin =>
      widget.member.isLastAdmin &&
      !Stores.invites.memberDraft.contains('members:add');

  Future<void> _save() async {
    if (_wouldDropAdmin) return;

    final store = Stores.invites;
    store.isSavingMember = true;
    final ok = await store.updateMemberPermissions(
      widget.workspaceId,
      widget.member.id,
      store.memberDraft.toList(),
    );
    if (!mounted) return;
    store.isSavingMember = false;

    if (!ok) {
      AppToast.error(
        context,
        store.error?.description ?? 'Could not update permissions.',
      );
      return;
    }
    Navigator.of(context).pop(true);
    AppToast.success(context, 'Permissions updated.');
  }

  @override
  Widget build(BuildContext context) {
    // The whole sheet is reactive: ticking a permission changes both the row
    // and whether Save is allowed, and the last-admin guard reads the same
    // draft. Wrapping fragments separately would only spread that around.
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final grantable = Stores.invites.grantable;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.member.email).header,
                const SizedBox(height: AppSpacing.xxs),
                const Text('Choose what they may do here.').muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_wouldDropAdmin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        0,
                      ),
                      child: AppAlert(
                        destructive: true,
                        title: const Text('Someone must be able to invite'),
                        content: Text(
                          'This is the only member who can invite others. Give someone else that permission first.',
                        ).small,
                      ),
                    ),

                  const AppFormSectionHeader('Permissions'),
                  for (final permission in grantable)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: PermissionCheckRow(
                        permission: permission,
                        selected: Stores.invites.memberDraft.contains(
                          permission.key,
                        ),
                        onChanged: (on) => Stores.invites
                            .toggleMemberPermission(permission.key, on),
                      ),
                    ),

                  if (_beyondCaller.isNotEmpty) ...[
                    const AppFormSectionHeader('Granted by someone else'),
                    for (final permission in _beyondCaller)
                      AppTile(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.sm,
                        ),
                        title: Text(permission.label),
                        subtitle: Text(
                          'You cannot change this, because you do not hold it yourself.',
                        ).muted.small,
                      ),
                  ],

                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          const AppDivider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    style: AppButtonStyle.accent,
                    onTap: Stores.invites.isSavingMember
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: 'Save',
                    busy: Stores.invites.isSavingMember,
                    onTap: (Stores.invites.isSavingMember || _wouldDropAdmin)
                        ? null
                        : _save,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
