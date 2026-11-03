import 'package:flutter/material.dart';

import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/contacts/view/contact_create_sheet.dart';
import 'package:revoked_app/features/contacts/view/contact_grant_sheets.dart';

/// The people this workspace sends to and asks from. Tap one to send them
/// something or ask them for something.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with RefreshOnEntry {
  @override
  void refresh() => Stores.contacts.loadIfDue();

  @override
  Widget build(BuildContext context) {
    final store = Stores.contacts;
    return AppLoadFade(
      loading: () => store.loadState.isFirstLoad && store.contacts.isEmpty,
      skeleton: const AppListSkeleton(
        intro:
            'Contacts receive records and requests directly. Sent records '
            'stay accessible until revoked.',
        rows: [
          AppSkeletonRow(
            'Ada Lovelace',
            'ada@example.com',
            icon: AppIcons.person,
            badge: 'Verified',
          ),
          AppSkeletonRow(
            'Grace Hopper',
            'grace@example.com',
            icon: AppIcons.person,
          ),
          AppSkeletonRow(
            'Alan Turing',
            'alan@example.com',
            icon: AppIcons.person,
          ),
        ],
      ),
      builder: (_) {
        final failure = store.loadState.error;
        if (store.contacts.isEmpty) {
          if (failure != null) {
            return AppLoadError(
              title: 'Contacts could not be loaded',
              message: failure,
              onRetry: store.load,
            );
          }
          return _empty(context);
        }
        return AppPageBody(
          children: [
            if (failure != null) ...[
              AppRefreshFailed(onRetry: store.load),
              AppSpacing.gapLg,
            ],
            const Text(
              'Contacts receive records and requests directly. Sent records '
              'stay accessible until revoked.',
            ).muted.small,
            AppSpacing.gapMd,
            AppListCard(
              children: [
                for (final c in store.contacts)
                  AppListRow(
                    icon: _icon(c),
                    title: c.name,
                    subtitle: _subtitle(c),
                    trailing: c.trust == ContactTrust.verified
                        ? const AppBadge(
                            icon: AppIcons.shieldCheck,
                            label: 'Verified',
                          )
                        : null,
                    onTap: () => _options(context, c),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) => AppEmptyState(
    icon: AppIcons.personPlus,
    title: 'No contacts',
    subtitle:
        'Contacts receive records and requests directly, without links to '
        'copy or attachments to send.',
    example: const AppEmptyExample(
      title: 'Ada Lovelace',
      detail: 'ada@example.com · on this server',
    ),
    steps: const [
      AppEmptyStep('Contact', 'Name and email address'),
      AppEmptyStep(
        'Delivery',
        'Directly to the app for contacts with an account here',
      ),
      AppEmptyStep('Revocation', 'Sent records stop working immediately'),
    ],
    action: AppButton(
      icon: AppIcons.personPlus,
      label: 'Add a contact',
      onTap: () => openContactCreateSheet(context),
    ),
  );

  IconData _icon(Contact c) {
    if (c.isHere) return AppIcons.person;
    if (c.isPeer) return AppIcons.server;
    return AppIcons.envelope;
  }

  /// Where they are, and when you last sent them something.
  String _subtitle(Contact c) {
    final last = c.lastUsedAt;
    return [
      if (c.isHere) 'In the app · ${c.email}' else c.where,
      ?(last == null ? null : 'last sent ${_day(last)}'),
    ].join(' · ');
  }

  String _day(String iso) => dayOf(iso) ?? iso;

  void _options(BuildContext context, Contact c) {
    showAppOptionsSheet(
      context: context,
      title: c.name,
      subtitle: _subtitle(c),
      actions: [
        AppSheetAction(
          icon: AppIcons.send,
          label: 'Send records',
          onTap: () => openSendToContactSheet(context, c),
        ),
        AppSheetAction(
          icon: AppIcons.askFor,
          label: 'Request data',
          onTap: () => openAskContactSheet(context, c),
        ),
        AppSheetAction(
          icon: AppIcons.pencil,
          label: 'Rename',
          onTap: () => _rename(context, c),
        ),
        AppSheetAction(
          icon: AppIcons.trash,
          label: 'Remove',
          destructive: true,
          onTap: () => _remove(context, c),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, Contact c) async {
    final store = Stores.contacts;
    store.startRename(c.id);
    final save = await showAppEditSheet(
      context: context,
      title: 'Rename contact',
      controller: store.renameName,
      hint: 'e.g. Ada Lovelace',
    );
    if (!save || !context.mounted) return;
    final ok = await store.rename(c.id);
    if (!context.mounted || ok) return;
    AppToast.error(
      context,
      'The contact could not be renamed.',
      subtitle: store.error?.description,
    );
  }

  Future<void> _remove(BuildContext context, Contact c) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Remove ${c.name}?',
      message:
          'The contact is removed. Anything already sent keeps working '
          'until revoked.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final store = Stores.contacts;
    final ok = await store.remove(c.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Contact removed');
    } else {
      AppToast.error(
        context,
        'The contact could not be removed.',
        subtitle: store.error?.description,
      );
    }
  }
}
