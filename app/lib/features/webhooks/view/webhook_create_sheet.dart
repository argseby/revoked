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
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/webhooks/view/webhooks_page.dart';

/// Clears the last draft and loads the event types, before the form opens.
void prepareWebhookDraft() {
  final store = Stores.webhooks;
  store.resetDraft();
  if (store.eventTypes.isEmpty) store.load();
}

/// The new-webhook form, shown in place on the webhooks page.
class WebhookCreateForm extends StatelessWidget {
  final VoidCallback onClose;

  const WebhookCreateForm({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final store = Stores.webhooks;
    return Observer(
      builder: (ctx) => Column(
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
                  'A notification is posted to the endpoint for each event. '
                  'It identifies what changed, never the record contents.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppFormSectionHeader('Endpoint'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: AppTextField(
                  controller: store.draftDescription,
                  label: 'Description',
                  hint: 'e.g. CRM sync',
                ),
              ),
              const AppFormSectionHeader('Events'),
              AppFormToggleRow(
                label: 'All events',
                subtitle:
                    'Excludes share opens and record edits, which are '
                    'selected individually.',
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
                        onChanged: (on) => store.toggleDraftEvent(t.type, on),
                      ),
                    ),
                ],
              const SizedBox(height: AppSpacing.lg),
            ],
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
                    onTap: onClose,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.plus,
                    label: 'Create webhook',
                    busy: store.isChanging,
                    onTap: store.canCreateDraft && !store.isChanging
                        ? () => _create(context, onClose)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

Future<void> _create(BuildContext parent, VoidCallback close) async {
  final store = Stores.webhooks;
  final secret = await store.create();
  if (!parent.mounted) return;
  if (secret == null) {
    AppToast.error(
      parent,
      'The webhook could not be created',
      subtitle: store.errorMessage,
    );
    return;
  }
  final created = store.endpoints.isEmpty ? null : store.endpoints.first;
  await showWebhookSecretDialog(
    parent,
    secret,
    title: 'Signing secret',
    message:
        'Used by the receiving server to verify that each message '
        'originates here. It remains available on the webhook’s page.',
  );
  close();
  if (created != null && parent.mounted) {
    parent.go(AppRoutes.webhookFor(created.id));
  }
}
