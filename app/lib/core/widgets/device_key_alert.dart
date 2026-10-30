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
  const DeviceKeyAlert({super.key});

  Future<void> _create(BuildContext context) async {
    final store = Stores.identities;
    final ok = await store.createIdentity(name: thisDeviceName);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'This device can sign now');
    } else {
      AppToast.error(
        context,
        'Could not create the identity',
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
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppAlert(
            leading: const Icon(AppIcons.keyOff),
            title: const Text('No identity on this device yet'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your identities\' keys stay on the devices that made '
                  'them, so they cannot sign here. Create one for this '
                  'device to sign, accept attestations and show them.',
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
