import 'package:flutter/material.dart';

import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';

/// Creates a workspace invite: choose what the person will be able to do, then
/// hand them the key.
///
/// Permissions come from the backend catalogue rather than a local copy, so the
/// list always matches what the server will actually enforce.
Future<void> showInviteCreateSheet({
  required BuildContext context,
  required String workspaceId,
}) {
  return showAppSheet(
    context: context,
    builder: (_) => _InviteCreateSheet(workspaceId: workspaceId),
  );
}

class _InviteCreateSheet extends StatefulWidget {
  final String workspaceId;

  const _InviteCreateSheet({required this.workspaceId});

  @override
  State<_InviteCreateSheet> createState() => _InviteCreateSheetState();
}

class _InviteCreateSheetState extends State<_InviteCreateSheet> {
  final _labelCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _selected = <String>{};
  bool _singleUse = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    Stores.invites.loadCatalogue();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = Stores.invites;
    if (_selected.isEmpty) {
      AppToast.error(context, 'Choose at least one permission to grant.');
      return;
    }

    setState(() => _submitting = true);
    final ok = await store.create(
      workspace: widget.workspaceId,
      label: _labelCtrl.text.trim().isEmpty ? 'Invite' : _labelCtrl.text.trim(),
      permissions: _selected.toList(),
      email: _emailCtrl.text.trim(),
      maxUses: _singleUse ? 1 : null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) {
      final err = store.error;
      AppToast.error(
        context,
        err?.description ?? 'Could not create the invite.',
      );
      return;
    }

    final token = store.lastCreatedToken;
    if (token == null) {
      AppToast.error(context, 'The invite was created but no key came back.');
      return;
    }
    Navigator.of(context).pop();
    await _showTokenDialog(context, token);
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.invites;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                0,
              ),
              child: Text('Invite someone').header,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                0,
              ),
              child: Text(
                'They will see exactly what you grant before they accept.',
              ).muted.small,
            ),

            const AppFormSectionHeader('Who'),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH(context),
              ),
              child: Column(
                children: [
                  AppTextField(
                    controller: _labelCtrl,
                    label: 'Name this invite',
                    hint: 'e.g. Accountant',
                  ),
                  AppSpacing.gapSm,
                  AppTextField(
                    controller: _emailCtrl,
                    label: 'Lock to an email (optional)',
                    hint: 'name@example.com',
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
                'Locking to an email means a forwarded key cannot be used by anyone else.',
              ).muted.small,
            ),

            AppFormToggleRow(
              icon: AppIcons.key,
              label: 'Single use',
              subtitle: 'The key stops working once someone joins.',
              value: _singleUse,
              onChanged: (v) => setState(() => _singleUse = v),
            ),

            const AppFormSectionHeader('What they may do'),
            Observer(
              builder: (_) {
                if (store.catalogue.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text('Loading permissions…'),
                  );
                }
                return Column(
                  children: [
                    for (final p in store.catalogue)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: PermissionCheckRow(
                          permission: p,
                          selected: _selected.contains(p.key),
                          onChanged: (on) => setState(() {
                            if (on) {
                              _selected.add(p.key);
                            } else {
                              _selected.remove(p.key);
                            }
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),

            if (_selected.isNotEmpty &&
                store.catalogue.any(
                  (p) => p.destructive && _selected.contains(p.key),
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
                  title: const Text('This invite hands over control'),
                  content: Text(
                    'At least one permission lets the holder change who else can get in.',
                  ).small,
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: AppButton(
                label: _submitting ? 'Creating…' : 'Create invite',
                onTap: _submitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The key is shown once. The server keeps only a hash, so a key that is not
/// copied here cannot be recovered — a new invite has to be made instead.
Future<void> _showTokenDialog(BuildContext context, String token) async {
  final link = DeepLinks.invite(token);
  final copy = await showAppDialog(
    context: context,
    title: 'Share this key',
    message: 'This is shown once. Copy it now — it cannot be retrieved later.',
    content: SelectableText(link),
    confirmLabel: 'Copy key',
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: link));
}
