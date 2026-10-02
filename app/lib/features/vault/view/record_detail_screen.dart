import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/reminder.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/file_view_sheet.dart';
import 'package:revoked_app/features/reminders/view/reminder_sheet.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/record_edit_sheet.dart';

/// One vault record, opened from the Vault list: its value, which links hand
/// it out, where it is filed, and the actions on it.
class RecordDetailScreen extends StatefulWidget {
  final String recordId;

  const RecordDetailScreen({super.key, required this.recordId});

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  /// Set while the record is being deleted, so the button spins.
  final Local<bool> _deleting = Local(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // Opened straight from a link, the list has not loaded anything yet.
      if (Stores.vault.records.isEmpty) Stores.vault.loadRecords();
      if (Stores.shares.shares.isEmpty) Stores.shares.loadShares();
      // Always: one may have fired, or been added on another device.
      Stores.reminders.load();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  models.Record? _find(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final r in Stores.vault.records) {
      if (r.id == id) return r;
    }
    return null;
  }

  models.Record? get _record => _find(widget.recordId);

  void _back() => context.go(AppRoutes.vault);

  String _name(models.Record r) => r.label.isEmpty ? r.key : r.label;

  Widget _title(BuildContext context) {
    final r = _record;
    return AppBarTitle(title: r == null ? 'Record' : _name(r), onBack: _back);
  }

  /// An alias carries no value of its own; it forwards its parent's.
  String _value(models.Record r) =>
      r.isAlias ? (_find(r.aliasOf)?.value ?? '') : r.value;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final record = _record;
        if (record == null) {
          if (Stores.vault.isLoading) {
            return const Center(child: AppSpinner(large: true));
          }
          return AppEmptyState(
            icon: AppIcons.safe,
            title: 'Record not found',
            subtitle: 'It may have been deleted.',
            action: AppButton(
              icon: AppIcons.arrowLeft,
              label: 'Back to vault',
              style: AppButtonStyle.accent,
              onTap: _back,
            ),
          );
        }

        return AppDetailPage(
          header: _header(context, record),
          sections: [
            _valueSection(record),
            _sharedIn(context, record),
            _reminders(context, record),
            _details(record),
            AppDetailManage(
              actions: [
                AppButton(
                  icon: AppIcons.trash,
                  label: 'Delete',
                  style: AppButtonStyle.destructive,
                  size: AppButtonSize.small,
                  busy: _deleting.value,
                  onTap: _deleting.value
                      ? null
                      : () => _confirmDelete(context, record),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  AppDetailHeader _header(BuildContext context, models.Record r) {
    final store = Stores.vault;
    return AppDetailHeader(
      badges: [
        AppBadge(icon: RecordTypeUtils.icon(r.type), label: r.type),
        if (r.isHidden)
          const AppBadge(icon: AppIcons.eyeSlash, label: 'Hidden'),
        if (r.isAlias) const AppBadge(icon: AppIcons.link, label: 'Alias'),
        if (r.isRequested)
          AppBadge(
            icon: AppIcons.inboxFill,
            label: 'Requested by ${r.requestedBy}',
          ),
      ],
      title: _name(r),
      subtitle: r.key,
      subtitleMono: true,
      primaryAction: r.isFile
          ? AppButton(
              icon: AppIcons.eye,
              label: 'View',
              onTap: () => _viewFile(r),
            )
          : AppButton(
              icon: AppIcons.copy,
              label: 'Copy value',
              onTap: () {
                Clipboard.setData(ClipboardData(text: _value(r)));
                AppToast.success(context, 'Copied to clipboard');
              },
            ),
      secondaryActions: [
        if (r.isFile)
          AppButton(
            icon: AppIcons.download,
            tooltip: 'Download',
            style: AppButtonStyle.accent,
            onTap: () => _downloadFile(r),
          ),
        AppButton(
          icon: AppIcons.pencil,
          tooltip: 'Edit',
          style: AppButtonStyle.accent,
          onTap: () => openRecordEditSheet(context, store, r),
        ),
        if (!r.isFile)
          AppButton(
            icon: AppIcons.duplicate,
            tooltip: 'Duplicate',
            style: AppButtonStyle.accent,
            onTap: () => openRecordCreateSheet(
              context: context,
              store: store,
              authStore: Stores.auth,
              initialRecord: r,
            ),
          ),
      ],
    );
  }

  Widget _valueSection(models.Record r) {
    final hidden = r.isHidden && !Stores.vault.isRevealed(r.id);
    final VoidCallback? toggle = r.isHidden
        ? () => Stores.vault.toggleRevealed(r.id)
        : null;

    final List<Widget> rows;
    if (r.isFile) {
      final mime = (r.mime ?? '').split(';').first;
      rows = [
        _ValueRow(
          icon: AppIcons.fileEarmark,
          text: hidden ? '••••••••••••' : r.displayName,
          masked: r.isHidden ? hidden : null,
          onToggle: toggle,
        ),
        AppDetailRow(label: 'Size', value: formatBytes(r.size)),
        if (mime.isNotEmpty) AppDetailRow(label: 'Type', value: mime),
      ];
    } else {
      final value = _value(r);
      final parent = _find(r.aliasOf);
      rows = [
        _ValueRow(
          icon: RecordTypeUtils.icon(r.type),
          text: hidden ? '••••••••••••••••' : (value.isEmpty ? '—' : value),
          masked: r.isHidden ? hidden : null,
          onToggle: toggle,
        ),
        if (r.isAlias)
          AppDetailRow(
            icon: AppIcons.link,
            label: 'Alias of',
            value: parent == null ? r.aliasOf ?? '' : _name(parent),
            onTap: parent == null
                ? null
                : () => context.go(AppRoutes.recordDetailFor(parent.id)),
          ),
      ];
    }

    return AppListGroup(
      title: r.isFile ? 'File' : 'Value',
      trailing: const SizedBox.shrink(),
      children: rows,
    );
  }

  /// Every active link that hands this record out — directly, or because it
  /// shares a section the record is filed in.
  Widget _sharedIn(BuildContext context, models.Record r) {
    final shares = Stores.shares;
    final sections = Stores.vault.sections
        .where((s) => s.records.contains(r.id))
        .toList();

    final via = <String, String?>{}; // link id -> section name, null = direct
    final links = <String, Link>{};
    for (final l in shares.linksForRecord(r.id)) {
      links[l.id] = l;
      via[l.id] = null;
    }
    for (final s in sections) {
      for (final l in shares.linksForSection(s.id)) {
        links.putIfAbsent(l.id, () => l);
        via.putIfAbsent(l.id, () => s.name.isEmpty ? s.key : s.name);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: 'Shared in',
          noun: 'links',
          previewCount: 5,
          trailing: links.isEmpty ? const SizedBox.shrink() : null,
          children: links.isEmpty
              ? const [
                  AppDetailRow(
                    icon: AppIcons.info,
                    label: 'Not in any active link',
                  ),
                ]
              : [
                  for (final l in links.values)
                    AppListRow(
                      icon: AppIcons.link,
                      title: l.label,
                      subtitle: via[l.id] == null
                          ? 'Shared directly'
                          : 'Through section ${via[l.id]}',
                      trailing: AppStatusBadge(l.status),
                      onTap: () => context.go(AppRoutes.shareDetailFor(l.id)),
                    ),
                ],
        ),
        AppListGroup(
          title: 'Sections',
          trailing: sections.isEmpty ? const SizedBox.shrink() : null,
          children: sections.isEmpty
              ? const [
                  AppDetailRow(icon: AppIcons.info, label: 'Not in a section'),
                ]
              : [
                  for (final s in sections)
                    AppDetailRow(
                      icon: AppIcons.folder,
                      label: s.name.isEmpty ? s.key : s.name,
                      value:
                          '${s.records.length} '
                          '${s.records.length == 1 ? 'record' : 'records'}',
                    ),
                ],
        ),
      ],
    );
  }

  /// The owner's own reminders on this record, and the way to add one.
  Widget _reminders(BuildContext context, models.Record r) {
    final list = Stores.reminders.forRecord(r.id);
    String nameOf(String id) {
      final other = _find(id);
      return other == null ? 'another entry' : _name(other);
    }

    return AppListGroup(
      title: 'Reminders',
      trailing: AppButton(
        icon: AppIcons.plus,
        label: 'Add',
        style: AppButtonStyle.accent,
        size: AppButtonSize.small,
        onTap: () => openReminderSheet(context, r),
      ),
      children: list.isEmpty
          ? const [
              AppDetailRow(
                icon: AppIcons.bell,
                label: 'No reminders. Add one for a date, or for a change.',
              ),
            ]
          : [
              for (final rem in list)
                AppListRow(
                  icon: rem.isDate ? AppIcons.calendar : AppIcons.arrowRepeat,
                  title: describeReminder(rem, r.id, nameOf),
                  subtitle: _reminderStatus(rem),
                  showChevron: false,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rem.hasFired)
                        AppButton(
                          icon: AppIcons.arrowClockwise,
                          tooltip: 'Remind me again',
                          style: AppButtonStyle.ghost,
                          size: AppButtonSize.small,
                          onTap: () => _rearmReminder(context, rem),
                        ),
                      AppButton(
                        icon: AppIcons.trash,
                        tooltip: 'Delete reminder',
                        style: AppButtonStyle.ghost,
                        size: AppButtonSize.small,
                        onTap: () => _deleteReminder(context, rem),
                      ),
                    ],
                  ),
                ),
            ],
    );
  }

  String _reminderStatus(Reminder rem) {
    final parts = <String>[
      if (rem.note.isNotEmpty) rem.note,
      if (rem.hasFired)
        'Reminded on ${formatReminderDay(rem.firedAt!)}'
      else if (!rem.isDate)
        'Waiting for a change',
    ];
    return parts.join(' · ');
  }

  Future<void> _rearmReminder(BuildContext context, Reminder rem) async {
    // A date that has passed would fire again at once: ask for a new one.
    if (rem.isDate) {
      final record = _record;
      if (record != null) await openReminderSheet(context, record);
      return;
    }
    final ok = await Stores.reminders.rearm(rem.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'You will be reminded at the next change');
    } else {
      AppToast.error(
        context,
        'Could not update the reminder',
        subtitle: Stores.reminders.error?.description,
      );
    }
  }

  Future<void> _deleteReminder(BuildContext context, Reminder rem) async {
    final ok = await Stores.reminders.delete(rem.id);
    if (!context.mounted || ok) return;
    AppToast.error(
      context,
      'Could not delete the reminder',
      subtitle: Stores.reminders.error?.description,
    );
  }

  Widget _details(models.Record r) {
    return AppListGroup(
      title: 'Details',
      trailing: const SizedBox.shrink(),
      children: [
        AppDetailRow(
          icon: AppIcons.key,
          label: 'Key',
          value: r.key,
          valueMono: true,
        ),
        if (r.isRequested)
          AppDetailRow(
            icon: AppIcons.inboxFill,
            label: 'Requested by',
            value: r.requestedBy ?? '',
          ),
        AppDetailRow(
          icon: AppIcons.plus,
          label: 'Created',
          value: AppEntityCard.formatDate(r.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: AppEntityCard.formatDate(r.updated) ?? '—',
        ),
      ],
    );
  }

  /// Images and text open in the app from memory; anything else goes to the
  /// app the OS uses for that type.
  Future<void> _viewFile(models.Record r) async {
    final bytes = await Stores.vault.fetchRecordFileBytes(r);
    if (!mounted) return;
    if (bytes == null) {
      AppToast.error(
        context,
        'Could not open file',
        subtitle: Stores.vault.errorMessage,
      );
      return;
    }
    await viewFile(
      context,
      bytes: bytes,
      filename: r.displayName,
      mime: r.mime,
    );
  }

  Future<void> _downloadFile(models.Record r) async {
    final bytes = await Stores.vault.fetchRecordFileBytes(r);
    if (bytes == null) {
      if (mounted) {
        AppToast.error(
          context,
          'Could not download file',
          subtitle: Stores.vault.errorMessage,
        );
      }
      return;
    }
    final ok = await saveFileToDevice(
      bytes: bytes,
      filename: r.displayName,
      mime: r.mime,
    );
    if (ok && mounted) AppToast.success(context, 'File saved');
  }

  Future<void> _confirmDelete(BuildContext context, models.Record r) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete record',
      message:
          'This action cannot be undone. This will permanently delete the record.',
      content: ApiPreview(
        spec: VaultStore.deleteRecordSpec(r.id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    _deleting.value = true;
    final ok = await Stores.vault.deleteRecord(r.id);
    _deleting.value = false;
    if (ok && context.mounted) {
      AppToast.success(context, 'Record deleted successfully');
      _back();
    }
  }
}

/// The record's value, in full and in the mono face. A hidden value is masked
/// until the row is tapped, and the row itself is the reveal control.
class _ValueRow extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Null for a value that is never masked; otherwise whether it is masked now.
  final bool? masked;
  final VoidCallback? onToggle;

  const _ValueRow({
    required this.icon,
    required this.text,
    this.masked,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          AppSpacing.gapMd,
          Expanded(child: AppText(text, maxLines: 6).mono),
          if (masked != null) ...[
            AppSpacing.gapSm,
            Tooltip(
              message: masked! ? 'Show' : 'Hide',
              child: Icon(
                masked! ? AppIcons.eye : AppIcons.eyeSlash,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    if (onToggle == null) return row;
    // Square like every row in a card; the card's clip rounds the ends.
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.zero,
      child: row,
    );
  }
}
