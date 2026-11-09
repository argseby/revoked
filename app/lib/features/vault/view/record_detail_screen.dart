import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/reminder.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/tool_tag.dart';
import 'package:revoked_app/core/utils/people.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/file_view_sheet.dart';
import 'package:revoked_app/features/reminders/view/reminder_sheet.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/record_edit_sheet.dart';
import 'package:revoked_app/core/widgets/redacted_value.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

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
    return AppBarTitle(title: 'Vault', onBack: _back);
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
            return const AppDetailSkeleton(
              badges: ['text'],
              primary: 'Copy value',
              icons: 3,
              sections: [
                AppSkeletonGroup('Value'),
                AppSkeletonGroup('Who can see this'),
                AppSkeletonGroup('Sections'),
                AppSkeletonGroup('Reminders'),
              ],
            );
          }
          return AppEmptyState(
            icon: AppIcons.safe,
            title: 'Record not found',
            subtitle: 'The record may have been deleted.',
            action: AppButton(
              icon: AppIcons.arrowLeft,
              label: 'Back to vault',
              style: AppButtonStyle.accent,
              onTap: _back,
            ),
          );
        }

        final openAccess = accessForRecord(
          record.id,
          links: Stores.shares.shares,
          sections: Stores.vault.sections,
          records: Stores.vault.records,
        ).where((a) => a.isOpen).length;
        return AppDetailPage(
          header: _header(context, record),
          sections: [
            if (record.unsealedElsewhere) _unsealedElsewhereAlert(record),
            _valueSection(record),
            if (record.sealed)
              _readableBy(record)
            else
              _sharedIn(context, record),
            _reminders(context, record),
          ],
          aside: [
            _details(record),
            AppDetailManage(
              note: openAccess == 0
                  ? null
                  : '$openAccess open '
                        '${openAccess == 1 ? 'link shows' : 'links show'} '
                        'this record. Deleting it removes it from '
                        '${openAccess == 1 ? 'that link' : 'them'}. The '
                        '${openAccess == 1 ? 'link stays' : 'links stay'} '
                        'open.',
              actions: [
                AppButton(
                  icon: AppIcons.trash,
                  label: 'Delete',
                  style: AppButtonStyle.danger,
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
      // The type is a fact about the record, not a state, so it reads with
      // the key rather than among the badges.
      badges: [
        if (r.isHidden)
          const AppBadge(icon: AppIcons.eyeSlash, label: 'Hidden'),
        if (r.sealed)
          const AppBadge(icon: AppIcons.lock, label: 'End-to-end encrypted'),
        if (r.isAlias) const AppBadge(icon: AppIcons.link, label: 'Alias'),
        if (r.isRequested)
          AppBadge(
            icon: AppIcons.inboxFill,
            label: 'Requested by ${r.requestedBy}',
          ),
        if (r.isWrittenByTool)
          AppBadge(icon: AppIcons.plug, label: 'Added by ${r.writerName}'),
      ],
      title: _name(r),
      subtitle: '${r.key} · ${RecordTypeUtils.label(r.type)}',
      subtitleMono: true,
      primaryAction: r.isFile
          ? AppButton(
              icon: AppIcons.eye,
              label: 'View',
              onTap: () => _viewFile(r),
            )
          : r.isLocked
          ? AppButton(
              icon: AppIcons.personPlus,
              label: 'Add this device',
              onTap: () => context.go(
                AppRoutes.settingsPage(SettingsPage.encryption.slug),
              ),
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
        if (!r.sealed)
          AppButton(
            icon: AppIcons.share,
            tooltip: 'Share',
            style: AppButtonStyle.accent,
            onTap: () =>
                openShareCreateSheet(context: context, records: [r.id]),
          ),
        // Its own visibility, for its owner, when they may publish: an alias,
        // a file and an answer stay with them.
        if (r.user == Stores.auth.userId &&
            Stores.settings.canPublishVault &&
            !r.isFile &&
            !r.isAlias &&
            r.requestedBy == null)
          AppButton(
            icon: AppIcons.personWorkspace,
            tooltip: 'Visibility',
            style: AppButtonStyle.accent,
            onTap: () => openAccessSheet(
              context,
              area: AccessArea.records,
              id: r.id,
              name: r.label.isEmpty ? r.key : r.label,
              audienceKind: r.audienceKind,
              editing: r.editing,
              save: (kind, editing, groups) => store.updateRecord(r.id, {
                'audienceKind': kind,
                'editing': editing,
                'audienceGroups': groups,
              }),
              saveError: () => store.errorMessage,
            ),
          ),
        if (!r.isLocked && !r.unsealedElsewhere)
          AppButton(
            icon: AppIcons.pencil,
            tooltip: 'Edit',
            style: AppButtonStyle.accent,
            onTap: () => openRecordEditSheet(context, store, r),
          ),
        if (Stores.keys.isAvailable && !r.isFile && !r.isAlias && !r.isLocked)
          AppButton(
            icon: AppIcons.lock,
            tooltip: r.sealed ? 'Stop encrypting' : 'Encrypt end to end',
            style: AppButtonStyle.accent,
            onTap: () => r.sealed ? _unseal(r) : _seal(r),
          ),
        if (!r.isFile && !r.isLocked)
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

  Future<void> _seal(models.Record r) async {
    final ready = await ensureSealingReady(context, r.workspace);
    if (!ready || !mounted) return;
    var outcome = await Stores.vault.sealRecord(r.id);
    if (!mounted) return;
    if (outcome == SealOutcome.linksAffected) {
      final go = await showAppDialog(
        context: context,
        title: 'Remove this record from links?',
        message:
            'Links cannot show an encrypted record, so it is removed from them. '
            'In a shared section, it reappears only if encryption is turned '
            'off.',
        confirmLabel: 'Encrypt',
        confirmIcon: AppIcons.lock,
      );
      if (!go || !mounted) return;
      outcome = await Stores.vault.sealRecord(r.id, dropLinks: true);
      if (!mounted) return;
    }
    if (outcome == SealOutcome.sealed) {
      await showAppDialog(
        context: context,
        title: 'Encrypted',
        message:
            'The server can no longer read this value. Its backups may still hold '
            'the old value. Sensitive secrets should be rotated.',
        confirmLabel: 'OK',
        confirmIcon: AppIcons.check,
        cancelLabel: null,
      );
    } else if (outcome == SealOutcome.failed) {
      AppToast.error(
        context,
        'The record could not be encrypted.',
        subtitle: Stores.vault.errorMessage,
      );
    }
  }

  Future<void> _unseal(models.Record r) async {
    final go = await showAppDialog(
      context: context,
      title: 'Stop encrypting this record?',
      message:
          'The server will be able to read it again. Section links that '
          'include it will show it again.',
      confirmLabel: 'Stop encrypting',
      confirmIcon: AppIcons.lock,
      destructive: true,
    );
    if (!go) return;
    final ok = await Stores.vault.unsealRecord(r.id);
    if (!ok && mounted) {
      AppToast.error(
        context,
        'Encryption could not be turned off.',
        subtitle: Stores.vault.errorMessage,
      );
    }
  }

  Widget _unsealedElsewhereAlert(models.Record r) => AppAlert(
    destructive: true,
    title: const Text('This record is no longer encrypted'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'If encryption was not turned off on another device, this value '
          'should not be trusted.',
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          icon: AppIcons.check,
          label: 'Confirm change',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => Stores.vault.acceptUnsealedRecord(r.id),
        ),
      ],
    ),
  );

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
          text: r.displayName,
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
          text: r.isLocked
              ? 'Not readable on this device'
              : (value.isEmpty ? '—' : value),
          masked: r.isHidden && !r.isLocked ? hidden : null,
          onToggle: r.isLocked ? null : toggle,
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

  /// An encrypted record is read by this person's devices and nothing else, so
  /// the links section would be empty. This says who those devices are.
  Widget _readableBy(models.Record r) {
    final keys = Stores.keys;
    final chain = keys.chain;
    final devices = chain.live
        .where((e) => e.kind == DeviceChainEntry.kindDevice)
        .toList();
    return AppListGroup(
      title: 'Who can read this',
      trailing: const SizedBox.shrink(),
      footer: const Text(
        'Not readable by the server, links or other workspace members.',
      ).muted.small,
      children: chain.entries.isEmpty
          ? [
              const AppListRow(
                icon: AppIcons.lock,
                title: 'Your devices',
                subtitle: 'Listed once this device is added',
                showChevron: false,
              ),
            ]
          : [
              for (final d in devices)
                AppListRow(
                  icon: AppIcons.shieldLock,
                  title: d.seq == keys.thisDeviceSeq ? 'This device' : d.label,
                  subtitle: d.seq == keys.thisDeviceSeq ? d.label : null,
                  showChevron: false,
                ),
              for (final p in chain.livePasskeys)
                AppListRow(
                  icon: AppIcons.key,
                  title: p.label,
                  subtitle: 'Passkey · any device signed in with it',
                  showChevron: false,
                ),
            ],
    );
  }

  /// Every active link that hands this record out — directly, or because it
  /// shares a section the record is filed in.
  Widget _sharedIn(BuildContext context, models.Record r) {
    final sections = Stores.vault.sections
        .where((s) => s.records.contains(r.id))
        .toList();
    final access = accessForRecord(
      r.id,
      links: Stores.shares.shares,
      sections: Stores.vault.sections,
      records: Stores.vault.records,
    );
    final open = access.where((a) => a.isOpen).toList();
    final closed = access.length - open.length;
    final rowActions = !AppSpacing.isNarrow(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: 'Who can see this',
          noun: 'links',
          previewCount: 5,
          // Wide, each row has its own button, so the header only offers to
          // revoke several at once. On a phone the rows have no room for one.
          trailing: open.isEmpty || (rowActions && open.length == 1)
              ? const SizedBox.shrink()
              : AppButton(
                  icon: AppIcons.xCircle,
                  label: open.length == 1 ? 'Revoke' : 'Revoke all',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () => _confirmRevokeAll(context, r, open),
                ),
          footer: closed == 0
              ? null
              : Text(
                  '$closed of these ${closed == 1 ? 'is' : 'are'} closed '
                  'and no longer show${closed == 1 ? 's' : ''} this record.',
                ).muted.small,
          children: access.isEmpty
              ? [
                  AppListRow(
                    icon: AppIcons.lock,
                    title: 'Only you',
                    subtitle: 'Not shared through any link',
                    onTap: () =>
                        openShareCreateSheet(context: context, records: [r.id]),
                    trailing: const AppBadge(
                      icon: AppIcons.share,
                      label: 'Share',
                      variant: AppBadgeVariant.outline,
                    ),
                  ),
                ]
              : [
                  for (final a in access)
                    AppListRow(
                      icon: switch (a.kind) {
                        AccessKind.link => AppIcons.link,
                        AccessKind.requestAnswer => AppIcons.inboxFill,
                        AccessKind.tool => AppIcons.plug,
                      },
                      title: a.link.label,
                      subtitle: '${a.audience} · ${a.route}',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusLabel(a.link.status),
                          if (a.isOpen && rowActions) ...[
                            AppSpacing.gapXs,
                            AppButton(
                              icon: AppIcons.shieldSlash,
                              label: a.kind == AccessKind.requestAnswer
                                  ? 'Withdraw'
                                  : 'Revoke',
                              style: AppButtonStyle.ghost,
                              size: AppButtonSize.small,
                              onTap: () => _confirmRevokeAll(context, r, [a]),
                            ),
                          ],
                        ],
                      ),
                      onTap: () =>
                          context.go(AppRoutes.shareDetailFor(a.link.id)),
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

  /// Closes every open link that shows [r]. A link may carry other records
  /// too; the dialog says so, because revoking it closes those as well.
  Future<void> _confirmRevokeAll(
    BuildContext context,
    models.Record r,
    List<RecordAccess> open,
  ) async {
    final n = open.length;
    final confirmed = await showAppDialog(
      context: context,
      title: n == 1 ? 'Revoke this link?' : 'Revoke all $n links?',
      message:
          '${_name(r)} is no longer visible through '
          '${n == 1 ? 'it' : 'them'}, and neither is anything else '
          '${n == 1 ? 'the link shares' : 'these links share'}. '
          'The record stays in the vault. This cannot be undone.',
      confirmLabel: n == 1 ? 'Revoke' : 'Revoke all',
      confirmIcon: AppIcons.xCircle,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    var failed = 0;
    for (final a in open) {
      final ok = await Stores.shares.updateShare(a.link.id, {
        'status': 'revoked',
      });
      if (!ok) failed++;
    }
    if (!context.mounted) return;
    if (failed == 0) {
      AppToast.success(context, n == 1 ? 'Link revoked' : '$n links revoked');
    } else {
      AppToast.error(
        context,
        '$failed of $n links could not be revoked.',
        subtitle: Stores.shares.errorMessage,
      );
    }
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
                label:
                    'No reminders. A reminder can be set for a date or the next change.',
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
                          tooltip: 'Remind again',
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
      AppToast.success(context, 'Reminder set for the next change');
    } else {
      AppToast.error(
        context,
        'The reminder could not be updated.',
        subtitle: Stores.reminders.error?.description,
      );
    }
  }

  Future<void> _deleteReminder(BuildContext context, Reminder rem) async {
    final ok = await Stores.reminders.delete(rem.id);
    if (!context.mounted || ok) return;
    AppToast.error(
      context,
      'The reminder could not be deleted.',
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
        if (r.isWrittenByTool)
          AppDetailRow(
            icon: AppIcons.plug,
            label: 'Added by',
            value: r.writerName,
            badge: ToolIdChip(r.writtenBy),
            onTap: () => _openWriter(r),
          ),
        if (r.isWrittenByTool)
          if (memberEmail(r.user) case final email?)
            AppDetailRow(
              icon: AppIcons.person,
              label: 'Connected by',
              value: email,
            ),
        AppDetailRow(
          icon: AppIcons.plus,
          label: 'Created',
          value: dayTimeOf(r.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: dayTimeOf(r.updated) ?? '—',
        ),
      ],
    );
  }

  /// Opens the tool that wrote the record, or the API keys when a key did.
  Future<void> _openWriter(models.Record r) async {
    if (Stores.connections.connections.isEmpty) {
      await Stores.connections.load();
    }
    if (!mounted) return;
    for (final c in Stores.connections.connections) {
      if (c.id == r.writtenBy) {
        context.go(AppRoutes.connectedToolFor(c.id));
        return;
      }
    }
    context.go(AppRoutes.apiKeys);
  }

  /// Images and text open in the app from memory; anything else goes to the
  /// app the OS uses for that type.
  Future<void> _viewFile(models.Record r) async {
    final bytes = await Stores.vault.fetchRecordFileBytes(r);
    if (!mounted) return;
    if (bytes == null) {
      AppToast.error(
        context,
        'The file could not be opened.',
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
          'The file could not be downloaded.',
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
          'The record is removed from every link that shows it. The links '
          'stay open. This cannot be undone.',
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
      AppToast.success(context, 'Record deleted');
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
          Expanded(
            child: masked ?? false
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: RedactionBar(
                      width: (text.length * 9.0).clamp(48.0, 240.0),
                    ),
                  )
                : AppText(text, maxLines: 6).mono,
          ),
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
    return Semantics(
      button: true,
      label: masked! ? 'Hidden value. Show' : 'Hide value',
      child: AppFocusRing(
        borderRadius: BorderRadius.zero,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.zero,
          child: row,
        ),
      ),
    );
  }
}
