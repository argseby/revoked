import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/ledger_header.dart';

/// Theme, text size and motion — the settings that decide whether the app
/// is comfortable to read and use at all.
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
