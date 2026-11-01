import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/shell/view/qr_scan_sheet.dart';

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Gets this device able to encrypt in [workspace], walking the person through
/// whatever is missing. True when it can encrypt now.
Future<bool> ensureSealingReady(BuildContext context, String workspace) async {
  final keys = Stores.keys;
  await keys.ensureLoaded();
  if (keys.canSeal(workspace)) return true;
  if (!context.mounted) return false;

  switch (keys.status) {
    case SealingStatus.ready:
      if (keys.isLockedFor(workspace)) {
        AppToast.error(
          context,
          'Someone else holds this workspace’s key',
          subtitle: 'Only the person who turned on encryption here can use it.',
        );
        return false;
      }
      final ok = await keys.ensureWorkspaceKey(workspace);
      if (!ok && context.mounted) {
        AppToast.error(
          context,
          'Couldn’t turn on encryption',
          subtitle: keys.errorMessage,
        );
      }
      return ok;
    case SealingStatus.notSetUp:
      return await openRecoveryKeySheet(context) == true;
    case SealingStatus.needsThisDevice:
    case SealingStatus.needsConfirmation:
      await openAddThisDeviceSheet(context);
      return keys.canSeal(workspace);
    case SealingStatus.untrusted:
      AppToast.error(
        context,
        'Your device list changed',
        subtitle: 'Check it in Settings before you encrypt anything.',
      );
      return false;
    case SealingStatus.unknown:
    case SealingStatus.unavailable:
      AppToast.error(
        context,
        'Encryption isn’t available right now',
        subtitle: keys.errorMessage,
      );
      return false;
  }
}

/// The one place the recovery key is ever shown. The person must type part of
/// it back before anything is saved, because it can't be shown again and nobody
/// can reset it.
Future<bool?> openRecoveryKeySheet(
  BuildContext context, {
  bool replacing = false,
}) {
  final keys = Stores.keys;
  if (replacing) {
    keys.beginRecoveryReplacement();
  } else {
    keys.beginSetup();
  }
  return showAppSheet<bool>(
    context: context,
    builder: (sheetContext) => Observer(
      builder: (_) {
        final code = keys.recoveryCode ?? '';
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Save your recovery key').header,
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'This key gets you back in if you lose your devices. Nobody '
                  'can reset it for you, not even whoever runs your server. '
                  'Without it, you lose what you’ve encrypted.',
                ).muted,
                const SizedBox(height: AppSpacing.lg),
                AppText(code).mono.selectable,
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  icon: AppIcons.copy,
                  label: 'Copy',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    AppToast.success(
                      sheetContext,
                      'Copied. Put it in your password manager.',
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Type the last two groups to confirm you saved it'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: keys.recoveryConfirm,
                  mono: true,
                  autofocus: true,
                ),
                if (keys.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppErrorText(keys.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        icon: AppIcons.x,
                        label: 'Cancel',
                        style: AppButtonStyle.accent,
                        onTap: keys.isSaving
                            ? null
                            : () {
                                keys.cancelRecovery();
                                Navigator.of(sheetContext).pop(false);
                              },
                      ),
                    ),
                    AppSpacing.gapSm,
                    Expanded(
                      child: AppButton(
                        icon: AppIcons.lock,
                        label: replacing ? 'Replace key' : 'Turn on',
                        busy: keys.isSaving,
                        onTap: keys.recoveryConfirmMatches && !keys.isSaving
                            ? () async {
                                final ok = await keys.finishRecovery(
                                  workspace: Stores.auth.activeWorkspace ?? '',
                                );
                                if (ok && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop(true);
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Shown on a device that isn't on the list yet: a code for a device that is,
/// or the recovery key.
Future<void> openAddThisDeviceSheet(BuildContext context) async {
  final keys = Stores.keys;
  await keys.prepareThisDevice();
  if (!context.mounted) return;
  await showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (sheetContext) => Observer(
      builder: (_) {
        final code = keys.deviceInvite ?? '';
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add this device').header,
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'On a device that can already read your encrypted records, '
                  'open Settings, End-to-end encryption, Add a device. Then '
                  'scan this code or paste it there.',
                ).muted,
                const SizedBox(height: AppSpacing.lg),
                if (code.isNotEmpty) ...[
                  Center(child: AppQrCode(data: code, size: 220)),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    icon: AppIcons.copy,
                    label: 'Copy code',
                    style: AppButtonStyle.accent,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      AppToast.success(sheetContext, 'Copied');
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Check that the other device shows the same code: '
                    '${keys.thisDeviceFingerprint ?? ''}',
                  ).muted.small,
                ],
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Your other device then shows you a code back. Enter it here, '
                  'so this device knows your device list is the real one.',
                ).muted,
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: keys.confirmationInput,
                  hint: 'Paste the code',
                  mono: true,
                ),
                if (_hasCamera) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    icon: AppIcons.qrCode,
                    label: 'Scan the code',
                    style: AppButtonStyle.accent,
                    onTap: () => openQrScanSheet(
                      sheetContext,
                      onCode: (value) {
                        if (DeviceConfirmation.tryParse(value) == null) {
                          return false;
                        }
                        keys.confirmationInput.text = value;
                        return true;
                      },
                    ),
                  ),
                ],
                if (keys.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppErrorText(keys.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  icon: AppIcons.check,
                  label: 'Finish',
                  busy: keys.isSaving,
                  onTap:
                      DeviceConfirmation.tryParse(
                                keys.confirmationInput.text,
                              ) ==
                              null ||
                          keys.isSaving
                      ? null
                      : () async {
                          final ok = await keys.confirmThisDevice(
                            keys.confirmationInput.text,
                          );
                          if (ok && sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _openAddAnotherDeviceSheet(BuildContext context) {
  final keys = Stores.keys;
  keys.deviceCodeInput.clear();
  keys.clearDeviceConfirmation();
  return showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (sheetContext) => Observer(
      builder: (_) {
        final typed = keys.deviceCodeInput.text;
        final fingerprint = keys.fingerprintOfInvite(typed);
        final confirmation = keys.deviceConfirmation;
        if (confirmation != null) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('One last step').header,
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Enter this code on your new device, so it knows your device '
                  'list is the real one.',
                ).muted,
                const SizedBox(height: AppSpacing.lg),
                Center(child: AppQrCode(data: confirmation, size: 220)),
                const SizedBox(height: AppSpacing.md),
                AppText(confirmation).mono.small.selectable,
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  icon: AppIcons.copy,
                  label: 'Copy code',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: confirmation));
                    AppToast.success(sheetContext, 'Copied');
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  icon: AppIcons.check,
                  label: 'Done',
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add a device').header,
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Sign in on the new device and open Add this device. Then '
                'paste its code here. It can read your encrypted records as '
                'soon as you add it.',
              ).muted,
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: keys.deviceCodeInput,
                hint: 'Paste the code',
                mono: true,
                autofocus: true,
              ),
              if (_hasCamera) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  icon: AppIcons.qrCode,
                  label: 'Scan the code',
                  style: AppButtonStyle.accent,
                  onTap: () => openQrScanSheet(
                    sheetContext,
                    onCode: (value) {
                      if (DeviceInvite.tryParse(value) == null) return false;
                      keys.deviceCodeInput.text = value;
                      return true;
                    },
                  ),
                ),
              ],
              if (fingerprint != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Check that the new device shows this too: $fingerprint',
                ).muted.small,
              ],
              if (keys.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppErrorText(keys.errorMessage!),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                icon: AppIcons.personPlus,
                label: 'Add device',
                busy: keys.isSaving,
                onTap: fingerprint == null || keys.isSaving
                    ? null
                    : () => keys.addDevice(typed),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _openRecoverySheet(BuildContext context) {
  final keys = Stores.keys;
  keys.recoveryInput.clear();
  return showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (sheetContext) => Observer(
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Use your recovery key').header,
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Enter the key you saved. This device can then read your '
              'encrypted records.',
            ).muted,
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: keys.recoveryInput,
              hint: 'XXXXX-XXXXX-XXXXX',
              mono: true,
              autofocus: true,
            ),
            if (keys.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppErrorText(keys.errorMessage!),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              icon: AppIcons.lock,
              label: 'Continue',
              busy: keys.isSaving,
              onTap: keys.isSaving
                  ? null
                  : () async {
                      final ok = await keys.restoreWithRecoveryKey();
                      if (ok && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openStartOverSheet(BuildContext context) {
  final keys = Stores.keys;
  keys.startOverConfirm.clear();
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => Observer(
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Start over').header,
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Only do this if you’ve lost every device and your recovery key. '
              'It permanently deletes your encrypted records. Nobody can get '
              'them back. Your other records aren’t affected.',
            ).muted,
            const SizedBox(height: AppSpacing.lg),
            const Text('Type “${KeysStore.startOverPhrase}” to confirm'),
            const SizedBox(height: AppSpacing.xs),
            AppTextField(controller: keys.startOverConfirm, autofocus: true),
            if (keys.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppErrorText(keys.errorMessage!),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    icon: AppIcons.x,
                    label: 'Cancel',
                    style: AppButtonStyle.accent,
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
                AppSpacing.gapSm,
                Expanded(
                  child: AppButton(
                    icon: AppIcons.trash,
                    label: 'Delete and start over',
                    style: AppButtonStyle.destructive,
                    busy: keys.isSaving,
                    onTap: keys.startOverConfirmed && !keys.isSaving
                        ? () async {
                            final ok = await keys.startOver();
                            if (ok) {
                              await Stores.vault.loadRecords();
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            }
                          }
                        : null,
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

/// Settings → End-to-end encryption: which devices can read what you encrypt,
/// and how to get back in if you lose them.
class SealingSection extends StatelessWidget {
  const SealingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        if (keys.isLoading && keys.status == SealingStatus.unknown) {
          return const Center(child: AppSpinner());
        }
        return switch (keys.status) {
          SealingStatus.unknown => _Message(
            text: keys.errorMessage ?? 'Couldn’t reach your server. Try again.',
            action: AppButton(
              icon: AppIcons.arrowClockwise,
              label: 'Try again',
              style: AppButtonStyle.accent,
              onTap: keys.load,
            ),
          ),
          SealingStatus.unavailable => const _Message(
            text: 'Your server doesn’t offer end-to-end encryption yet.',
          ),
          SealingStatus.notSetUp => _Message(
            text:
                'Encrypt the records that matter most, so only your devices '
                'can read them. Not even your server can. You can’t share an '
                'encrypted record yet.',
            action: AppButton(
              icon: AppIcons.lock,
              label: 'Turn on',
              onTap: () => openRecoveryKeySheet(context),
            ),
          ),
          SealingStatus.needsThisDevice => const _NeedsThisDevice(),
          SealingStatus.needsConfirmation => const _NeedsThisDevice(),
          SealingStatus.untrusted => const _Untrusted(),
          SealingStatus.ready => const _Devices(),
        };
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Widget? action;

  const _Message({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text),
        if (action != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(alignment: Alignment.centerLeft, child: action),
        ],
      ],
    );
  }
}

class _NeedsThisDevice extends StatelessWidget {
  const _NeedsThisDevice();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'You’ve encrypted records on another device. Add this one to read '
          'them here.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              icon: AppIcons.personPlus,
              label: 'Add this device',
              onTap: () => openAddThisDeviceSheet(context),
            ),
            AppButton(
              icon: AppIcons.lock,
              label: 'Use your recovery key',
              style: AppButtonStyle.accent,
              onTap: () => _openRecoverySheet(context),
            ),
            AppButton(
              icon: AppIcons.trash,
              label: 'Start over',
              style: AppButtonStyle.destructive,
              onTap: () => _openStartOverSheet(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _Untrusted extends StatelessWidget {
  const _Untrusted();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppAlert(
          destructive: true,
          title: const Text('Your device list changed'),
          content: const Text(
            'It no longer matches what this device remembers. If you didn’t '
            'start over yourself, someone may have tampered with it, so this '
            'device has stopped encrypting and sharing keys.',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            icon: AppIcons.arrowClockwise,
            label: 'Check again',
            style: AppButtonStyle.accent,
            onTap: Stores.keys.load,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            icon: AppIcons.arrowClockwise,
            label: 'I started over: rejoin',
            style: AppButtonStyle.destructive,
            onTap: () async {
              final ok = await showAppDialog(
                context: context,
                title: 'Rejoin from scratch?',
                message:
                    'This device forgets its keys and what it remembered. You’ll '
                    'then need another device or your recovery key to get back '
                    'in. Do this only if you started over yourself.',
                confirmLabel: 'Rejoin',
                confirmIcon: AppIcons.arrowClockwise,
                destructive: true,
              );
              if (ok) await Stores.keys.forgetThisDevice();
            },
          ),
        ),
      ],
    );
  }
}

class _Devices extends StatelessWidget {
  const _Devices();

  Future<void> _remove(BuildContext context, DeviceChainEntry entry) async {
    final others = Stores.keys
        .removalsFor(entry.seq)
        .where((e) => e.seq != entry.seq)
        .map((e) => e.label)
        .toList();
    final ok = await showAppDialog(
      context: context,
      title: 'Remove ${entry.label}?',
      message:
          'It can’t read anything you encrypt from now on. It may still have '
          'copies of what it could already read, so change any secret you’re '
          'worried about.'
          '${others.isEmpty ? '' : ' Anything it added comes off too, because '
                    'you can’t be sure it was you: ${others.join(', ')}.'}',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final done = await Stores.keys.removeDevice(entry.seq);
    if (!done && context.mounted) {
      AppToast.error(
        context,
        'Couldn’t remove it',
        subtitle: Stores.keys.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = Stores.keys;
    final devices = keys.chain.live
        .where((e) => e.kind == DeviceChainEntry.kindDevice)
        .toList();
    final recovery = keys.chain.liveRecovery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (keys.chainBroken) ...[
          AppAlert(
            destructive: true,
            title: const Text(
              'Something on your device list doesn’t check out',
            ),
            content: const Text(
              'This device still reads your records, but it has stopped '
              'encrypting and sharing keys.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (keys.needsNewRecoveryKey) ...[
          AppAlert(
            destructive: true,
            title: const Text('You don’t have a recovery key'),
            content: const Text(
              'If you lose your devices now, you lose what you’ve encrypted. '
              'Make a new key below.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Text(
          'Only these devices can read what you encrypt. Not even your server '
          'can. You can’t share an encrypted record yet.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppListGroup(
          title: 'Your devices',
          trailing: AppButton(
            icon: AppIcons.personPlus,
            label: 'Add a device',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () => _openAddAnotherDeviceSheet(context),
          ),
          children: [
            for (final entry in devices)
              AppEntityCard(
                title: entry.label,
                subtitle: entry.seq == keys.thisDeviceSeq
                    ? 'This device'
                    : KeysStore.fingerprint(
                        entry.hpkePublicKey,
                        entry.signingPublicKey,
                      ),
                actions: [
                  if (entry.seq != keys.thisDeviceSeq)
                    AppSheetAction(
                      icon: AppIcons.trash,
                      label: 'Remove',
                      destructive: true,
                      onTap: () => _remove(context, entry),
                    ),
                ],
              ),
            if (recovery != null)
              AppEntityCard(
                title: recovery.label,
                subtitle: KeysStore.fingerprint(
                  recovery.hpkePublicKey,
                  recovery.signingPublicKey,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            icon: AppIcons.lock,
            label: keys.needsNewRecoveryKey
                ? 'Make a recovery key'
                : 'Replace your recovery key',
            style: AppButtonStyle.accent,
            onTap: () => openRecoveryKeySheet(context, replacing: true),
          ),
        ),
      ],
    );
  }
}
