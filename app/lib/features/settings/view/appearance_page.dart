import 'package:material_ui/material_ui.dart';
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
import 'package:revoked_app/core/widgets/app_composer.dart';

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
          _AppearanceSection(
            title: 'Theme',
            description: 'System follows the device setting.',
            child: _ResponsiveChoice<ThemeMode>(
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
          ),
          const _AppearanceSection(
            title: 'Dates and times',
            description: 'Automatic follows the device region and time zone.',
            child: _DatesAndTimes(),
          ),
          _AppearanceSection(
            title: 'Text size',
            description:
                'Scales the device text size. At 100%, the app matches the '
                'device.',
            child: _TextSize(scale: DisplayPreferences.textScale),
          ),
          _AppearanceSection(
            title: 'Motion',
            child: AppFormToggleRow(
              label: 'Reduce motion',
              subtitle: 'Disables fades and slides. Always on when the device requests reduced motion.',
              value: DisplayPreferences.reduceMotion,
              onChanged: DisplayPreferences.setReduceMotion,
              inset: false,
            ),
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
            const Expanded(child: AppComposerSubLabel('App text size')),
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
        const AppComposerSubLabel('Date format'),
        AppSelect<DateStyle>(
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
        AppSpacing.gapLg,
        const AppComposerSubLabel('Clock'),
        _ResponsiveChoice<ClockStyle>(
          value: DateTimePreferences.clockStyle,
          onChanged: DateTimePreferences.setClockStyle,
          items: const [
            AppSegmentedItem(value: ClockStyle.automatic, label: 'Automatic'),
            AppSegmentedItem(value: ClockStyle.hours24, label: '24-hour'),
            AppSegmentedItem(value: ClockStyle.hours12, label: '12-hour'),
          ],
        ),
        AppSpacing.gapLg,
        const AppComposerSubLabel('Time zone'),
        AppSelect<String>(
          value: DateTimePreferences.timeZone?.name ?? _deviceZone,
          onChanged: (v) =>
              DateTimePreferences.setTimeZone(v == _deviceZone ? null : v),
          items: [
            AppSelectItem(_deviceZone, Text(deviceZone)),
            for (final name in DateTimePreferences.timeZoneNames)
              AppSelectItem(name, Text(name.replaceAll('_', ' '))),
          ],
        ),
        AppSpacing.gapXs,
        Text('Current time: ${formatDayTime(now)}.').small.muted,
      ],
    );
  }
}

/// One group of settings as a composer card: the same title, description
/// and controls as in every create sheet.
class _AppearanceSection extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const _AppearanceSection({
    required this.title,
    required this.child,
    this.description,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: AppComposerCard(
      title: title,
      description: description,
      inset: false,
      child: child,
    ),
  );
}

/// Keep all choices readable on a small phone or with enlarged text.
class _ResponsiveChoice<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<AppSegmentedItem<T>> items;

  const _ResponsiveChoice({
    required this.value,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      if (box.maxWidth < 360 * scale) {
        return AppSelect<T>(
          value: value,
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          items: [
            for (final item in items)
              AppSelectItem(item.value, Text(item.label!)),
          ],
        );
      }
      return AppSegmented<T>(
        value: value,
        onChanged: onChanged,
        items: items,
        expand: true,
      );
    },
  );
}
