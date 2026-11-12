import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Adds someone this workspace sends to and asks from.
Future<void> openContactCreateSheet(BuildContext context) {
  Stores.contacts.clearForm();
  return showAppSheet(context: context, builder: (_) => const _CreateSheet());
}

class _CreateSheet extends StatelessWidget {
  const _CreateSheet();

  Future<void> _create(BuildContext context) async {
    final store = Stores.contacts;
    final workspace = Stores.auth.activeWorkspace ?? '';
    final ok = await store.create(workspace: workspace);
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(context, 'Contact added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.contacts;
    return Observer(
      builder: (_) => SingleChildScrollView(
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
            const Text('Add a contact').header,
            AppSpacing.gapXxs,
            const Text(
              'Contacts receive records and requests. Only an email address '
              'is required.',
            ).muted.small,
            AppSpacing.gapLg,
            AppFormField(
              label: 'Name',
              inset: false,
              child: AppTextField(
                controller: store.name,
                hint: 'Ada Lovelace',
                autofocus: true,
              ),
            ),
            AppSpacing.gapSm,
            AppFormField(
              label: 'Email address',
              inset: false,
              child: AppTextField(
                controller: store.email,
                hint: 'ada@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            AppSpacing.gapSm,
            AppFormField(
              label: 'Server (optional)',
              inset: false,
              child: AppTextField(
                controller: store.peerDomain,
                hint: 'revoked.example.com',
                mono: true,
              ),
            ),
            AppSpacing.gapXs,
            const Text(
              'Only for contacts running their own Revoked server. Not '
              'checked until the contact is verified.',
            ).muted.small,
            if (store.error != null) ...[
              AppSpacing.gapSm,
              AppErrorText(store.error!.description),
            ],
            AppSpacing.gapLg,
            Row(
              children: [
                AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.accent,
                  onTap: () => Navigator.of(context).pop(),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    icon: AppIcons.personPlus,
                    label: 'Add',
                    busy: store.isSaving,
                    onTap: store.canSave ? () => _create(context) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
