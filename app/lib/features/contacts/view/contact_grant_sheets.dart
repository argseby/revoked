import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/shares/view/share_contents_picker.dart';

/// Shares vault entries with [contact].
Future<void> openSendToContactSheet(BuildContext context, Contact contact) {
  Stores.contacts.startGrant(contact.id);
  Stores.contacts.loadPolicy();
  if (Stores.vault.records.isEmpty) Stores.vault.loadRecords();
  return showAppSheet(
    context: context,
    builder: (_) => _SendSheet(contact: contact),
  );
}

/// Asks [contact] to send something back.
///
/// The identities load before the sheet opens rather than inside it: an ask
/// carries the name the other person is asked to trust, so a sheet that
/// opened without one would show its Ask button dead and say nothing about
/// why.
Future<void> openAskContactSheet(BuildContext context, Contact contact) async {
  final identities = Stores.identities;
  if (identities.identities.isEmpty) await identities.loadIdentities();
  if (!context.mounted) return;
  Stores.contacts.startGrant(
    contact.id,
    identityId:
        identities.primaryIdentity?.id ??
        identities.identities.where((i) => !i.isRevoked).firstOrNull?.id,
  );
  Stores.contacts.loadPolicy();
  final workspace = Stores.auth.activeWorkspace ?? '';
  if (workspace.isNotEmpty) Stores.templates.loadTemplates(workspace);
  return showAppSheet(
    context: context,
    builder: (_) => _AskSheet(contact: contact),
  );
}

/// Where a grant will reach [contact], said before the sender taps rather
/// than after. The button is never disabled: the grant is minted either way
/// and the slug comes back, so disabling it would lose the one thing a sender
/// can always fall back on.
String _reachLine(Contact contact, {required bool isAsk}) {
  final name = contact.name;
  if (contact.isHere) return 'It lands in $name\u2019s app.';
  final reason = Stores.contacts.emailReason(contact, isAsk: isAsk);
  if (reason == null) return '$name gets an email with the link.';
  if (isAsk && !Stores.contacts.signupsOpen) {
    return '$name needs an account here to answer. '
        'You\u2019ll get a link to pass on.';
  }
  return '$name has no account here, so you\u2019ll get a link to pass on.';
}

/// What happened to a grant, told once and the same way for both sheets: it
/// is in their app, an email is on its way, or here is the link to pass on.
Future<void> _reportOutcome(
  BuildContext context,
  Contact contact,
  ContactGrant grant,
) async {
  final navigator = Navigator.of(context);
  final root = navigator.context;
  navigator.pop();
  if (!root.mounted) return;

  if (grant.delivered) {
    AppToast.success(
      root,
      grant.isRequest
          ? 'Asked ${contact.name} — it is in their app'
          : 'Sent to ${contact.name} — it is in their app',
    );
    return;
  }
  if (grant.emailed) {
    AppToast.success(root, 'Emailed to ${contact.email}');
    return;
  }

  final askNeedsAccount = grant.isRequest && !Stores.contacts.signupsOpen;
  final origin = Stores.api.originAuthority;
  final link = grant.isRequest
      ? DeepLinks.request(grant.slug, origin: origin)
      : DeepLinks.share(grant.slug, origin: origin);
  await showQrSheet(
    context: root,
    title: grant.isRequest
        ? 'Send this to ${contact.name}'
        : 'Give this to ${contact.name}',
    link: link,
    message: askNeedsAccount
        ? '${contact.name} needs an account on this server to answer. Send '
              'them this link, or ask whoever runs the server to add them.'
        : grant.isRequest
        ? '${contact.name} has no account here yet, so send them this link '
              'yourself. They open it in Revoked to answer.'
        : '${contact.name} has no account here yet, so send them this link '
              'yourself. You can revoke it whenever you like.',
  );
}

class _SendSheet extends StatelessWidget {
  final Contact contact;

  const _SendSheet({required this.contact});

  Future<void> _send(BuildContext context) async {
    final grant = await Stores.contacts.submitSend();
    if (!context.mounted || grant == null) return;
    await _reportOutcome(context, contact, grant);
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.contacts;
    return Observer(
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
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
              Text('Send to ${contact.name}').header,
              AppSpacing.gapXxs,
              const Text(
                'They always see the latest version, and you can revoke it '
                'whenever you like.',
              ).muted.small,
              AppSpacing.gapXxs,
              Text(_reachLine(contact, isAsk: false)).muted.small,
              AppSpacing.gapLg,
              AppFormField(
label: 'Label',
inset: false,
child: AppTextField(
controller: store.grantLabel,
hint: 'My bank details',
autofocus: true,
),
),
              AppSpacing.gapSm,
              ShareContentsRow(
                records: store.draftRecords,
                sections: store.draftSections,
                toggleRecord: store.toggleDraftRecord,
                toggleSection: store.toggleDraftSection,
                inset: false,
              ),
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
                      icon: AppIcons.send,
                      label: 'Send',
                      busy: store.isHandingOver,
                      onTap: store.canSend ? () => _send(context) : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AskSheet extends StatelessWidget {
  final Contact contact;

  const _AskSheet({required this.contact});

  Future<void> _ask(BuildContext context) async {
    final grant = await Stores.contacts.submitAsk();
    if (!context.mounted || grant == null) return;
    await _reportOutcome(context, contact, grant);
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.contacts;
    return Observer(
      builder: (_) {
        final templates = Stores.templates.templates;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
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
                Text('Ask ${contact.name} for something').header,
                AppSpacing.gapXxs,
                const Text(
                  'What comes back stays theirs: they can change it or take '
                  'it away, and you always see the latest.',
                ).muted.small,
                AppSpacing.gapXxs,
                Text(_reachLine(contact, isAsk: true)).muted.small,
                AppSpacing.gapLg,
                AppFormField(
label: 'Title',
inset: false,
child: AppTextField(
controller: store.grantLabel,
hint: 'Your new address',
autofocus: true,
),
),
                AppSpacing.gapSm,
                AppFormField(
                  label: 'Template',
                  inset: false,
                  child: AppSelect<String>(
                    value: store.askTemplateId,
                    placeholder: 'None — they add their own fields',
                    onChanged: store.setAskTemplate,
                    items: [
                      for (final t in templates)
                        AppSelectItem(t.id, Text(t.name)),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
                AppFormField(
                  label: 'Your identity',
                  inset: false,
                  child: IdentityPicker(
                    selectedId: store.askIdentityId,
                    onChanged: store.setAskIdentity,
                  ),
                ),
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
                        icon: AppIcons.askFor,
                        label: 'Ask',
                        busy: store.isHandingOver,
                        onTap: store.canAsk ? () => _ask(context) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
