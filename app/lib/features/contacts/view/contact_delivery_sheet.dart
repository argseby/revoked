import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_avatar.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/contacts/store/contact_delivery_store.dart';
import 'package:revoked_app/features/contacts/view/contact_create_sheet.dart';

/// The saved object survives skipping or closing; sending never makes copies.
Future<void> openContactDeliverySheet(
  BuildContext context, {
  Link? share,
  DataRequest? request,
}) async {
  assert((share == null) != (request == null));
  final owner = Stores.auth.userId;
  final serverBase = Stores.api.baseUrl;
  final workspace = request?.workspace ?? share!.workspace;
  await showAppSheet<void>(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => _ContactDeliverySheet(share: share, request: request),
  );
  if (!context.mounted ||
      Stores.auth.userId != owner ||
      Stores.auth.activeWorkspace != workspace ||
      Stores.api.baseUrl != serverBase) {
    return;
  }
  context.go(
    request != null
        ? AppRoutes.requestDetailFor(request.id)
        : AppRoutes.shareDetailFor(share!.id),
  );
}

class _ContactDeliverySheet extends StatefulWidget {
  final Link? share;
  final DataRequest? request;
  const _ContactDeliverySheet({this.share, this.request});
  @override
  State<_ContactDeliverySheet> createState() => _ContactDeliverySheetState();
}

class _ContactDeliverySheetState extends State<_ContactDeliverySheet> {
  late final flow = ContactDeliveryStore(
    share: widget.share,
    request: widget.request,
  );

  @override
  void initState() {
    super.initState();
    flow.load();
  }

  @override
  void dispose() {
    flow.dispose();
    super.dispose();
  }

  Future<void> _shareManually() async {
    if (!flow.contextMatches) {
      AppToast.error(
        context,
        'Return to the saved item’s account, server and workspace to share its link.',
      );
      return;
    }
    final share = widget.share == null
        ? null
        : Stores.shares.findById(widget.share!.id) ?? widget.share;
    final key = share == null ? null : Stores.shares.linkKeyText(share);
    await showShareSheet(
      context: context,
      slug: flow.slug,
      title: flow.title,
      isRequest: flow.isRequest,
      linkKey: key,
      keyUnreadable: (share?.encrypted ?? false) && key == null,
    );
  }

  String _name(Contact contact) =>
      contact.name.isEmpty ? contact.email : contact.name;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final step = flow.step;
      final busy = flow.busy;
      final heading = switch (step) {
        ContactDeliveryStep.contacts => 'Who’s it for?',
        ContactDeliveryStep.review => 'Send your ${flow.kind}',
        ContactDeliveryStep.results => busy ? 'Sending…' : 'Delivery results',
      };
      final description = switch (step) {
        ContactDeliveryStep.contacts =>
          'Select the contacts you want to send it to.',
        ContactDeliveryStep.review => 'Check the recipients before sending.',
        ContactDeliveryStep.results =>
          'The result for each recipient is shown below.',
      };
      return PopScope(
        canPop: !busy,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
          child: Column(
            // Fills the side panel, so the footer sits on its bottom edge.
            mainAxisSize: AppSpacing.isNarrow(context)
                ? MainAxisSize.min
                : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VaultComposerHeader(
                title: heading,
                subtitle: description,
                area: flow.isRequest ? 'Requests' : 'Shares',
                areaIcon: flow.isRequest ? AppIcons.askFor : AppIcons.share,
                crumb: 'Send',
                onClose: busy ? null : () => Navigator.of(context).pop(),
              ),
              const AppDivider(),
              Flexible(
                fit: AppSpacing.isNarrow(context)
                    ? FlexFit.loose
                    : FlexFit.tight,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppComposerCard(
                        trailing: AppText('${step.index + 1} of 3').small.muted,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppBadge(
                              icon: AppIcons.checkCircle,
                              label:
                                  '${flow.isRequest ? 'Request' : 'Share'} created',
                            ),
                            AppSpacing.gapMd,
                            Row(
                              children: [
                                Icon(
                                  flow.isRequest
                                      ? AppIcons.askFor
                                      : AppIcons.link,
                                ),
                                AppSpacing.gapMd,
                                Expanded(
                                  child: AppText(
                                    flow.title.isEmpty
                                        ? 'Untitled ${flow.kind}'
                                        : flow.title,
                                  ).bold,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (step == ContactDeliveryStep.contacts)
                        ..._contacts(context)
                      else if (step == ContactDeliveryStep.review)
                        ..._review(context)
                      else
                        ..._results(context),
                    ],
                  ),
                ),
              ),
              const AppDivider(),
              _footer(context),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _contacts(BuildContext context) {
    final contacts = flow.matchingContacts;
    final failure = Stores.contacts.loadState.error;
    return [
      AppComposerCard(
        trailing: AppText('${flow.selected.length} selected').small.muted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: flow.query,
              hint: 'Find a contact…',
              leading: const Icon(AppIcons.search),
            ),
            AppSpacing.gapMd,
            if (flow.loading) const AppText('Loading contacts…').small.muted,
            if (failure != null) ...[
              AppErrorText(failure),
              AppButton(
                label: 'Retry loading contacts',
                icon: AppIcons.arrowClockwise,
                style: AppButtonStyle.accent,
                onTap: flow.loading
                    ? null
                    : () async {
                        await Stores.contacts.load();
                      },
              ),
            ],
            if (contacts.isEmpty && !flow.loading && failure == null)
              AppText(
                flow.query.text.trim().isEmpty
                    ? 'No contacts yet. Add someone to send this to.'
                    : 'No contacts match your search.',
              ).small.muted,
            for (final contact in contacts)
              AppCheckRow(
                label: _name(contact),
                subtitle: flow.routeFor(contact),
                icon: contact.isHere ? AppIcons.person : AppIcons.envelope,
                value: flow.selected.containsKey(contact.id),
                onChanged: (_) => flow.toggle(contact),
              ),
            AppSpacing.gapSm,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                icon: AppIcons.personPlus,
                label: 'Add contact',
                style: AppButtonStyle.ghost,
                onTap: () => openContactCreateSheet(context),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _review(BuildContext context) => [
    AppComposerCard(
      title: flow.isRequest ? 'What you’re asking for' : 'What you’re sharing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (flow.contentNames.isEmpty)
            const AppText('Open the saved item to review its full contents.')
                .small
                .muted,
          for (final name in flow.contentNames)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    flow.isRequest ? AppIcons.cardList : AppIcons.fileText,
                    size: 16,
                  ),
                  AppSpacing.gapSm,
                  Expanded(child: AppText(name).small),
                ],
              ),
            ),
        ],
      ),
    ),
    AppComposerCard(
      title:
          'To ${flow.recipients.length} ${flow.recipients.length == 1 ? 'contact' : 'contacts'}',
      trailing: AppButton(
        label: 'Change',
        icon: AppIcons.pen,
        size: AppButtonSize.small,
        style: AppButtonStyle.ghost,
        onTap: flow.changeRecipients,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final contact in flow.recipients) _recipient(contact),
          AppSpacing.gapMd,
          AppText(
            flow.isRequest
                ? 'Answers appear under this request.'
                : 'Access stays linked to this share.',
          ).small.muted,
          if ((widget.request?.maxResponses ?? 0) > 0) ...[
            AppSpacing.gapSm,
            AppText(
              'This request accepts up to ${widget.request!.maxResponses} responses in total across all recipients.',
            ).small.muted,
          ],
          if ((widget.share?.maxViews ?? 0) > 0) ...[
            AppSpacing.gapSm,
            AppText(
              'This share allows ${widget.share!.maxViews} views in total across all recipients.',
            ).small.muted,
          ],
          if (flow.encrypted) ...[
            AppSpacing.gapSm,
            const AppText(
              'This share is encrypted. Use “Share link” on the next step to deliver its key securely.',
            ).small.muted,
          ],
        ],
      ),
    ),
  ];

  Widget _recipient(Contact contact) => AppListRow(
    leading: AppAvatar(source: _name(contact), size: AppAvatarSize.small),
    title: _name(contact),
    subtitle: flow.routeFor(contact),
    showChevron: false,
  );

  List<Widget> _results(BuildContext context) => [
    for (final contact in flow.recipients)
      AppComposerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_recipient(contact), _outcome(context, contact)],
        ),
      ),
  ];

  Widget _outcome(BuildContext context, Contact contact) {
    final result = flow.results[contact.id];
    if (result == null) {
      return AppText(
        flow.sendingId == contact.id ? 'Sending…' : 'Waiting to send',
      ).small.muted;
    }
    if (result.error != null) return AppErrorText(result.error!);
    final grant = result.grant!;
    final (label, explanation, icon) = switch (grant.channel) {
      ContactChannel.account => (
        'Delivered in Revoked',
        'Available in their received items.',
        AppIcons.checkCircle,
      ),
      ContactChannel.email => (
        'Email queued',
        'The email is queued; delivery is not yet confirmed.',
        AppIcons.clock,
      ),
      ContactChannel.manual => (
        'Share manually',
        flow.encrypted
            ? 'The encrypted key stays on your device.'
            : 'This server could not deliver the link automatically.',
        AppIcons.link,
      ),
      ContactChannel.handedOver => (
        'Handed over',
        'The server does not disclose the delivery channel. You can also pass on the link.',
        AppIcons.send,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBadge(
            icon: icon,
            label: label,
            accent: grant.delivered
                ? Theme.of(context).colorScheme.success
                : null,
          ),
          AppSpacing.gapXs,
          AppText(explanation).small.muted,
          if (grant.channel == ContactChannel.manual ||
              grant.channel == ContactChannel.handedOver)
            AppButton(
              label: 'Share link',
              icon: AppIcons.share,
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: flow.busy ? null : _shareManually,
            ),
        ],
      ),
    );
  }

  /// Laid out like [AppComposerFooter]: quieter actions first, the step's
  /// primary action at the end, wrapping onto a second line when narrow.
  Widget _footer(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.xl,
      AppSpacing.md + MediaQuery.paddingOf(context).bottom,
    ),
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (flow.step == ContactDeliveryStep.contacts) ...[
          AppButton(
            label: 'Skip for now',
            style: AppButtonStyle.ghost,
            onTap: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'Copy or share link',
            icon: AppIcons.share,
            style: AppButtonStyle.ghost,
            onTap: _shareManually,
          ),
          AppButton(
            label: 'Review recipients',
            trailingIcon: AppIcons.arrowRight,
            onTap: flow.selected.isEmpty ? null : flow.review,
          ),
        ] else if (flow.step == ContactDeliveryStep.review) ...[
          AppButton(
            label: 'Back',
            icon: AppIcons.arrowLeft,
            style: AppButtonStyle.ghost,
            onTap: flow.changeRecipients,
          ),
          AppButton(
            label: flow.encrypted
                ? 'Prepare manual delivery'
                : 'Send to ${flow.recipients.length} ${flow.recipients.length == 1 ? 'contact' : 'contacts'}',
            trailingIcon: AppIcons.send,
            onTap: flow.recipients.isEmpty ? null : flow.send,
          ),
        ] else ...[
          if (flow.hasFailures)
            AppButton(
              label: 'Retry unsuccessful sends',
              icon: AppIcons.arrowRepeat,
              style: AppButtonStyle.accent,
              onTap: flow.busy ? null : flow.send,
            ),
          AppButton(
            label: 'Done',
            trailingIcon: AppIcons.check,
            busy: flow.busy,
            onTap: flow.busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ],
    ),
  );
}
