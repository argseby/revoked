import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Shown at the top of a page that belongs to a feature the person has off.
///
/// A link or an old bookmark can land anywhere, so the page still opens; this
/// says why it is not in the navigation and offers to turn the feature on in
/// one tap. Where the workspace does not allow the feature, it says that
/// instead. Nothing while the feature is visible.
class FeatureNotice extends StatelessWidget {
  final Feature feature;

  /// Space under the notice when it shows, for pages that stack it above
  /// their own content.
  final bool padded;

  const FeatureNotice(this.feature, {super.key, this.padded = true});

  Future<void> _turnOn(BuildContext context) async {
    final store = Stores.features;
    final ok = await store.turnOn(feature);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, '${store.labelFor(feature)} turned on');
    } else {
      AppToast.error(
        context,
        store.error?.description ?? 'The feature could not be turned on.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.features;
        if (store.visible(feature)) return const SizedBox.shrink();
        final label = store.labelFor(feature);
        final alert = store.isPermitted(feature)
            ? AppAlert(
                leading: const Icon(AppIcons.info),
                title: Text('$label is off'),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This feature is turned off and hidden from navigation.',
                    ).small,
                    AppSpacing.gapSm,
                    AppButton(
                      icon: AppIcons.check,
                      label: 'Turn on $label',
                      size: AppButtonSize.small,
                      busy: store.isSaving,
                      onTap: store.isSaving ? null : () => _turnOn(context),
                    ),
                  ],
                ),
              )
            : AppAlert(
                leading: const Icon(AppIcons.shieldLock),
                title: Text('$label not available in this workspace'),
                content: const Text(
                  'It must be allowed by a workspace admin. This page is read-only.',
                ).small,
              );
        if (!padded) return alert;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenH(context),
            AppSpacing.md,
            AppSpacing.screenH(context),
            0,
          ),
          child: alert,
        );
      },
    );
  }
}

/// The feature a location belongs to, or null for the places every account
/// has: the vault and Settings.
Feature? featureForLocation(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  bool under(String root) => path == root || path.startsWith('$root/');
  if (under(AppRoutes.overview) || under(AppRoutes.shared)) {
    return Feature.sharing;
  }
  if (under(AppRoutes.requests) || under(AppRoutes.templates)) {
    return Feature.requests;
  }
  if (under(AppRoutes.attestations) ||
      under(AppRoutes.settingsPage('identities'))) {
    return Feature.attestations;
  }
  if (under(AppRoutes.contacts)) return Feature.contacts;
  if (under(AppRoutes.connectedTools) || under('/settings/signed-in')) {
    return Feature.tools;
  }
  if (under(AppRoutes.apiKeys)) return Feature.developer;
  return null;
}
