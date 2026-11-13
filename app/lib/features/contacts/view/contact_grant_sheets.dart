import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/shares/view/share_contents_picker.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';

/// Shares vault entries with [contact].
Future<void> openSendToContactSheet(BuildContext context, Contact contact) {
  Stores.contacts.startGrant(contact.id);
  Stores.contacts.loadPolicy();
  if (Stores.vault.records.isEmpty) Stores.vault.loadRecords();
  return showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
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
    identityId: identities.defaultSigner()?.id,
  );
  Stores.contacts.loadPolicy();
  final workspace = Stores.auth.activeWorkspace ?? '';
  if (workspace.isNotEmpty) Stores.templates.loadTemplates(workspace);
  return showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => _AskSheet(contact: contact),
  );
}

/// Where a grant will reach [contact], said before the sender taps rather
/// than after. The button is never disabled: the grant is minted either way
/// and the slug comes back, so disabling it would lose the one thing a sender
/// can always fall back on.
String _reachLine(Contact contact, {required bool isAsk}) {
  final name = contact.name;
  if (contact.isHere) return 'Delivered to $name\u2019s app.';
  final reason = Stores.contacts.emailReason(contact, isAsk: isAsk);
  if (reason == null) return '$name receives the link by email.';
  if (isAsk && !Stores.contacts.signupsOpen) {
    return '$name needs an account here to respond. '
        'The link is returned for manual delivery.';
  }
  // What this server will do with the link, without the old claim that the
  // address names nobody here: for a contact nobody has confirmed, that is
  // not something the server says, and it may well be wrong.
  return 'The link is returned for manual delivery. If $name holds an '
      'account here, it arrives in their app as well.';
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
          ? 'Request delivered to ${contact.name}'
          : 'Delivered to ${contact.name}',
    );
    return;
  }
  if (grant.emailed) {
    AppToast.success(root, 'Emailed to ${contact.email}');
    return;
  }

  final askNeedsAccount = grant.isRequest && !Stores.contacts.signupsOpen;
  final unsaid = grant.channel == ContactChannel.handedOver;
  final origin = Stores.api.originAuthority;
  final link = grant.isRequest
      ? DeepLinks.request(grant.slug, origin: origin)
      : DeepLinks.share(grant.slug, origin: origin);
  await showQrSheet(
    context: root,
    title: grant.isRequest
        ? 'Request link for ${contact.name}'
        : 'Link for ${contact.name}',
    link: link,
    // An unconfirmed contact is told what to do, not what the address is:
    // "no account here" would answer a question the server withholds on
    // purpose, and it may well be wrong — the grant can be in their app
    // already.
    message: unsaid
        ? '${contact.name} already has this if they hold an account here. '
              'Otherwise the link reaches them however you like, and stays '
              'revocable.'
        : askNeedsAccount
        ? '${contact.name} needs an account on this server to respond. '
              'Accounts can be added by the server operator.'
        : grant.isRequest
        ? '${contact.name} has no account here. The link is delivered '
              'manually and opened in Revoked to respond.'
        : '${contact.name} has no account here. The link is delivered '
              'manually and remains revocable.',
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
      builder: (_) => _ContactGrantLayout(
        title: 'Send to ${contact.name}',
        subtitle:
            'The recipient always sees the latest version. Access can be '
            'revoked. ${_reachLine(contact, isAsk: false)}',
        error: store.error?.description,
        fields: [
          AppComposerField(
            label: 'Label',
            child: AppTextField(
              controller: store.grantLabel,
              hint: 'Bank details',
              autofocus: true,
            ),
          ),
          ShareContentsRow(
            records: store.draftRecords,
            sections: store.draftSections,
            toggleRecord: store.toggleDraftRecord,
            toggleSection: store.toggleDraftSection,
          ),
        ],
        footer: AppComposerFooter(
          label: 'Send',
          icon: AppIcons.send,
          busy: store.isHandingOver,
          onSubmit: store.canSend ? () => _send(context) : null,
          onCancel: () => Navigator.of(context).pop(),
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
        return _ContactGrantLayout(
          title: 'Request from ${contact.name}',
          subtitle:
              'Responses stay under the contact\u2019s control and always '
              'show the latest version. ${_reachLine(contact, isAsk: true)}',
          error: store.error?.description,
          fields: [
            AppComposerField(
              label: 'Title',
              child: AppTextField(
                controller: store.grantLabel,
                hint: 'New address',
                autofocus: true,
              ),
            ),
            AppComposerField(
              label: 'Template',
              child: AppSelect<String>(
                value: store.askTemplateId,
                placeholder: 'None — respondents add their own fields',
                onChanged: store.setAskTemplate,
                items: [
                  for (final t in templates) AppSelectItem(t.id, Text(t.name)),
                ],
              ),
            ),
            AppComposerField(
              label: 'Your identity',
              child: IdentityPicker(
                selectedId: store.askIdentityId,
                onChanged: store.setAskIdentity,
              ),
            ),
          ],
          footer: AppComposerFooter(
            label: 'Ask',
            icon: AppIcons.askFor,
            busy: store.isHandingOver,
            onSubmit: store.canAsk ? () => _ask(context) : null,
            onCancel: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }
}

/// A short contact drawer: the composer's header, a few fields without a
/// section rail, and its footer.
class _ContactGrantLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> fields;
  final String? error;
  final Widget footer;

  const _ContactGrantLayout({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.footer,
    this.error,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: composerMaxHeight(context),
    ),
    child: Column(
      // Fills the side panel, so the footer sits on its bottom edge.
      mainAxisSize: AppSpacing.isNarrow(context)
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VaultComposerHeader(
          title: title,
          area: 'Contacts',
          areaIcon: AppIcons.person,
          subtitle: subtitle,
          onClose: () => Navigator.of(context).pop(),
        ),
        const AppDivider(),
        Flexible(
          fit: AppSpacing.isNarrow(context) ? FlexFit.loose : FlexFit.tight,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...fields,
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl,
                      AppSpacing.sm,
                      AppSpacing.xxl,
                      0,
                    ),
                    child: AppErrorText(error!),
                  ),
              ],
            ),
          ),
        ),
        const AppDivider(),
        footer,
      ],
    ),
  );
}
