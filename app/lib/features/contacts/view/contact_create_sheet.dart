import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';

/// Adds someone this workspace sends to and asks from.
Future<void> openContactCreateSheet(BuildContext context) {
  Stores.contacts.clearForm();
  return showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => const _CreateSheet(),
  );
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
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: composerMaxHeight(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VaultComposerHeader(
              title: 'Add a contact',
              area: 'Contacts',
              areaIcon: AppIcons.person,
              subtitle:
                  'Contacts receive records and requests. Only an email '
                  'address is required.',
              onClose: store.isSaving
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            const AppDivider(),
            Flexible(
              child: AppComposerSections(
                enabled: !store.isSaving,
                sections: [
                  AppComposerSection(
                    title: 'Contact',
                    icon: AppIcons.person,
                    children: [
                      AppComposerField(
                        label: 'Name',
                        child: AppTextField(
                          controller: store.name,
                          hint: 'Ada Lovelace',
                          autofocus: true,
                        ),
                      ),
                      AppComposerField(
                        label: 'Email address',
                        explanation: 'Where records and requests are sent',
                        child: AppTextField(
                          controller: store.email,
                          hint: 'ada@example.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  AppComposerSection(
                    title: 'Server',
                    icon: AppIcons.globe,
                    children: [
                      AppComposerField(
                        label: 'Server (optional)',
                        explanation:
                            'Only for contacts running their own Revoked '
                            'server. Not checked until the contact is '
                            'verified.',
                        child: AppTextField(
                          controller: store.peerDomain,
                          hint: 'revoked.example.com',
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (store.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.sm,
                  AppSpacing.xxl,
                  0,
                ),
                child: AppErrorText(store.error!.description),
              ),
            const AppDivider(),
            AppComposerFooter(
              label: 'Add contact',
              icon: AppIcons.personPlus,
              busy: store.isSaving,
              onSubmit: store.canSave ? () => _create(context) : null,
              onCancel: store.isSaving
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
