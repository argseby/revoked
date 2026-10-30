import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/utils/value_kind.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// Whether the vault masks a record's value (or a file record's name) on
/// screen. A labelled switch of its own, below the value, rather than an eye
/// on the value: an eye there reads as "show what I typed", while this is a
/// setting stored with the record.
class RecordHiddenToggle extends StatelessWidget {
  final bool hidden;
  final ValueChanged<bool> onChanged;

  /// A file record masks its name, not a value.
  final bool isFile;

  /// Aligns the row with a create drawer's other rows; off inside a form
  /// that already pads its fields.
  final bool inset;

  const RecordHiddenToggle({
    super.key,
    required this.hidden,
    required this.onChanged,
    this.isFile = false,
    this.inset = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppFormToggleRow(
      icon: inset ? AppIcons.eyeSlash : null,
      label: isFile ? 'Hide file name' : 'Hide value',
      subtitle: isFile
          ? 'Keep the name hidden until you reveal it. A file name can give '
                'away what is inside.'
          : 'Keep it hidden until you reveal it. Good for passwords and '
                'anything nobody should read over your shoulder.',
      value: hidden,
      onChanged: onChanged,
      inset: inset,
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
/// and web addresses, a switch for yes/no, a calendar for dates. Whether it is
/// masked is the [RecordHiddenToggle] the form places below it.
class RecordValueField extends StatelessWidget {
  final String type;
  final TextEditingController controller;

  /// Runs after every change, typed or picked, so the caller can validate.
  final ValueChanged<String> onChanged;

  const RecordValueField({
    super.key,
    required this.type,
    required this.controller,
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
    switch (type) {
      case 'boolean':
        final on = controller.text.trim().toLowerCase() == 'true';
        return _PickerField(
          onTap: () => _set(on ? 'false' : 'true'),
          trailing: [
            AppSwitch(value: on, onChanged: (v) => _set(v ? 'true' : 'false')),
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
