import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:revoked_app/core/widgets/copy_actions.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/record_edit_sheet.dart';

/// Record commands shared by the detail view and contextual options.
class RecordActions {
  final BuildContext context;
  final VoidCallback? onDeleted;
  final ValueChanged<bool>? onBusy;
  const RecordActions(this.context, {this.onDeleted, this.onBusy});

  List<AppSheetAction> forRecord(models.Record r) {
    final store = Stores.vault;
    return [
      if (!r.isLocked)
        AppSheetAction(
          icon: AppIcons.copy,
          label: 'Copy value',
          onTap: () {
            final parent = [
              ...store.records,
              ...store.sharedRecords,
            ].where((p) => p.id == r.aliasOf).firstOrNull;
            Clipboard.setData(
              ClipboardData(text: r.isAlias ? parent?.value ?? '' : r.value),
            );
            AppToast.success(context, 'Copied to clipboard');
          },
        ),
      if (r.isFile && !r.isLocked)
        AppSheetAction(
          icon: AppIcons.download,
          label: 'Download',
          onTap: () => download(r),
        ),
      if (!r.isLocked)
        AppSheetAction(
          icon: AppIcons.share,
          label: 'Share',
          onTap: () => openShareCreateSheet(context: context, records: [r.id]),
        ),
      if (r.user == Stores.auth.userId &&
          Stores.settings.canPublishVault &&
          !r.isFile &&
          !r.isAlias &&
          r.requestedBy == null)
        AppSheetAction(
          icon: AppIcons.personWorkspace,
          label: 'Visibility',
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
        AppSheetAction(
          icon: AppIcons.pencil,
          label: 'Edit',
          onTap: () => openRecordEditSheet(context, store, r),
        ),
      if (Stores.keys.isAvailable && !r.isAlias && !r.isLocked)
        AppSheetAction(
          icon: AppIcons.lock,
          label: r.sealed ? 'Stop encrypting' : 'Encrypt end to end',
          onTap: () => r.sealed ? unseal(r) : seal(r),
        ),
      if (!r.isFile && !r.isLocked)
        AppSheetAction(
          icon: AppIcons.duplicate,
          label: 'Duplicate',
          onTap: () => openRecordCreateSheet(
            context: context,
            store: store,
            authStore: Stores.auth,
            initialRecord: r,
          ),
        ),
      copyIdAction(context, r.id),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: () => delete(r),
      ),
    ];
  }

  /// Encrypts [r] after the confirmations it needs; true once it is.
  Future<bool> seal(models.Record r) async {
    final ready = await ensureSealingReady(context, r.workspace);
    if (!ready || !context.mounted) return false;
    var outcome = await Stores.vault.sealRecord(r.id);
    if (!context.mounted) return outcome == SealOutcome.sealed;
    if (outcome == SealOutcome.linksAffected) {
      final go = await showAppDialog(
        context: context,
        title: 'Some links cannot keep this record',
        message:
            'Links whose keys are readable on this device keep the encrypted entry. '
            'Other links stop showing it, and their owners are notified. '
            'Copies of addresses that gain a key need the complete new address.',
        confirmLabel: 'Encrypt',
        confirmIcon: AppIcons.lock,
      );
      if (!go || !context.mounted) return false;
      outcome = await Stores.vault.sealRecord(r.id, dropLinks: true);
      if (!context.mounted) return outcome == SealOutcome.sealed;
    }
    if (outcome == SealOutcome.sealed) {
      await showAppDialog(
        context: context,
        title: 'Encrypted',
        message:
            'Links kept during encryption now require their complete address, including '
            'the key after #. The server can no longer read this '
            '${r.isFile ? 'file' : 'value'}. Its backups may still hold the '
            'old ${r.isFile ? 'file' : 'value'}. Sensitive secrets should be '
            'rotated.',
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
    return outcome == SealOutcome.sealed;
  }

  /// Stores [r] in plain text again once confirmed; true once it is.
  Future<bool> unseal(models.Record r) async {
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
    if (!go || !context.mounted) return false;
    final ok = await Stores.vault.unsealRecord(r.id);
    if (!ok && context.mounted) {
      AppToast.error(
        context,
        'Encryption could not be turned off.',
        subtitle: Stores.vault.errorMessage,
      );
    }
    return ok;
  }

  Future<void> download(models.Record r) async {
    final bytes = await Stores.vault.fetchRecordFileBytes(r);
    if (bytes == null) {
      if (context.mounted) {
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
    if (ok && context.mounted) AppToast.success(context, 'File saved');
  }

  Future<void> delete(models.Record r) async {
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
    onBusy?.call(true);
    final ok = await Stores.vault.deleteRecord(r.id);
    onBusy?.call(false);
    if (ok && context.mounted) {
      AppToast.success(context, 'Record deleted');
      onDeleted?.call();
    }
  }
}
