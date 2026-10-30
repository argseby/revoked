import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/detail_gate.dart';
import 'package:revoked_app/core/widgets/ledger_header.dart';

/// Theme, how much each screen says, text size and motion — the settings
/// that decide whether the app is comfortable to read and use at all.
///
/// Each choice shows its effect right below it, so nobody has to leave the
/// page to find out what a switch did.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LedgerHeader('Theme'),
          AppSegmented<ThemeMode>(
            value: Stores.theme.mode,
            onChanged: Stores.theme.setMode,
            items: const [
              AppSegmentedItem(
                value: ThemeMode.system,
                label: 'System',
                icon: AppIcons.brightnessAuto,
              ),
              AppSegmentedItem(
                value: ThemeMode.light,
                label: 'Light',
                icon: AppIcons.brightnessLight,
              ),
              AppSegmentedItem(
                value: ThemeMode.dark,
                label: 'Dark',
                icon: AppIcons.brightnessDark,
              ),
            ],
          ),
          AppSpacing.gapXs,
          const Text(
            'System matches your device and changes with it.',
          ).small.muted,

          const LedgerHeader('Detail'),
          AppSegmented<DetailLevel>(
            value: DisplayPreferences.detailLevel,
            onChanged: DisplayPreferences.setDetailLevel,
            items: const [
              AppSegmentedItem(
                value: DetailLevel.essentials,
                label: 'Essentials',
              ),
              AppSegmentedItem(value: DetailLevel.full, label: 'Full detail'),
            ],
          ),
          AppSpacing.gapXs,
          const Text(
            'Essentials tells you who can see what, in one sentence. Full '
            'detail adds link addresses, fingerprints, check results and view '
            'counts. Essentials never hides anything you need to act on.',
          ).small.muted,
          AppSpacing.gapMd,
          const _DetailPreview(),

          const LedgerHeader('Text size'),
          _TextSize(scale: DisplayPreferences.textScale),

          const LedgerHeader('Motion'),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reduce motion'),
                    const Text(
                      'Turns off fades and slides. Always on if your device '
                      'asks for less motion.',
                    ).small.muted,
                  ],
                ),
              ),
              AppSpacing.gapMd,
              Semantics(
                label: 'Reduce motion',
                child: AppSwitch(
                  value: DisplayPreferences.reduceMotion,
                  onChanged: DisplayPreferences.setReduceMotion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One link, described at the chosen level of detail.
class _DetailPreview extends StatelessWidget {
  const _DetailPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Preview',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadius.allMd,
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surfaceContainerLowest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(child: AppText('Property manager', bold: true)),
                StatusLabel('active'),
              ],
            ),
            AppSpacing.gapXs,
            const Text(
              'They can see your tenant details and IBAN, always the current '
              'values. You can stop this at any time.',
            ),
            DetailGate(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('example.org/s/k7m2p9').small.mono,
                    const Text(
                      'Password, ends 31 Dec · read 12 times, last 2 h ago',
                    ).small.muted,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The in-app text size, on top of the device's, with a sample that grows
/// as the slider moves.
class _TextSize extends StatelessWidget {
  final double scale;

  const _TextSize({required this.scale});

  @override
  Widget build(BuildContext context) {
    const scales = DisplayPreferences.textScales;
    final index = scales.indexOf(scale).clamp(0, scales.length - 1);
    final percent = '${(scale * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Text size in this app')),
            AppText(percent, bold: true),
          ],
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: (scales.length - 1).toDouble(),
          divisions: scales.length - 1,
          label: percent,
          semanticFormatterCallback: (_) => percent,
          onChanged: (v) => DisplayPreferences.setTextScale(scales[v.round()]),
        ),
        const Text(
          'Adds to your device\'s text size. At 100%, the app matches your '
          'device.',
        ).small.muted,
      ],
    );
  }
}
