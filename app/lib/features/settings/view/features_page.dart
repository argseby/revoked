import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Which parts of the app this account sees. The same list onboarding asks
/// with, so what was ticked there can be changed here; Developer sits last,
/// because it is for the few who script against the API.
///
/// A feature the workspace does not allow stays in the list, unticked and
/// marked, so "it's gone" has a reason beside it rather than a mystery.
class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.features;
        final failed = store.loadState.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Visible features',
              trailing: const SizedBox.shrink(),
              footer: const Text(
                'Turned-off features leave the navigation. Links to them still '
                'open and offer to turn them back on. This affects visibility '
                'only, never permissions.',
              ),
              children: [
                if (failed != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: AppErrorText(failed),
                  ),
                const FeatureRows(),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The catalogue as tick rows: the vault first, always on, then every
/// feature with Developer last. [draft] and [onChanged] make it a form that
/// saves later (onboarding); without them each tick saves at once.
class FeatureRows extends StatelessWidget {
  final Set<String>? draft;
  final void Function(Feature feature, bool on)? onChanged;

  const FeatureRows({super.key, this.draft, this.onChanged});

  bool _ticked(Feature feature) =>
      draft?.contains(feature.key) ?? Stores.features.isOn(feature);

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.features;
        final rows = <Widget>[
          const AppCheckRow(
            label: 'Vault',
            subtitle: 'Records, files and sections. Always on.',
            value: true,
            onChanged: null,
          ),
        ];
        for (final feature in store.ordered) {
          final info = store.infoFor(feature);
          final permitted = store.isPermitted(feature);
          rows.add(
            AppCheckRow(
              label: store.labelFor(feature),
              subtitle: info?.description,
              badge: permitted
                  ? null
                  : const AppBadge(
                      icon: AppIcons.shieldLock,
                      label: 'Not allowed here',
                      variant: AppBadgeVariant.outline,
                    ),
              value: _ticked(feature) && permitted,
              onChanged: !permitted || store.isSaving
                  ? null
                  : (on) => onChanged != null
                        ? onChanged!(feature, on)
                        : _save(context, feature, on),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows,
              if (store.catalogue.isEmpty && store.loadState.isFirstLoad)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: const Text('Loading…').muted.small,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Saves one tick at once, and says so only when that failed.
Future<void> _save(BuildContext context, Feature feature, bool on) async {
  final store = Stores.features;
  final ok = on ? await store.turnOn(feature) : await store.turnOff(feature);
  if (!ok && context.mounted) {
    AppToast.error(
      context,
      store.error?.description ?? 'The change could not be saved.',
    );
  }
}
