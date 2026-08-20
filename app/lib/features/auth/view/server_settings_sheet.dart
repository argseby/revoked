import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Opens the server-settings drawer used from the login / register screens so
/// the user can point the app at a different backend (IP + port or a domain).
Future<void> openServerSettingsSheet(BuildContext context) {
  return showAppSheet(
    context: context,
    builder: (_) => const ServerSettingsSheet(),
  );
}

class ServerSettingsSheet extends StatelessWidget {
  const ServerSettingsSheet({super.key});

  Future<void> _save(BuildContext context) async {
    final saved = await Stores.serverSettings.save();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Server set to $saved');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = Stores.serverSettings;

    return Padding(
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
          Row(
            children: [
              Icon(AppIcons.server, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              const Text('Server').header,
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Choose which backend this app talks to. Enter an address like '
            '192.168.1.5:3000 or https://your-domain.com.',
          ).muted.small,
          const SizedBox(height: AppSpacing.lg),
          const Text('Server address').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: store.controller,
            hint: 'http://192.168.1.5:3000',
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          Observer(
            builder: (_) {
              final message = store.testMessage;
              if (message == null) return const SizedBox.shrink();
              final ok = store.isReachable == true;
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      ok ? AppIcons.checkCircle : AppIcons.xCircle,
                      size: 16,
                      color: ok ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(message).small),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Observer(
                  builder: (_) => AppButton(
                    icon: AppIcons.shieldCheck,
                    label: 'Test',
                    style: AppButtonStyle.accent,
                    busy: store.isTesting,
                    onTap: store.canSave ? store.test : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Observer(
                  builder: (_) => AppButton(
                    icon: AppIcons.checkCircle,
                    label: 'Save',
                    onTap: store.canSave ? () => _save(context) : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Reset to default',
              style: AppButtonStyle.accent,
              onTap: store.resetToDefault,
            ),
          ),
        ],
      ),
    );
  }
}
