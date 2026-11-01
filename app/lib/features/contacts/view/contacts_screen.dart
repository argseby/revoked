import 'package:flutter/material.dart';

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
            'Send something to someone, or ask them for something. They keep '
            'what you send until you revoke it.',
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
              title: 'Couldn’t load your contacts',
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
              'Send something to someone, or ask them for something. They '
              'keep what you send until you revoke it.',
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
    title: 'Keep the people you deal with',
    subtitle:
        'Add someone once, then send them a detail or ask them for one '
        'whenever you need to — no link to copy, no attachment to chase.',
    example: const AppEmptyExample(
      title: 'Ada Lovelace',
      detail: 'ada@example.com · on this server',
    ),
    steps: const [
      AppEmptyStep('Add them', 'Their name and their email address'),
      AppEmptyStep(
        'Send or ask',
        'It lands in their app if they have an account here',
      ),
      AppEmptyStep('Revoke any time', 'What you sent stops working at once'),
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

  String _day(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final m = d.month.toString().padLeft(2, '0');
      return '${d.year}-$m-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  void _options(BuildContext context, Contact c) {
    showAppOptionsSheet(
      context: context,
      title: c.name,
      subtitle: _subtitle(c),
      actions: [
        AppSheetAction(
          icon: AppIcons.send,
          label: 'Send them something',
          onTap: () => openSendToContactSheet(context, c),
        ),
        AppSheetAction(
          icon: AppIcons.askFor,
          label: 'Ask them for something',
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
      'Couldn’t rename them',
      subtitle: store.error?.description,
    );
  }

  Future<void> _remove(BuildContext context, Contact c) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Remove ${c.name}?',
      message:
          'They leave your contacts. Anything you already sent them keeps '
          'working until you revoke it.',
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
        'Couldn’t remove them',
        subtitle: store.error?.description,
      );
    }
  }
}
