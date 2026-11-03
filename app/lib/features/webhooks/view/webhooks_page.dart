import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/status_colors.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/connections/view/day_label.dart';
import 'package:revoked_app/features/webhooks/store/webhooks_store.dart';
import 'package:revoked_app/features/webhooks/view/webhook_create_sheet.dart';

/// The workspace's webhooks, one row each; a row opens the webhook's own page
/// with everything that was sent to it.
class WebhooksList extends StatelessWidget {
  const WebhooksList({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.webhooks;
    return Observer(
      builder: (_) {
        if (store.endpoints.isEmpty && store.loadState.isFirstLoad) {
          return const AppListSkeleton();
        }
        if (store.endpoints.isEmpty && store.loadState.error != null) {
          return AppLoadError(
            title: 'Couldn’t load webhooks',
            message: store.loadState.error!,
            onRetry: store.load,
          );
        }
        if (store.endpoints.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.send,
            title: 'Hear about changes the moment they happen',
            subtitle:
                'Your server gets a message when a share is opened or '
                'revoked, a request is answered, or a record changes. No '
                'asking every few minutes.',
            example: const AppEmptyExample(
              title: 'crm.example.com',
              detail: 'All events · 42 delivered today',
              badge: 'on',
            ),
            steps: const [
              AppEmptyStep('Add your server’s address', 'Pick what it hears'),
              AppEmptyStep('Check the signature', 'Only you can send it'),
              AppEmptyStep('See every delivery', 'Send any of them again'),
            ],
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New webhook',
              onTap: () => openWebhookCreateSheet(context),
            ),
            learnMoreLabel: 'How webhooks work',
            learnMoreUrl: '${AppConfig.docsUrl}/api/webhooks/',
          );
        }
        return AppListGroup(
          title: 'Webhooks',
          footer: const Text(
            'Messages never carry your records. Your server reads what it '
            'needs with an API key.',
          ),
          trailing: AppButton(
            icon: AppIcons.plus,
            label: 'New',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () => openWebhookCreateSheet(context),
          ),
          children: [
            for (final e in store.endpoints)
              AppListRow(
                icon: AppIcons.send,
                title: e.host,
                subtitle: _summary(e),
                trailing: _stateBadge(e),
                onTap: () => context.go(AppRoutes.webhookFor(e.id)),
              ),
          ],
        );
      },
    );
  }
}

String _summary(WebhookEndpoint e) => [
  if (e.description.isNotEmpty) e.description,
  _eventsLabel(e),
  _todayLabel(e),
].join(' · ');

String _eventsLabel(WebhookEndpoint e) {
  if (e.sendsEverything) return 'All events';
  return e.events.length == 1 ? e.events.first : '${e.events.length} events';
}

String _todayLabel(WebhookEndpoint e) {
  final sent = e.succeeded + e.failed;
  if (sent == 0 && e.pending == 0) return 'Nothing sent today';
  return [
    '${e.succeeded} delivered today',
    if (e.failed > 0) '${e.failed} failed',
    if (e.pending > 0) '${e.pending} waiting',
  ].join(', ');
}

Widget? _stateBadge(WebhookEndpoint e) {
  if (!e.enabled) {
    return AppBadge(
      label: e.disabledReason == 'failing' ? 'Turned off' : 'Off',
      variant: e.disabledReason == 'failing'
          ? AppBadgeVariant.destructive
          : AppBadgeVariant.secondary,
    );
  }
  if (e.isFailing) {
    return const AppBadge(
      icon: AppIcons.exclamationTriangle,
      label: 'Failing',
      variant: AppBadgeVariant.destructive,
    );
  }
  return null;
}

/// One webhook: where it sends, what it hears, its signing secret, and the
/// log of every delivery with a way to send each again.
/// Said where a webhook points at this machine or a private network and the
/// server won't deliver there, before anyone waits for one that never comes.
class PrivateAddressNotice extends StatelessWidget {
  const PrivateAddressNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppAlert(
      tone: AppAlertTone.warning,
      leading: Icon(AppIcons.exclamationTriangle),
      title: Text('This server won’t deliver here'),
      content: Text(
        'It doesn’t send webhooks to local or private addresses. Whoever '
        'runs the server can allow them with ALLOW_PRIVATE_CALLBACKS=true.',
      ),
    );
  }
}

class WebhookEndpointPage extends StatefulWidget {
  final String endpointId;

  const WebhookEndpointPage({super.key, required this.endpointId});

  @override
  State<WebhookEndpointPage> createState() => _WebhookEndpointPageState();
}

class _WebhookEndpointPageState extends State<WebhookEndpointPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      final store = Stores.webhooks;
      if (store.endpoint(widget.endpointId) == null) {
        store.load();
      } else {
        store.loadIfDue();
      }
      store.loadDeliveries(widget.endpointId);
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  void _back() => context.go(AppRoutes.webhooks);

  Widget _title(BuildContext context) => Observer(
    builder: (_) => AppBarTitle(
      title: Stores.webhooks.endpoint(widget.endpointId)?.host ?? 'Webhook',
      onBack: _back,
    ),
  );

  Future<void> _showSecret(WebhookEndpoint e) async {
    final secret = await Stores.webhooks.revealSecret(e.id);
    if (!mounted) return;
    if (secret == null) {
      AppToast.error(
        context,
        'Couldn’t show the secret',
        subtitle: Stores.webhooks.errorMessage,
      );
      return;
    }
    await showWebhookSecretDialog(
      context,
      secret,
      title: 'Signing secret',
      message: 'Your server uses it to check that a message came from here.',
    );
  }

  Future<void> _rotate(WebhookEndpoint e) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Make a new secret?',
      message:
          'The old one keeps working for 24 hours, so you have time to '
          'switch your server over.',
      confirmLabel: 'Make new secret',
      confirmIcon: AppIcons.arrowRepeat,
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;
    final secret = await Stores.webhooks.rotateSecret(e.id);
    if (!mounted) return;
    if (secret == null) {
      AppToast.error(
        context,
        'Couldn’t make a new secret',
        subtitle: Stores.webhooks.errorMessage,
      );
      return;
    }
    await showWebhookSecretDialog(
      context,
      secret,
      title: 'Your new secret',
      message: 'Put it on your server within 24 hours.',
    );
  }

  Future<void> _setEnabled(WebhookEndpoint e, bool enabled) async {
    final store = Stores.webhooks;
    if (!await store.setEnabled(e.id, enabled) && mounted) {
      AppToast.error(
        context,
        enabled ? 'Couldn’t turn it on' : 'Couldn’t turn it off',
        subtitle: store.errorMessage,
      );
    }
  }

  Future<void> _resendFailed(WebhookEndpoint e) async {
    final store = Stores.webhooks;
    final n = await store.resendFailed(e.id);
    if (!mounted) return;
    if (n == null) {
      AppToast.error(context, 'Couldn’t resend', subtitle: store.errorMessage);
    } else if (n == 0) {
      AppToast.success(context, 'Nothing failed in the last day');
    } else {
      AppToast.success(
        context,
        n == 1 ? 'Sending 1 message again' : 'Sending $n messages again',
      );
    }
  }

  Future<void> _delete(WebhookEndpoint e) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Delete this webhook?',
      message:
          'Nothing more is sent to ${e.host}, and its delivery log goes too.',
      confirmLabel: 'Delete',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await Stores.webhooks.delete(e.id)) {
      if (mounted) _back();
    } else if (mounted) {
      AppToast.error(
        context,
        'Couldn’t delete',
        subtitle: Stores.webhooks.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.webhooks;
    final e = store.endpoint(widget.endpointId);
    if (e == null) {
      if (store.loadState.isFirstLoad || !store.loadState.hasLoaded) {
        return const AppDetailSkeleton();
      }
      return AppEmptyState(
        icon: AppIcons.send,
        title: 'Webhook not found',
        subtitle: 'It may have been deleted.',
        action: AppButton(
          icon: AppIcons.arrowLeft,
          label: 'Back to webhooks',
          style: AppButtonStyle.accent,
          onTap: _back,
        ),
      );
    }

    return AppDetailPage(
      header: AppDetailHeader(
        badges: [
          AppBadge(
            label: e.enabled ? 'On' : 'Off',
            variant: e.enabled
                ? AppBadgeVariant.primary
                : AppBadgeVariant.secondary,
          ),
          if (e.isFailing)
            const AppBadge(
              icon: AppIcons.exclamationTriangle,
              label: 'Failing',
              variant: AppBadgeVariant.destructive,
            ),
        ],
        title: e.host,
        subtitle: e.url,
        subtitleMono: true,
      ),
      sections: [
        if (Stores.webhooks.unreachable(e.url)) const PrivateAddressNotice(),
        if (!e.enabled && e.disabledReason == 'failing')
          AppListGroup(
            title: 'Turned off',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'Nothing reached this address for three days. Fix your server, '
              'turn the webhook back on, then resend what it missed.',
            ),
            children: const [],
          ),
        AppListGroup(
          title: 'Last 24 hours',
          trailing: const SizedBox.shrink(),
          footer: e.isFailing
              ? Text(
                  'Failing since ${dayLabel(e.failingSince?.toIso8601String())}. Failed messages '
                  'are tried again for about a day and a half. After three '
                  'days without success the webhook turns itself off.',
                )
              : null,
          children: [
            AppDetailRow(
              icon: AppIcons.checkCircle,
              label: 'Delivered',
              value: '${e.succeeded}',
            ),
            AppDetailRow(
              icon: AppIcons.xCircle,
              label: 'Failed',
              value: '${e.failed}',
            ),
            AppDetailRow(
              icon: AppIcons.hourglass,
              label: 'Waiting',
              value: '${e.pending}',
            ),
          ],
        ),
        AppListGroup(
          title: 'What it hears',
          trailing: const SizedBox.shrink(),
          footer: e.sendsEverything
              ? const Text(
                  'Every event, except share opens and record edits. Those '
                  'are frequent, so they are sent only when picked by name.',
                )
              : null,
          children: [
            if (e.sendsEverything)
              const AppDetailRow(icon: AppIcons.collection, label: 'All events')
            else
              for (final t in e.events)
                AppDetailRow(
                  icon: AppIcons.tag,
                  label: _describe(t),
                  value: t,
                  valueMono: true,
                ),
          ],
        ),
        AppListGroup(
          title: 'Signing secret',
          trailing: const SizedBox.shrink(),
          footer: const Text(
            'Every message carries a Revoked-Signature header made with this '
            'secret. Check it before you trust the message.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.eye,
              label: 'Show secret',
              onTap: () => _showSecret(e),
            ),
            AppDetailRow(
              icon: AppIcons.arrowRepeat,
              label: 'Make a new secret',
              onTap: store.isChanging ? null : () => _rotate(e),
            ),
          ],
        ),
        _TestEvent(endpoint: e),
        _DeliveryLog(endpoint: e),
        AppDetailManage(
          actions: [
            AppButton(
              label: 'Resend failed',
              icon: AppIcons.arrowClockwise,
              style: AppButtonStyle.accent,
              busy: store.isChanging,
              onTap: !e.enabled || store.isChanging
                  ? null
                  : () => _resendFailed(e),
            ),
            if (e.enabled)
              AppButton(
                label: 'Turn off',
                icon: AppIcons.pause,
                style: AppButtonStyle.accent,
                onTap: store.isChanging ? null : () => _setEnabled(e, false),
              )
            else
              AppButton(
                label: 'Turn on',
                icon: AppIcons.play,
                onTap: store.isChanging ? null : () => _setEnabled(e, true),
              ),
            AppButton(
              label: 'Delete',
              icon: AppIcons.trash,
              style: AppButtonStyle.destructive,
              onTap: store.isChanging ? null : () => _delete(e),
            ),
          ],
        ),
      ],
    );
  }
}

String _describe(String type) {
  for (final t in Stores.webhooks.eventTypes) {
    if (t.type == type) return t.description;
  }
  return type;
}

/// Sends one sample event through the real path, so a wrong address or a
/// signature check that fails shows up before the first real event.
class _TestEvent extends StatelessWidget {
  final WebhookEndpoint endpoint;

  const _TestEvent({required this.endpoint});

  Future<void> _send(BuildContext context) async {
    final store = Stores.webhooks;
    final delivery = await store.sendTest(endpoint.id);
    if (!context.mounted) return;
    if (delivery == null) {
      AppToast.error(
        context,
        'Couldn’t send the test',
        subtitle: store.errorMessage,
      );
      return;
    }
    if (delivery.status == 'succeeded') {
      AppToast.success(
        context,
        'Delivered',
        subtitle: 'Your server answered ${delivery.lastStatus}.',
      );
    } else {
      AppToast.error(context, 'Not delivered', subtitle: _outcome(delivery));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.webhooks;
    return AppListGroup(
      title: 'Send a test',
      trailing: const SizedBox.shrink(),
      footer: const Text(
        'A sample with "test": true, so your server can tell it from a '
        'real one.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) => Observer(
              builder: (_) {
                final select = AppSelect<String>(
                  value: store.testType,
                  items: [
                    for (final t in store.eventTypes)
                      AppSelectItem(t.type, Text(t.type).mono),
                  ],
                  onChanged: (v) {
                    if (v != null) store.setTestType(v);
                  },
                );
                final button = AppButton(
                  icon: AppIcons.send,
                  label: 'Send test',
                  style: AppButtonStyle.accent,
                  busy: store.sendingId == endpoint.id,
                  onTap: store.sendingId != null || store.eventTypes.isEmpty
                      ? null
                      : () => _send(context),
                );
                if (constraints.maxWidth < AppSpacing.narrowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      select,
                      const SizedBox(height: AppSpacing.sm),
                      button,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: select),
                    const SizedBox(width: AppSpacing.sm),
                    button,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The deliveries to one webhook, newest first, filterable by outcome.
class _DeliveryLog extends StatelessWidget {
  final WebhookEndpoint endpoint;

  const _DeliveryLog({required this.endpoint});

  @override
  Widget build(BuildContext context) {
    final store = Stores.webhooks;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A status beside the title and four filter labels side by side
        // both crowd a phone, so there the status leads the subtitle and the
        // filter is a dropdown.
        final narrow = constraints.maxWidth < AppSpacing.narrowWidth;
        return Observer(
          builder: (_) {
            final rows = store.deliveries[endpoint.id];
            final loading = store.loadingDeliveries.contains(endpoint.id);
            return AppListGroup(
              title: 'Deliveries',
              noun: 'deliveries',
              previewCount: 20,
              trailing: AppButton(
                icon: AppIcons.arrowClockwise,
                tooltip: 'Refresh',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                busy: loading,
                onTap: loading ? null : () => store.loadDeliveries(endpoint.id),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: narrow
                      ? AppSelect<DeliveryFilter>(
                          value: store.filter,
                          items: [
                            for (final f in DeliveryFilter.values)
                              AppSelectItem(f, Text(f.label)),
                          ],
                          onChanged: (f) {
                            if (f != null) store.setFilter(f, endpoint.id);
                          },
                        )
                      : AppSegmented<DeliveryFilter>(
                          value: store.filter,
                          items: [
                            for (final f in DeliveryFilter.values)
                              AppSegmentedItem(value: f, label: f.label),
                          ],
                          onChanged: (f) => store.setFilter(f, endpoint.id),
                        ),
                ),
                if (rows == null && loading)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: AppListSkeleton(embedded: true),
                  )
                else if (rows == null || rows.isEmpty)
                  AppDetailRow(
                    icon: AppIcons.info,
                    label: store.filter == DeliveryFilter.all
                        ? 'Nothing sent yet'
                        : 'Nothing here',
                  )
                else
                  for (final d in rows)
                    AppListRow(
                      icon: d.test ? AppIcons.flask : AppIcons.send,
                      title: d.type,
                      subtitle: narrow
                          ? '${StatusColors.displayLabel(d.status)} · '
                                '${_deliveryLine(d)}'
                          : _deliveryLine(d),
                      trailing: narrow ? null : StatusLabel(d.status),
                      onTap: () => openWebhookDeliverySheet(context, d),
                    ),
              ],
            );
          },
        );
      },
    );
  }
}

String _deliveryLine(WebhookDelivery d) => [
  _when(d.created),
  if (d.lastStatus > 0) 'HTTP ${d.lastStatus}',
  if (d.attempts > 1) '${d.attempts} tries',
  if (d.status == 'pending' && d.nextAttemptAt != null)
    'next try ${_when(d.nextAttemptAt)}',
  if (d.test) 'test',
].join(' · ');

String _when(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return hm;
  }
  return '${dayLabel(t.toIso8601String())} $hm';
}

String _outcome(WebhookDelivery d) {
  if (d.lastError.isNotEmpty && d.lastStatus == 0) return d.lastError;
  if (d.lastStatus > 0) return 'Your server answered ${d.lastStatus}.';
  return 'It wasn’t sent yet.';
}

/// Shows a secret once, with a way to copy it.
Future<void> showWebhookSecretDialog(
  BuildContext context,
  String secret, {
  required String title,
  required String message,
}) async {
  final copy = await showAppDialog(
    context: context,
    title: title,
    message: message,
    content: Text(secret).mono.selectable,
    confirmLabel: 'Copy',
    confirmIcon: AppIcons.copy,
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: secret));
}

/// One delivery: what was sent, every try and what the server answered, and
/// the way to send it again.
Future<void> openWebhookDeliverySheet(
  BuildContext context,
  WebhookDelivery summary,
) {
  final store = Stores.webhooks;
  store.loadDelivery(summary.id);
  return showAppSheet(
    context: context,
    dismissible: true,
    builder: (sheetContext) => Observer(
      builder: (ctx) {
        final d = store.details[summary.id] ?? summary;
        final scheme = Theme.of(ctx).colorScheme;
        final payload = d.payload;
        Widget code(String text) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: AppRadius.allMd,
          ),
          child: Text(text).mono.small.selectable,
        );
        return ConstrainedBox(
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
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(d.type).header.mono,
                        StatusLabel(d.status),
                        if (d.test) const AppBadge(label: 'Test'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(_deliveryLine(d)).muted.small,
                  ],
                ),
              ),
              const AppDivider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Tries').header,
                      const SizedBox(height: AppSpacing.sm),
                      if (d.attemptLog.isEmpty)
                        Text(
                          d.status == 'pending'
                              ? 'Not tried yet.'
                              : 'No tries were recorded.',
                        ).muted
                      else
                        for (final a in d.attemptLog) ...[
                          _AttemptRow(attempt: a),
                          if (a.responseBody.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            code(a.responseBody),
                          ],
                          const SizedBox(height: AppSpacing.md),
                        ],
                      const SizedBox(height: AppSpacing.md),
                      const Text('What was sent').header,
                      const SizedBox(height: AppSpacing.sm),
                      if (payload == null)
                        const AppListSkeleton(embedded: true)
                      else
                        code(
                          const JsonEncoder.withIndent('  ').convert(payload),
                        ),
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
                        label: 'Close',
                        style: AppButtonStyle.accent,
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppButton(
                        icon: AppIcons.arrowClockwise,
                        label: 'Resend',
                        busy: store.sendingId == d.id,
                        onTap: store.sendingId != null
                            ? null
                            : () => _resend(ctx, d),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _resend(BuildContext context, WebhookDelivery d) async {
  final store = Stores.webhooks;
  final fresh = await store.resend(d);
  if (!context.mounted) return;
  if (fresh == null) {
    AppToast.error(context, 'Couldn’t resend', subtitle: store.errorMessage);
  } else if (fresh.attemptLog.isNotEmpty && fresh.attemptLog.first.ok) {
    AppToast.success(context, 'Delivered');
  } else {
    AppToast.error(
      context,
      'Not delivered',
      subtitle: fresh.attemptLog.isEmpty
          ? null
          : _attemptLine(fresh.attemptLog.first),
    );
  }
}

String _attemptLine(WebhookAttempt a) => [
  if (a.responseStatus > 0) 'HTTP ${a.responseStatus}' else a.error,
  '${a.durationMs} ms',
  _when(a.created),
  if (a.manual) 'sent by hand',
].where((s) => s.isNotEmpty).join(' · ');

class _AttemptRow extends StatelessWidget {
  final WebhookAttempt attempt;

  const _AttemptRow({required this.attempt});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusLabel(attempt.ok ? 'succeeded' : 'failed'),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(_attemptLine(attempt)).small),
      ],
    );
  }
}
