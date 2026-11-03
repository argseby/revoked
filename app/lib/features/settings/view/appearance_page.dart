import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/date_time_preferences.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/ledger_header.dart';

/// Theme, text size, motion and how dates read — the settings that decide whether the app
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
          const Text('System follows the device setting.').small.muted,

          const LedgerHeader('Dates and times'),
          const _DatesAndTimes(),

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
                      'Disables fades and slides. Always on when the device '
                      'requests reduced motion.',
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
            const Expanded(child: Text('App text size')),
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
          'Scales the device text size. At 100%, the app matches the '
          'device.',
        ).small.muted,
      ],
    );
  }
}

/// Date format, clock and time zone. Each starts on Automatic, which follows
/// the device's region and time zone.
class _DatesAndTimes extends StatelessWidget {
  const _DatesAndTimes();

  /// The automatic zone in the time zone list: a name no real zone has.
  static const _deviceZone = '';

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final now = DateTime.now();
    final sample = DateTime(now.year, 12, 31);
    String example(DateStyle style) => writeDay(sample, style);
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final deviceZone = 'This device (UTC$sign$hours:$minutes)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: 'Date format',
          inset: false,
          child: AppSelect<DateStyle>(
            value: DateTimePreferences.dateStyle,
            onChanged: (v) {
              if (v != null) DateTimePreferences.setDateStyle(v);
            },
            items: [
              AppSelectItem(
                DateStyle.automatic,
                Text(
                  'Automatic · ${example(DateTimePreferences.automaticDateStyle)}',
                ),
              ),
              for (final style in DateStyle.values.skip(1))
                AppSelectItem(style, Text(example(style))),
            ],
          ),
        ),
        AppSpacing.gapMd,
        const Text('Clock'),
        AppSpacing.gapXs,
        AppSegmented<ClockStyle>(
          value: DateTimePreferences.clockStyle,
          onChanged: DateTimePreferences.setClockStyle,
          items: const [
            AppSegmentedItem(value: ClockStyle.automatic, label: 'Automatic'),
            AppSegmentedItem(value: ClockStyle.hours24, label: '24-hour'),
            AppSegmentedItem(value: ClockStyle.hours12, label: '12-hour'),
          ],
        ),
        AppSpacing.gapMd,
        AppFormField(
          label: 'Time zone',
          inset: false,
          child: AppSelect<String>(
            value: DateTimePreferences.timeZone?.name ?? _deviceZone,
            onChanged: (v) =>
                DateTimePreferences.setTimeZone(v == _deviceZone ? null : v),
            items: [
              AppSelectItem(_deviceZone, Text(deviceZone)),
              for (final name in DateTimePreferences.timeZoneNames)
                AppSelectItem(name, Text(name.replaceAll('_', ' '))),
            ],
          ),
        ),
        AppSpacing.gapXs,
        Text('Current time: ${formatDayTime(now)}.').small.muted,
        const Text(
          'Automatic follows the device region and time zone.',
        ).small.muted,
      ],
    );
  }
}
