import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/sealing/store/member_keys_store.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/shell/view/qr_scan_sheet.dart';

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void _showLockedWorkspace(BuildContext context) => AppToast.error(
  context,
  'Another account holds this workspace’s key',
  subtitle:
      'Only the account that turned on encryption here can use it. '
      'Sharing the key with other members is not possible yet.',
);

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
        _showLockedWorkspace(context);
        return false;
      }
      final ok = await keys.ensureWorkspaceKey(workspace);
      if (!ok && context.mounted && keys.isLockedFor(workspace)) {
        // Someone else turned it on here since this device last looked.
        _showLockedWorkspace(context);
      } else if (!ok && context.mounted) {
        AppToast.error(
          context,
          'Encryption could not be turned on',
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
        'The device list changed',
        subtitle: 'Review it in Settings before encrypting anything.',
      );
      return false;
    case SealingStatus.unknown:
    case SealingStatus.unavailable:
      AppToast.error(
        context,
        'Encryption is currently unavailable',
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
                const Text('New recovery key').header,
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'This key restores access if every device is lost. It '
                  'cannot be reset, not even by the server operator. Without '
                  'it, encrypted records are lost.',
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
                      'Copied. Store it in a password manager.',
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Enter the last two groups to confirm it was saved'),
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
                                if (ok) {
                                  unawaited(Stores.identities.syncSealedKeys());
                                }
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
                  'Scan or paste this code on a device that can already read '
                  'encrypted records, under Settings → End-to-end encryption '
                  '→ Add a device.',
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
                    'The other device must show the same code: '
                    '${keys.thisDeviceFingerprint ?? ''}',
                  ).muted.small,
                ],
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'The other device then shows a confirmation code. Entering '
                  'it here lets this device confirm the device list is '
                  'genuine.',
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
                          if (ok) {
                            unawaited(Stores.identities.syncSealedKeys());
                          }
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Confirmation code').header,
                if (keys.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppErrorText(keys.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Enter this code on the new device so it can confirm the '
                  'device list is genuine.',
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add a device').header,
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'After sign-in, the new device shows its code under Add this '
                'device. Once added here, it can read encrypted records.',
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
                  'The new device must show the same code: $fingerprint',
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
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Use your recovery key').header,
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'With the recovery key, this device can read encrypted records. '
              'All other devices are removed from the list and must be added '
              'again.',
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
                      if (ok) {
                        unawaited(Stores.identities.syncSealedKeys());
                      }
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
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Start over').header,
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Intended only for when every device and the recovery key are '
              'lost. All encrypted records are permanently deleted and cannot '
              'be recovered. Other records are not affected.',
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
          return const AppListSkeleton(embedded: true);
        }
        return switch (keys.status) {
          SealingStatus.unknown => AppLoadError(
            title: 'The devices could not be loaded',
            message: keys.errorMessage ?? 'The server could not be reached.',
            onRetry: keys.load,
          ),
          SealingStatus.unavailable => const _Message(
            text: 'This server does not offer end-to-end encryption yet.',
          ),
          SealingStatus.notSetUp => _Message(
            text:
                'Encrypted records are readable only on this account’s '
                'devices, and on those of members given access, not by the '
                'server. Links cannot show them yet.',
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
    return Observer(
      builder: (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (Stores.keys.removedFromList) ...[
              AppAlert(
                destructive: true,
                title: const Text(
                  'This device was removed from the device list',
                ),
                content: Text(
                  Stores.keys.chain.liveRecovery != null
                      ? 'If this was not done from another device, someone '
                            'else may have access. The recovery key removes '
                            'every other device from the list.'
                      : 'If this was not done from another device, someone '
                            'else has access and has also removed the recovery '
                            'key. Sign out everywhere else from a device still '
                            'on the list. Without one, the only option is to '
                            'start over.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const Text(
              'Records were encrypted on another device. This device must be '
              'added to read them.',
            ),
            if (Stores.keys.chain.livePasskeys.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              const _PasskeyWayIn(),
            ],
            if (Stores.keys.passkeyError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppErrorText(Stores.keys.passkeyError!),
            ],
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
      },
    );
  }
}

/// On a device the list doesn't name, when a passkey on the list could let it
/// in: which one, and the way to use it. Says nothing a passkey can't deliver.
class _PasskeyWayIn extends StatelessWidget {
  const _PasskeyWayIn();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        final names = keys.chain.livePasskeys.map((e) => e.label).join(', ');
        if (keys.thisPasskeyCredentialId != null) {
          return const Text(
            'The passkey used to sign in here does not hold the key yet. Once '
            'this device is added another way, it will.',
          ).muted;
        }
        if (keys.passkeyWithoutSecret) {
          return Text(
            'The passkey cannot unlock them on this device. Signing in with '
            '$names on a supported device would.',
          ).muted;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signing in with $names unlocks them here.').muted,
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              icon: AppIcons.key,
              label: 'Sign in with your passkey',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => Stores.auth.beginSignIn(),
            ),
          ],
        );
      },
    );
  }
}

/// The one button that gets the passkey this session signed in with to hold
/// the key, whatever that takes right now. Nothing when it can't be done here.
class _PasskeyConnectButton extends StatelessWidget {
  /// Beside a line of small text, the label is one word.
  final bool compact;

  const _PasskeyConnectButton({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        if (keys.passkeyWithoutSecret) return const SizedBox.shrink();
        if (keys.canConnectPasskey) {
          return AppButton(
            icon: AppIcons.key,
            label: compact ? 'Connect' : 'Connect your passkey',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            busy: keys.isSaving,
            onTap: keys.isSaving ? null : () => keys.connectPasskey(),
          );
        }
        return AppButton(
          icon: AppIcons.key,
          label: compact ? 'Sign in with passkey' : 'Sign in with your passkey',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => Stores.auth.beginSignIn(),
        );
      },
    );
  }
}

/// Under the encryption toggle: where the value will be readable once saved.
/// One line, indented to the toggle's text, so it reads as part of the row.
class SealedReadabilityNote extends StatelessWidget {
  final String workspace;

  const SealedReadabilityNote({super.key, required this.workspace});

  /// A list tile's text starts after its icon and the gap beside it.
  static const double _indent = AppSpacing.gigantic;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        if (!keys.canSeal(workspace)) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final passkeys = keys.chain.livePasskeys;
        final thisDevice =
            keys.chain.bySeq(keys.thisDeviceSeq ?? 0)?.label ?? 'This device';
        final Widget badge;
        final String text;
        Widget? action;
        if (passkeys.isNotEmpty) {
          badge = AppBadge(
            icon: AppIcons.check,
            label: 'Opens on your devices',
            accent: scheme.success,
          );
          text =
              '$thisDevice · passkey ${passkeys.map((e) => e.label).join(', ')}';
        } else {
          badge = AppBadge(
            icon: AppIcons.exclamationTriangle,
            label: 'This device only',
            accent: scheme.warning,
          );
          text = keys.passkeyWithoutSecret
              ? 'The passkey cannot carry the key on this device'
              : 'Readable on a phone once the passkey is connected';
          if (!keys.passkeyWithoutSecret) {
            action = const _PasskeyConnectButton(compact: true);
          }
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, left: _indent),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [badge, Text(text).small.muted, ?action],
          ),
        );
      },
    );
  }
}

/// The question the settings page is really asked: on which devices do my
/// encrypted records open, and who else can read them.
class _WhereRecordsOpen extends StatelessWidget {
  final KeysStore keys;
  final List<DeviceChainEntry> passkeys;
  final DeviceChainEntry? recovery;

  /// Takes a passkey off the list. The row is the only place it is shown, so
  /// it is also the only place it can be removed from.
  final void Function(DeviceChainEntry) onRemovePasskey;

  const _WhereRecordsOpen({
    required this.keys,
    required this.passkeys,
    required this.recovery,
    required this.onRemovePasskey,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final thisDevice = keys.chain.bySeq(keys.thisDeviceSeq ?? 0);
        Icon holds() => Icon(AppIcons.checkCircle, color: scheme.success);
        Icon missing() =>
            Icon(AppIcons.exclamationTriangle, color: scheme.warning);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Where encrypted records open',
              trailing: const SizedBox.shrink(),
              children: [
                AppListRow(
                  leading: holds(),
                  title: thisDevice?.label ?? 'This device',
                  subtitle: 'This device · holds the key',
                  showChevron: false,
                ),
                if (passkeys.isEmpty)
                  AppListRow(
                    leading: missing(),
                    title: 'Your passkey',
                    subtitle: keys.passkeyWithoutSecret
                        ? 'Cannot carry the key on this device'
                        : 'Not connected yet',
                    showChevron: false,
                  )
                else
                  for (final entry in passkeys)
                    AppListRow(
                      leading: holds(),
                      title: entry.label,
                      subtitle:
                          entry.credentialId == keys.thisPasskeyCredentialId
                          ? 'Passkey · signed in here · opens them on any '
                                'device signed in with it'
                          : 'Passkey · opens them on any device signed in '
                                'with it',
                      showChevron: false,
                      trailing: AppButton(
                        icon: AppIcons.trash,
                        tooltip: 'Remove ${entry.label}',
                        style: AppButtonStyle.ghost,
                        size: AppButtonSize.small,
                        onTap: () => onRemovePasskey(entry),
                      ),
                    ),
                AppListRow(
                  leading: recovery == null ? missing() : holds(),
                  title: 'Your recovery key',
                  subtitle: recovery == null
                      ? 'None. Without one, losing every device loses all '
                            'encrypted records.'
                      : 'Saved · restores access if every device is lost',
                  showChevron: false,
                ),
                AppListRow(
                  leading: Icon(AppIcons.shieldSlash, color: scheme.outline),
                  title: 'Other people in your workspace',
                  subtitle: 'Cannot read them yet. They see a locked row.',
                  showChevron: false,
                ),
              ],
            ),
            if (passkeys.isEmpty && !keys.passkeyWithoutSecret) ...[
              AppAlert(
                tone: AppAlertTone.warning,
                leading: const Icon(AppIcons.exclamationTriangle),
                title: const Text('Passkey not connected'),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Until it is, a new device needs a code from this one '
                      'to read encrypted records.',
                    ),
                    SizedBox(height: AppSpacing.sm),
                    _PasskeyConnectButton(),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        );
      },
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
          title: const Text('The device list changed'),
          content: const Text(
            'It no longer matches what this device recorded. Unless '
            'encryption was started over from this account, it may have been '
            'tampered with. This device has stopped encrypting and sharing '
            'keys.',
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
                    'This device stops trusting the old list. Another device '
                    'or the recovery key is then required to regain access. '
                    'Only appropriate after a deliberate start-over.',
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
    if (!context.mounted) return;
    if (!done) {
      AppToast.error(
        context,
        'The device could not be removed',
        subtitle: Stores.keys.errorMessage,
      );
      return;
    }
    await _signOutOthers(context);
  }

  Future<void> _signOutOthers(BuildContext context) async {
    final go = await showAppDialog(
      context: context,
      title: 'Sign out everywhere else?',
      message:
          'A lost device may still be signed in. It cannot read anything '
          'encrypted from now on, but it can read unencrypted records until '
          'it is signed out. Other devices must sign in again.',
      confirmLabel: 'Sign out everywhere else',
      confirmIcon: AppIcons.lock,
      destructive: true,
    );
    if (!go || !context.mounted) return;
    final ok = await Stores.keys.signOutOtherSessions();
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Other sessions signed out');
    } else {
      AppToast.error(
        context,
        'The other sessions could not be signed out',
        subtitle: Stores.keys.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        final devices = keys.chain.live
            .where((e) => e.kind == DeviceChainEntry.kindDevice)
            .toList();
        final passkeys = keys.chain.livePasskeys;
        final recovery = keys.chain.liveRecovery;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (keys.chainBroken) ...[
              AppAlert(
                destructive: true,
                title: const Text('The device list failed verification'),
                content: const Text(
                  'This device can still read records, but has stopped '
                  'encrypting and sharing keys.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (keys.unreviewedEntries.isNotEmpty) ...[
              AppAlert(
                destructive: true,
                title: const Text('New on the device list'),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${keys.unreviewedEntries.map((e) => e.action == DeviceChainEntry.actionRemove ? 'A removal' : e.label).join(', ')} '
                      'came from another device. If that wasn’t you, remove that '
                      'device.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      icon: AppIcons.check,
                      label: 'That was me',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: keys.acknowledgeNewEntries,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (keys.needsNewRecoveryKey) ...[
              AppAlert(
                destructive: true,
                title: const Text('No recovery key'),
                content: const Text(
                  'If every device is lost now, encrypted records are lost. A '
                  'new key can be made below.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _WhereRecordsOpen(
              keys: keys,
              passkeys: passkeys,
              recovery: recovery,
              onRemovePasskey: (entry) => _remove(context, entry),
            ),
            const Text(
              'Only these devices can read encrypted records, not the server, '
              'along with the devices of members given access below.',
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
                // Rows, not cards: a card of its own inside the group's card
                // draws a second outline around every device.
                for (final entry in devices)
                  AppListRow(
                    icon: AppIcons.device,
                    title: entry.label,
                    subtitle: entry.seq == keys.thisDeviceSeq
                        ? 'This device'
                        : KeysStore.fingerprint(
                            entry.hpkePublicKey,
                            entry.signingPublicKey,
                          ),
                    showChevron: false,
                    trailing: entry.seq == keys.thisDeviceSeq
                        ? null
                        : AppButton(
                            icon: AppIcons.trash,
                            tooltip: 'Remove ${entry.label}',
                            style: AppButtonStyle.ghost,
                            size: AppButtonSize.small,
                            onTap: () => _remove(context, entry),
                          ),
                  ),
              ],
            ),
            if (keys.passkeyError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppErrorText(keys.passkeyError!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  icon: AppIcons.key,
                  label: keys.needsNewRecoveryKey
                      ? 'Create recovery key'
                      : 'Replace recovery key',
                  style: AppButtonStyle.accent,
                  onTap: () => openRecoveryKeySheet(context, replacing: true),
                ),
                AppButton(
                  icon: AppIcons.boxArrowLeft,
                  label: 'Sign out everywhere else',
                  style: AppButtonStyle.accent,
                  onTap: () => _signOutOthers(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Members(),
          ],
        );
      },
    );
  }
}

/// The workspace's members as this device sees their keys. Nobody is handed
/// anything here yet; this is where fingerprints are compared, so a later
/// grant only goes to a list the person had a chance to check.
class _Members extends StatelessWidget {
  const _Members();

  static String _stateLabel(MemberKeyState state) => switch (state) {
    MemberKeyState.notSetUp => 'Encryption off',
    MemberKeyState.broken => 'Failed verification',
    MemberKeyState.trusted => 'Not verified',
    MemberKeyState.verified => 'Verified',
    MemberKeyState.changed => 'Keys changed',
  };

  static AppBadgeVariant _stateVariant(MemberKeyState state) => switch (state) {
    MemberKeyState.verified => AppBadgeVariant.primary,
    MemberKeyState.broken ||
    MemberKeyState.changed => AppBadgeVariant.destructive,
    _ => AppBadgeVariant.outline,
  };

  Future<void> _verify(BuildContext context, MemberKeys member) async {
    final own = Stores.keys.ownFingerprint;
    final ok = await showAppDialog(
      context: context,
      title: 'Compare fingerprints with ${member.email}',
      icon: AppIcons.shieldCheck,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'In person or on a call, not through this app or the server. '
            'Both of you should see the same two numbers.',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppText('Theirs').small.bold,
          AppText(member.fingerprint ?? '').mono.selectable,
          if (own != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppText('Yours').small.bold,
            AppText(own).mono.selectable,
          ],
        ],
      ),
      confirmLabel: 'They match',
      confirmIcon: AppIcons.check,
    );
    if (!ok) return;
    await Stores.memberKeys.markVerified(member.user);
    // A key they handed over waited for exactly this.
    final waiting = Stores.keys.pendingGrants.values.any(
      (granters) => granters.contains(member.user),
    );
    if (waiting) await Stores.keys.load();
  }

  Future<void> _grant(BuildContext context, MemberKeys member) async {
    final workspace = Stores.memberKeys.workspace;
    if (workspace == null) return;
    if (member.state != MemberKeyState.verified) {
      final grantAnyway = await showAppDialog(
        context: context,
        title: 'Fingerprints not compared',
        icon: AppIcons.exclamationTriangle,
        message:
            'Without comparing, the keys shown for ${member.email} are the '
            'server’s word. If the server made them up, it could read every '
            'encrypted record in this workspace. Comparing takes a minute.',
        confirmLabel: 'Give access without comparing',
        confirmIcon: AppIcons.key,
        cancelLabel: 'Compare first',
        destructive: true,
      );
      if (!context.mounted) return;
      if (!grantAnyway) {
        await _verify(context, member);
        if (!context.mounted ||
            Stores.memberKeys.byUser(member.user)?.state !=
                MemberKeyState.verified) {
          return;
        }
      }
    } else {
      final ok = await showAppDialog(
        context: context,
        title: 'Give ${member.email} access?',
        message:
            'Their devices get the key this workspace’s encrypted records are '
            'written under. Removing them later stops them reading new '
            'values, not what they already read.',
        confirmLabel: 'Give access',
        confirmIcon: AppIcons.key,
      );
      if (!ok || !context.mounted) return;
    }
    final current = Stores.memberKeys.byUser(member.user) ?? member;
    final done = await Stores.keys.grantAccess(workspace, current);
    if (!context.mounted) return;
    if (done) {
      AppToast.success(context, '${member.email} has access');
      await Stores.memberKeys.load(workspace);
    } else {
      AppToast.error(
        context,
        'Access could not be given',
        subtitle: Stores.keys.errorMessage,
      );
    }
  }

  Future<void> _acceptChange(BuildContext context, MemberKeys member) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Accept ${member.email}’s new keys?',
      message:
          'Their device list now starts somewhere else, or lost entries this '
          'device saw. That happens when they start over with encryption. It '
          'also happens when the server shows a list of its own. Asking them, '
          'and comparing the new fingerprint, tells the two apart.'
          '${member.previousFingerprint == null ? '' : '\n\nBefore: ${member.previousFingerprint}'}'
          '${member.fingerprint == null ? '' : '\nNow: ${member.fingerprint}'}',
      confirmLabel: 'Accept new keys',
      confirmIcon: AppIcons.key,
      destructive: true,
    );
    if (ok) await Stores.memberKeys.acceptChange(member.user);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final store = Stores.memberKeys;
        final own = Stores.keys.ownFingerprint;
        final others = [
          for (final m in store.members)
            if (!m.isSelf) m,
        ];
        MemberKeys? self;
        for (final m in store.members) {
          if (m.isSelf) self = m;
        }
        final workspace = store.workspace;
        final canGrantHere =
            self != null &&
            self.canGrant &&
            workspace != null &&
            Stores.keys.canSeal(workspace);
        final pending = workspace == null
            ? const <String>{}
            : Stores.keys.pendingGrants[workspace] ?? const <String>{};
        String nameOf(String user) =>
            store.byUser(user)?.email ?? 'Another member';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (self?.state == MemberKeyState.changed) ...[
              AppAlert(
                destructive: true,
                title: const Text('Others are shown a different list for you'),
                content: const Text(
                  'The server shows other members a device list for this '
                  'account that does not start where yours does. Nothing is '
                  'handed to it; tell an administrator.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (pending.isNotEmpty) ...[
              AppAlert(
                title: const Text('Access waits for a fingerprint'),
                content: Text(
                  '${pending.map(nameOf).join(', ')} gave your devices this '
                  'workspace’s key. It is used once you compare fingerprints '
                  'with them below.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (store.changed.isNotEmpty) ...[
              AppAlert(
                destructive: true,
                title: const Text('A member’s keys changed'),
                content: Text(
                  '${store.changed.map((m) => m.email).join(', ')}: nothing '
                  'is shared with them until their new keys are accepted.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (own != null) ...[
              AppText('Your fingerprint').small.bold,
              const SizedBox(height: AppSpacing.xs),
              AppText(own).mono.selectable,
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Other members compare it with what their app shows for you. '
                'It stays the same as devices come and go.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (store.errorMessage != null)
              AppErrorText(store.errorMessage!)
            else if (store.isLoading && store.members.isEmpty)
              const AppListSkeleton(embedded: true)
            else if (others.isNotEmpty)
              AppListGroup(
                title: 'Members',
                children: [
                  for (final member in others)
                    AppListRow(
                      icon: AppIcons.person,
                      title: member.email.isEmpty
                          ? 'Unknown account'
                          : member.email,
                      subtitle: member.fingerprint ?? 'No keys yet',
                      showChevron: false,
                      trailing: Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppBadge(
                            label: _stateLabel(member.state),
                            variant: _stateVariant(member.state),
                          ),
                          if (member.holdsKey)
                            const AppBadge(
                              label: 'Has access',
                              variant: AppBadgeVariant.secondary,
                            )
                          else if (member.waiting &&
                              member.state != MemberKeyState.notSetUp)
                            const AppBadge(
                              label: 'Waiting for access',
                              variant: AppBadgeVariant.outline,
                            ),
                          if (canGrantHere && member.waiting && member.usable)
                            AppButton(
                              icon: AppIcons.key,
                              label: 'Give access',
                              style: AppButtonStyle.accent,
                              size: AppButtonSize.small,
                              onTap: () => _grant(context, member),
                            ),
                          if (member.state == MemberKeyState.trusted)
                            AppButton(
                              icon: AppIcons.shieldCheck,
                              tooltip: 'Compare fingerprints',
                              style: AppButtonStyle.ghost,
                              size: AppButtonSize.small,
                              onTap: () => _verify(context, member),
                            ),
                          if (member.state == MemberKeyState.changed &&
                              member.fingerprint != null &&
                              !member.chain.broken)
                            AppButton(
                              icon: AppIcons.key,
                              tooltip: 'Accept new keys',
                              style: AppButtonStyle.ghost,
                              size: AppButtonSize.small,
                              onTap: () => _acceptChange(context, member),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// A warning that can't wait for someone to open Settings: their list changed in
/// a way this device didn't do, or it no longer trusts it.
class SealingAlarm extends StatelessWidget {
  const SealingAlarm({super.key});

  /// Whether there is anything to warn about, so a list can leave out the
  /// alarm, and the gap it would stand in, when there is not.
  static bool get shows => _message(Stores.keys) != null;

  static bool _locked(KeysStore keys) =>
      keys.status == SealingStatus.needsThisDevice ||
      keys.status == SealingStatus.needsConfirmation;

  static String? _message(KeysStore keys) {
    final locked = _locked(keys);
    return switch (keys) {
      _ when keys.status == SealingStatus.untrusted =>
        'The device list changed in a way this device cannot confirm.',
      _ when keys.removedFromList =>
        'This device was removed from the device list.',
      _ when locked => 'Encrypted records cannot be read on this device yet.',
      _ when keys.unreviewedEntries.isNotEmpty => 'The device list changed.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final keys = Stores.keys;
        final locked = _locked(keys);
        final message = _message(keys);
        if (message == null) return const SizedBox.shrink();
        final alarm = !locked || keys.removedFromList;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppAlert(
            destructive: alarm,
            title: Text(message),
            content: Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                icon: alarm ? AppIcons.lock : AppIcons.personPlus,
                label: alarm ? 'Check it' : 'Add this device',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: () => context.go(
                  AppRoutes.settingsPage(SettingsPage.encryption.slug),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
