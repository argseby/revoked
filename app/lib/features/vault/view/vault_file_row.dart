import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_upload_progress.dart';

/// Only the desktop targets can take a dropped file.
bool get vaultCanDropFiles =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// Stages a picked file on the vault draft, refusal and preview included.
Future<void> pickVaultFile() async {
  final picked = await FilePicker.pickFile();
  if (picked == null) return;
  await Stores.vault.stageFile(await PendingUpload.fromPicked(picked));
}

/// Wraps a drawer so a file dropped anywhere on it stages the same way the
/// picker does.
Widget vaultDropTarget({
  required Widget child,
  Future<void> Function()? onStaged,
}) {
  if (!vaultCanDropFiles) return child;
  return DropTarget(
    onDragDone: (detail) async {
      if (detail.files.isEmpty) return;
      final staged = await PendingUpload.fromDropped(detail.files.first);
      if (staged == null) return;
      await Stores.vault.stageFile(staged);
      await onStaged?.call();
    },
    child: child,
  );
}

/// The vault's one staged-file field: a place to drop or choose a file, then
/// what is attached, with its preview and a way to replace or remove it, and
/// the upload's progress while it runs. Used by the record drawer and by a
/// template's file field, so a file behaves the same wherever it is attached.
class VaultFileRow extends StatelessWidget {
  const VaultFileRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.vault;
        final file = store.pickedFile;
        return AppFormField(
          label: 'File',
          error: store.pickedFileError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (file == null)
                const _DropArea()
              else
                _Attached(file: file, preview: store.pickedFilePreview),
              if (store.isUploading) ...[
                AppSpacing.gapSm,
                AppUploadProgress(
                  sent: store.uploadSent,
                  total: store.uploadTotal,
                  onCancel: store.cancelUpload,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Where a file goes before there is one. The whole drawer takes a drop; this
/// is the place that says so.
class _DropArea extends StatelessWidget {
  const _DropArea();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: scheme.outline),
      ),
      child: InkWell(
        onTap: pickVaultFile,
        borderRadius: AppRadius.allMd,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Icon(AppIcons.filePlus, color: scheme.onSurfaceVariant),
              AppSpacing.gapSm,
              Text(
                vaultCanDropFiles ? 'Drop a file here' : 'Add a file',
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapMd,
              AppButton(
                icon: AppIcons.folder,
                label: 'Choose a file',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: pickVaultFile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The staged file at a glance, and the two things to do with it.
class _Attached extends StatelessWidget {
  final PendingUpload file;
  final Uint8List? preview;

  const _Attached({required this.file, required this.preview});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = Stores.vault.isUploading;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview != null) ...[
            ClipRRect(
              borderRadius: AppRadius.allSm,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: Image.memory(preview!, fit: BoxFit.contain),
              ),
            ),
            AppSpacing.gapMd,
          ],
          Row(
            children: [
              Icon(
                file.isImage ? AppIcons.image : AppIcons.fileEarmark,
                color: scheme.onSurfaceVariant,
              ),
              AppSpacing.gapSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(formatBytes(file.size)).muted.small,
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                icon: AppIcons.arrowRepeat,
                label: 'Replace',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: busy ? null : pickVaultFile,
              ),
              AppButton(
                icon: AppIcons.trash,
                label: 'Remove',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: busy ? null : Stores.vault.clearPickedFile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
