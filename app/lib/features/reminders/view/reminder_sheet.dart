import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/reminder.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Opens the drawer that adds a reminder to [record].
Future<void> openReminderSheet(BuildContext context, models.Record record) {
  return showAppSheet(
    context: context,
    builder: (_) => _ReminderSheet(record: record),
  );
}

/// When a date reminder fires, offered as one tap each.
enum ReminderPreset { week, month, year, custom }

/// The day [preset] lands on, counted from [from], at nine in the morning:
/// a reminder is for a day, and nine is when a day's reminders are useful.
/// A month or a year on keeps the day of the month where it can, and takes
/// the month's last day where it cannot (31 January → 28 February).
DateTime reminderPresetDate(ReminderPreset preset, DateTime from) {
  DateTime at(int y, int m, int d) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d > last ? last : d, 9);
  }

  switch (preset) {
    case ReminderPreset.week:
      final d = from.add(const Duration(days: 7));
      return DateTime(d.year, d.month, d.day, 9);
    case ReminderPreset.month:
      return at(from.year, from.month + 1, from.day);
    case ReminderPreset.year:
      return at(from.year + 1, from.month, from.day);
    case ReminderPreset.custom:
      return DateTime(from.year, from.month, from.day, 9);
  }
}

/// "2026-10-09", the way dates read everywhere else in the app.
String formatReminderDay(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

/// One line saying what a reminder waits for. [nameOf] names an entry by id.
String describeReminder(
  Reminder r,
  String recordId,
  String Function(String id) nameOf,
) {
  if (r.isDate) {
    final due = r.dueAt;
    return due == null ? 'On a date' : 'On ${formatReminderDay(due)}';
  }
  final watch = r.watch;
  if (watch == null || watch == recordId) return 'When this entry changes';
  return 'When “${nameOf(watch)}” changes';
}

class _ReminderSheet extends StatefulWidget {
  final models.Record record;

  const _ReminderSheet({required this.record});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  final Local<String> _kind = Local(Reminder.kindDate);
  final Local<ReminderPreset> _preset = Local(ReminderPreset.month);
  final Local<DateTime?> _picked = Local(null);

  /// The entry a change reminder watches; empty is the entry itself.
  final Local<String> _watch = Local('');
  final ObservableTextController _note = ObservableTextController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _name(models.Record r) => r.label.isEmpty ? r.key : r.label;

  DateTime? get _dueAt => _preset.value == ReminderPreset.custom
      ? _picked.value
      : reminderPresetDate(_preset.value, DateTime.now());

  bool get _canSave =>
      !Stores.reminders.isSaving &&
      (_kind.value == Reminder.kindChange || _dueAt != null);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _picked.value ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 30)),
    );
    if (picked == null) return;
    _picked.value = reminderPresetDate(ReminderPreset.custom, picked);
    _preset.value = ReminderPreset.custom;
  }

  Future<void> _save() async {
    final store = Stores.reminders;
    final isDate = _kind.value == Reminder.kindDate;
    final ok = await store.create(
      user: Stores.auth.userId,
      record: widget.record.id,
      kind: _kind.value,
      dueAt: isDate ? _dueAt : null,
      watch: isDate ? null : _watch.value,
      note: _note.text,
    );
    if (!mounted) return;
    if (!ok) {
      AppToast.error(
        context,
        store.error?.title ?? 'Could not add the reminder',
        subtitle: store.error?.description,
      );
      return;
    }
    Navigator.of(context).pop();
    AppToast.success(context, 'Reminder added');
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New reminder').header,
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'For ${_name(widget.record)}. It arrives in your '
                    'notifications, and only you see it.',
                  ).muted.small,
                ],
              ),
            ),
            const AppDivider(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppFormSectionHeader('Remind me'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppSegmented<String>(
                        value: _kind.value,
                        items: const [
                          AppSegmentedItem(
                            value: Reminder.kindDate,
                            icon: AppIcons.calendar,
                            label: 'On a date',
                          ),
                          AppSegmentedItem(
                            value: Reminder.kindChange,
                            icon: AppIcons.arrowRepeat,
                            label: 'On a change',
                          ),
                        ],
                        onChanged: (v) => _kind.value = v,
                      ),
                    ),
                    if (_kind.value == Reminder.kindDate)
                      ..._dateFields()
                    else
                      ..._changeFields(),
                    const AppFormSectionHeader('Note'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppTextField(
                        controller: _note,
                        hint: 'e.g. Renew it at the town hall',
                        maxLines: 3,
                        minLines: 1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      style: AppButtonStyle.accent,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      icon: AppIcons.bell,
                      label: 'Add reminder',
                      busy: Stores.reminders.isSaving,
                      onTap: _canSave ? _save : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _dateFields() {
    final due = _dueAt;
    return [
      const AppFormSectionHeader('When'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: AppSegmented<ReminderPreset>(
          value: _preset.value,
          items: const [
            AppSegmentedItem(value: ReminderPreset.week, label: '1 week'),
            AppSegmentedItem(value: ReminderPreset.month, label: '1 month'),
            AppSegmentedItem(value: ReminderPreset.year, label: '1 year'),
            AppSegmentedItem(value: ReminderPreset.custom, label: 'Date'),
          ],
          onChanged: (v) {
            _preset.value = v;
            if (v == ReminderPreset.custom && _picked.value == null) {
              _pickDate();
            }
          },
        ),
      ),
      AppSpacing.gapSm,
      AppFormRow(
        icon: AppIcons.calendar,
        label: 'Reminds you on',
        valueText: due == null ? 'Pick a date' : formatReminderDay(due),
        isPlaceholder: due == null,
        onTap: _pickDate,
      ),
    ];
  }

  List<Widget> _changeFields() {
    final others =
        Stores.vault.records.where((r) => r.id != widget.record.id).toList()
          ..sort(
            (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
          );
    return [
      const AppFormSectionHeader('When this changes'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: AppSelect<String>(
          value: _watch.value,
          items: [
            const AppSelectItem<String>('', Text('This entry')),
            for (final r in others)
              AppSelectItem<String>(
                r.id,
                Text(_name(r), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => _watch.value = v ?? '',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          0,
        ),
        child: const Text(
          'The first time its value changes — whoever changes it — you get '
          'one notification. The value itself is never in it.',
        ).muted.small,
      ),
    ];
  }
}
