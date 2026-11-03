import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/webhooks/view/webhooks_page.dart';

/// The new-webhook drawer. Header and footer are pinned; only the form
/// scrolls, so Create stays reachable however long the event list grows.
Future<void> openWebhookCreateSheet(BuildContext context) {
  final store = Stores.webhooks;
  store.resetDraft();
  if (store.eventTypes.isEmpty) store.load();

  return showAppSheet(
    context: context,
    builder: (sheetContext) => Observer(
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.9,
        ),
        child: Column(
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
                  const Text('New webhook').header,
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'Your server gets a short message each time something '
                    'happens here. It says what changed, never the record '
                    'itself.',
                  ).muted.small,
                ],
              ),
            ),
            const AppDivider(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppFormSectionHeader('Where to send'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppTextField(
                        controller: store.draftUrl,
                        label: 'Address',
                        hint: 'https://example.com/hooks/revoked',
                        keyboardType: TextInputType.url,
                        mono: true,
                      ),
                    ),
                    if (store.draftUnreachable)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.sm,
                          AppSpacing.xl,
                          0,
                        ),
                        child: PrivateAddressNotice(),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppTextField(
                        controller: store.draftDescription,
                        label: 'Description',
                        hint: 'e.g. CRM sync',
                      ),
                    ),
                    const AppFormSectionHeader('What it hears'),
                    AppFormToggleRow(
                      label: 'All events',
                      subtitle:
                          'Except share opens and record edits, which you '
                          'pick by name.',
                      value: store.draftEverything,
                      onChanged: store.setDraftEverything,
                    ),
                    if (!store.draftEverything)
                      for (final group in _groups(store.eventTypes)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            AppSpacing.md,
                            AppSpacing.xl,
                            AppSpacing.xxs,
                          ),
                          child: Text(group.key).small.muted,
                        ),
                        for (final t in group.value)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                            ),
                            child: AppCheckRow(
                              label: t.description,
                              subtitle: t.type,
                              value: store.draftEvents.contains(t.type),
                              onChanged: (on) =>
                                  store.toggleDraftEvent(t.type, on),
                            ),
                          ),
                      ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      style: AppButtonStyle.accent,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      icon: AppIcons.plus,
                      label: 'Create webhook',
                      busy: store.isChanging,
                      onTap: store.canCreateDraft && !store.isChanging
                          ? () => _create(ctx, context)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<MapEntry<String, List<WebhookEventType>>> _groups(
  List<WebhookEventType> types,
) {
  final out = <String, List<WebhookEventType>>{};
  for (final t in types) {
    out.putIfAbsent(t.group, () => []).add(t);
  }
  return out.entries.toList();
}

Future<void> _create(BuildContext sheetCtx, BuildContext parent) async {
  final store = Stores.webhooks;
  final secret = await store.create();
  if (!sheetCtx.mounted) return;
  if (secret == null) {
    AppToast.error(
      sheetCtx,
      'Couldn’t create the webhook',
      subtitle: store.errorMessage,
    );
    return;
  }
  Navigator.of(sheetCtx).pop();
  final created = store.endpoints.isEmpty ? null : store.endpoints.first;
  if (!parent.mounted) return;
  await showWebhookSecretDialog(
    parent,
    secret,
    title: 'Your signing secret',
    message:
        'Your server uses it to check that each message came from here. You '
        'can see it again on the webhook’s page.',
  );
  if (created != null && parent.mounted) {
    parent.go(AppRoutes.webhookFor(created.id));
  }
}
