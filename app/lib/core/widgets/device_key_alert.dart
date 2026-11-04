import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';

/// Shown when the account has identities but none of their keys is on this
/// device, as after signing in on a new computer: says where the keys are
/// and makes one here, instead of letting the next signature fail.
class DeviceKeyAlert extends StatelessWidget {
  /// Around the alert while it shows. Nothing is laid out while it is hidden,
  /// so a page that needs space above the alert passes it here rather than
  /// wrapping it, which would leave that space empty.
  final EdgeInsetsGeometry padding;

  const DeviceKeyAlert({
    super.key,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  Future<void> _create(BuildContext context) async {
    final store = Stores.identities;
    final ok = await store.createIdentity(name: thisDeviceName);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Identity created for this device');
    } else {
      AppToast.error(
        context,
        'The identity could not be created',
        subtitle: store.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.identities;
        if (!store.keysElsewhere) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: AppAlert(
            leading: const Icon(AppIcons.keyOff),
            title: const Text('No identity on this device'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'With end-to-end encryption on, identities reach every '
                  'device on the account\'s device list. Without it, keys '
                  'stay on the device that made them, and signing here needs '
                  'an identity created here.',
                ).small,
                AppSpacing.gapSm,
                AppButton(
                  icon: AppIcons.plus,
                  label: 'Create for this device',
                  size: AppButtonSize.small,
                  busy: store.isLoading,
                  onTap: store.isLoading ? null : () => _create(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The badge an identity whose key is not on this device carries, in every
/// list that shows identities.
const keyElsewhereLabel = 'Key on another device';
