import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/group.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// The groups of the active workspace (HR, Service, Techs), which an item's
/// visibility can name (VISIBILITY.md §6). Every member sees them; members
/// who may invite create, rename and delete them and choose who is in them.
Future<void> openGroupsSheet(BuildContext context) {
  final workspace = Stores.auth.activeWorkspace ?? '';
  Stores.settings.loadGroups();
  if (workspace.isNotEmpty) Stores.invites.loadMembers(workspace);
  return showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (_) => const _GroupsSheet(),
  );
}

class _GroupsSheet extends StatelessWidget {
  const _GroupsSheet();

  Future<void> _create(BuildContext context) async {
    final settings = Stores.settings;
    settings.groupName.clear();
    final save = await showAppEditSheet(
      context: context,
      title: 'New group',
      controller: settings.groupName,
      hint: 'e.g. HR',
    );
    if (!save || !context.mounted) return;
    final ok = await settings.createGroup(settings.groupName.text.trim());
    if (!context.mounted) return;
    _report(
      context,
      ok,
      done: 'Group created',
      failed: 'The group could not be created',
    );
  }

  Future<void> _rename(BuildContext context, WorkspaceGroup g) async {
    final settings = Stores.settings;
    settings.groupName.text = g.name;
    final save = await showAppEditSheet(
      context: context,
      title: 'Rename group',
      controller: settings.groupName,
    );
    if (!save || !context.mounted) return;
    final ok = await settings.renameGroup(g.id, settings.groupName.text.trim());
    if (!context.mounted) return;
    _report(
      context,
      ok,
      done: 'Group renamed',
      failed: 'The group could not be renamed',
    );
  }

  Future<void> _delete(BuildContext context, WorkspaceGroup g) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${g.name}?',
      message:
          'Items visible to this group alone are then seen by their owner '
          'only. Items naming other groups too keep those.',
      confirmLabel: 'Delete group',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.settings.deleteGroup(g.id);
    if (!context.mounted) return;
    _report(
      context,
      ok,
      done: 'Group deleted',
      failed: 'The group could not be deleted',
    );
  }

  void _report(
    BuildContext context,
    bool ok, {
    required String done,
    required String failed,
  }) {
    if (ok) {
      AppToast.success(context, done);
    } else {
      AppToast.error(
        context,
        failed,
        subtitle: Stores.settings.groupsError.value,
      );
    }
  }

  void _options(BuildContext context, WorkspaceGroup g) {
    showAppOptionsSheet(
      context: context,
      title: g.name,
      actions: [
        AppSheetAction(
          icon: AppIcons.person,
          label: 'Members',
          onTap: () => showAppSheet<void>(
            context: context,
            dismissible: true,
            builder: (_) => _GroupMembersSheet(groupId: g.id),
          ),
        ),
        AppSheetAction(
          icon: AppIcons.pencil,
          label: 'Rename',
          onTap: () => _rename(context, g),
        ),
        AppSheetAction(
          icon: AppIcons.trash,
          label: 'Delete',
          destructive: true,
          onTap: () => _delete(context, g),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Stores.settings;
    return Observer(
      builder: (_) {
        final manage = settings.canManageGroups.value;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxs,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Groups').header,
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'Items can be made visible to one or more groups instead of '
                'the whole workspace, under Visibility.',
              ).small.muted,
              const SizedBox(height: AppSpacing.lg),
              if (settings.groups.isEmpty)
                const Text('This workspace has no groups yet.').small.muted
              else
                for (final g in settings.groups)
                  AppListRow(
                    icon: AppIcons.personWorkspace,
                    title: g.name,
                    subtitle:
                        '${g.members.length} '
                        '${g.members.length == 1 ? 'member' : 'members'}',
                    onTap: manage ? () => _options(context, g) : null,
                  ),
              if (manage) ...[
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    icon: AppIcons.plus,
                    label: 'New group',
                    style: AppButtonStyle.accent,
                    onTap: () => _create(context),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Who is in one group: every member of the workspace, ticked when in it.
class _GroupMembersSheet extends StatelessWidget {
  final String groupId;

  const _GroupMembersSheet({required this.groupId});

  @override
  Widget build(BuildContext context) {
    final settings = Stores.settings;
    return Observer(
      builder: (_) {
        WorkspaceGroup? group;
        for (final g in settings.groups) {
          if (g.id == groupId) group = g;
        }
        final members = Stores.invites.members;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxs,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Members of ${group?.name ?? 'the group'}').header,
              const SizedBox(height: AppSpacing.lg),
              if (members.isEmpty)
                const Text('Loading members…').small.muted
              else
                for (final m in members)
                  Row(
                    children: [
                      AppCheckbox(
                        value: group?.contains(m.userId) ?? false,
                        onChanged: group == null
                            ? null
                            : (on) async {
                                final ok = await settings.setGroupMember(
                                  groupId,
                                  m.userId,
                                  on == true,
                                );
                                if (!ok && context.mounted) {
                                  AppToast.error(
                                    context,
                                    'The group could not be changed',
                                    subtitle: settings.groupsError.value,
                                  );
                                }
                              },
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(m.email)),
                    ],
                  ),
            ],
          ),
        );
      },
    );
  }
}
