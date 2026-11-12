import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/widgets/app_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/invites/store/invites_store.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/invites/view/permission_sections.dart';
import 'package:revoked_app/features/settings/view/features_page.dart';

/// Opens the new-invite form for the active workspace.
Future<void> openInviteCreateSheet(BuildContext context) {
  final ws = Stores.auth.activeWorkspace ?? '';
  return showAppCreateSheet(
    context,
    label: 'New invite',
    form: (close) => InviteCreateForm(
      workspaceId: ws,
      onClose: () {
        close();
        if (ws.isNotEmpty) Stores.invites.load(ws);
      },
    ),
  );
}

/// Creates a workspace invite: choose what the person will be able to do, then
/// hand them the key.
///
/// Permissions come from the backend catalogue rather than a local copy, so the
/// list always matches what the server will actually enforce.
class InviteCreateForm extends StatefulWidget {
  final String workspaceId;
  final VoidCallback onClose;

  const InviteCreateForm({
    super.key,
    required this.workspaceId,
    required this.onClose,
  });

  @override
  State<InviteCreateForm> createState() => _InviteCreateSheetState();
}

class _InviteCreateSheetState extends State<InviteCreateForm> {
  InvitesStore get _store => Stores.invites;

  @override
  void initState() {
    super.initState();
    Stores.invites.resetDraft();
    Stores.invites.loadCatalogue();
    Stores.features.loadIfDue().then((_) {
      // Most invites are for one kind of member; the first preset is the
      // narrowest, so nothing is handed out that was not chosen.
      if (!mounted || _store.draftPermissions.isNotEmpty) return;
      final presets = Stores.features.presets;
      if (presets.isNotEmpty) _store.applyPreset(presets.first);
    });
  }

  Future<void> _submit() async {
    final store = Stores.invites;
    if (_store.draftPermissions.isEmpty) {
      AppToast.error(context, 'At least one permission is required.');
      return;
    }

    _store.isCreating = true;
    final ok = await store.create(
      workspace: widget.workspaceId,
      label: _store.labelController.text.trim().isEmpty
          ? 'Invite'
          : _store.labelController.text.trim(),
      permissions: _store.draftPermissions.toList(),
      features: _store.draftFeatures.toList(),
      email: _store.emailController.text.trim(),
      maxUses: _store.draftSingleUse ? 1 : null,
    );
    if (!mounted) return;
    _store.isCreating = false;

    if (!ok) {
      final err = store.error;
      AppToast.error(
        context,
        err?.description ?? 'The invite could not be created.',
      );
      return;
    }

    final token = store.lastCreatedToken;
    if (token == null) {
      AppToast.error(
        context,
        'The invite was created, but its key was not returned. The invite should be withdrawn and recreated.',
      );
      return;
    }
    await _showTokenDialog(context, token);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    // Ticking a permission changes the row, the destructive warning and
    // whether Create is enabled, so the body is reactive as a whole.
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.invites;

    return Column(
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
              const Text('New invite').header,
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'The granted permissions are shown to the invitee before acceptance.',
              ).muted.small,
            ],
          ),
        ),
        const AppDivider(),

        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppFormSectionHeader('Who'),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH(context),
              ),
              child: Column(
                children: [
                  AppFormField(
                    label: 'Label',
                    inset: false,
                    child: AppTextField(
                      controller: _store.labelController,
                      hint: 'Accountant',
                    ),
                  ),
                  AppSpacing.gapSm,
                  AppFormField(
                    label: 'Restrict to email (optional)',
                    inset: false,
                    child: AppTextField(
                      controller: _store.emailController,
                      hint: 'name@example.com',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                0,
              ),
              child: Text(
                'A forwarded key is then rejected for any other account.',
              ).muted.small,
            ),

            AppFormToggleRow(
              icon: AppIcons.key,
              label: 'Single use',
              subtitle: 'The key expires after the first join.',
              value: _store.draftSingleUse,
              onChanged: _store.setDraftSingleUse,
            ),

            const AppFormSectionHeader('Access'),
            _Presets(store: _store),
            AppFormAdvanced(
              summary: 'Permissions and initial features',
              // A draft no preset describes is only readable in here.
              initiallyOpen: _store.draftPreset == null,
              children: [
                if (store.catalogue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text('Loading permissions…'),
                  )
                else
                  PermissionSections(
                    permissions: store.catalogue,
                    selected: (permission) =>
                        _store.draftPermissions.contains(permission.key),
                    onChanged: (change) => _store.toggleDraftPermission(
                      change.permission.key,
                      change.selected,
                    ),
                  ),
                const AppFormSectionHeader('Initial features'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xs,
                  ),
                  child: const Text(
                    'Applies only to members without their own selection. '
                    'Adjustable later under Settings → Features.',
                  ).muted.small,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: FeatureRows(
                    draft: _store.draftFeatures,
                    onChanged: (feature, on) =>
                        _store.toggleDraftFeature(feature.key, on),
                  ),
                ),
              ],
            ),

            if (_store.draftPermissions.isNotEmpty &&
                store.catalogue.any(
                  (p) =>
                      p.destructive && _store.draftPermissions.contains(p.key),
                ))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                child: AppAlert(
                  destructive: true,
                  title: const Text('This invite grants access control'),
                  content: Text(
                    'Members joining with it can manage workspace access.',
                  ).small,
                ),
              ),

            const SizedBox(height: AppSpacing.lg),
          ],
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
              AppButton(
                label: 'Cancel',
                style: AppButtonStyle.accent,
                onTap: _store.isCreating ? null : widget.onClose,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  icon: AppIcons.plus,
                  label: 'Create invite',
                  busy: _store.isCreating,
                  onTap: _store.isCreating ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The kinds of member the catalogue offers, one of which is the draft.
/// Picking one fills in its permissions and features; editing those under
/// Advanced leaves none picked, which the rows show by selecting nothing.
class _Presets extends StatelessWidget {
  final InvitesStore store;

  const _Presets({required this.store});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final presets = Stores.features.presets;
        if (presets.isEmpty) return const SizedBox.shrink();
        final current = store.draftPreset;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final preset in presets)
                AppListRow(
                  icon: switch (preset.features.length) {
                    0 => AppIcons.safe,
                    1 => AppIcons.share,
                    _ => AppIcons.stars,
                  },
                  title: preset.label,
                  subtitle: preset.description,
                  selected: preset.key == current,
                  showChevron: false,
                  onTap: () => store.applyPreset(preset),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The key is shown once. The server keeps only a hash, so a key that is not
/// copied here cannot be recovered — a new invite has to be made instead.
Future<void> _showTokenDialog(BuildContext context, String token) async {
  final link = DeepLinks.invite(token, origin: Stores.api.originAuthority);
  final copy = await showAppDialog(
    context: context,
    title: 'Invite key',
    message: 'The key is shown once and cannot be retrieved later.',
    content: SelectableText(link),
    confirmLabel: 'Copy key',
    confirmIcon: AppIcons.copy,
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: link));
}
