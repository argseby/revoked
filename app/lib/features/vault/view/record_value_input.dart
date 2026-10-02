import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/utils/value_kind.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// The eye behind a record's value: whether the vault masks it. It sits on
/// the value itself, so the choice is made where the value is.
class RecordHiddenToggle extends StatelessWidget {
  final bool hidden;
  final ValueChanged<bool> onChanged;

  /// A file record masks its name, not a value.
  final bool isFile;

  const RecordHiddenToggle({
    super.key,
    required this.hidden,
    required this.onChanged,
    this.isFile = false,
  });

  @override
  Widget build(BuildContext context) {
    final what = isFile ? 'name' : 'value';
    return AppButton(
      icon: hidden ? AppIcons.eyeSlash : AppIcons.eye,
      tooltip: hidden
          ? 'Hidden in the vault — show the $what'
          : 'Shown in the vault — hide the $what',
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      onTap: () => onChanged(!hidden),
    );
  }
}

/// What a record of [type] holds once the type is picked: a yes/no record
/// holds `true` or `false` and nothing else, so anything else becomes
/// `false` and the toggle starts in a state it can show.
String recordValueForType(String type, String value) {
  if (type != 'boolean') return value;
  return value.trim().toLowerCase() == 'true' ? 'true' : 'false';
}

/// A date or date-and-time value the way a person reads it: "12 April 1991",
/// "12 April 1991, 14:30". Anything that does not parse is shown as stored.
String recordDateTimeLabel(String value) {
  final v = value.trim();
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}))?').firstMatch(v);
  if (m == null) return v;
  final day = displayValue(ValueKind.date, m.group(1)!);
  return m.group(2) == null ? day : '$day, ${m.group(2)}';
}

/// Picks a date, then optionally a time, and returns it as the ISO 8601 the
/// vault stores — `1991-04-12`, or `1991-04-12T14:30` when a time was picked.
/// The time step can be dismissed: a date of birth has no time. Null when the
/// date itself was dismissed.
Future<String?> pickRecordDateTime(
  BuildContext context, {
  required String title,
  String current = '',
}) async {
  final now = DateTime.now();
  final initial = DateTime.tryParse(current.trim()) ?? now;

  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(now.year + 50),
    helpText: title,
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: '$title — time (optional)',
  );

  final day =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  if (time == null) return day;
  return '${day}T${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// A record's value as an input that fits its type — typed for text, numbers
/// and web addresses, a switch for yes/no, a calendar for dates — with the
/// [RecordHiddenToggle] right behind it.
class RecordValueField extends StatelessWidget {
  final String type;
  final TextEditingController controller;
  final bool hidden;
  final ValueChanged<bool> onHiddenChanged;

  /// Runs after every change, typed or picked, so the caller can validate.
  final ValueChanged<String> onChanged;

  const RecordValueField({
    super.key,
    required this.type,
    required this.controller,
    required this.hidden,
    required this.onHiddenChanged,
    required this.onChanged,
  });

  void _set(String value) {
    controller.text = value;
    onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    // The store's controllers are observable: reading the value here, rather
    // than trusting the parent to, repaints the switch and the date on change.
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final eye = Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: RecordHiddenToggle(hidden: hidden, onChanged: onHiddenChanged),
    );

    switch (type) {
      case 'boolean':
        final on = controller.text.trim().toLowerCase() == 'true';
        return _PickerField(
          onTap: () => _set(on ? 'false' : 'true'),
          trailing: [
            AppSwitch(value: on, onChanged: (v) => _set(v ? 'true' : 'false')),
            eye,
          ],
          child: Text(on ? 'True' : 'False'),
        );
      case 'datetime':
        final value = controller.text.trim();
        return _PickerField(
          onTap: () async {
            final picked = await pickRecordDateTime(
              context,
              title: 'Value',
              current: value,
            );
            if (picked != null) _set(picked);
          },
          leading: const Icon(AppIcons.calendar),
          trailing: [eye],
          child: value.isEmpty
              ? Text(
                  'Pick a date',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Text(recordDateTimeLabel(value)),
        );
      default:
        return AppTextField(
          controller: controller,
          hint: switch (type) {
            'number' => '42',
            'url' => 'https://example.com',
            _ => 'sk-1234...',
          },
          keyboardType: switch (type) {
            'number' => const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            'url' => TextInputType.url,
            _ => null,
          },
          onChanged: onChanged,
          trailing: eye,
        );
    }
  }
}

/// A field that is tapped rather than typed in, drawn with the same frame as
/// a text field so the form's inputs line up.
class _PickerField extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final Widget? leading;
  final List<Widget> trailing;

  const _PickerField({
    required this.child,
    required this.onTap,
    this.leading,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allMd,
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: leading,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: trailing),
        ),
        child: child,
      ),
    );
  }
}
