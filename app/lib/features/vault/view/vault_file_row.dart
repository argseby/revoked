import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/stores.dart';
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

/// The vault's one staged-file row: what is attached (or why it was refused),
/// an image preview, and the upload's progress while it runs. Used by the
/// record drawer and by a template's file field, so a file behaves the same
/// wherever it is attached.
class VaultFileRow extends StatelessWidget {
  const VaultFileRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.vault;
        final file = store.pickedFile;
        final refusal = store.pickedFileError;
        final preview = store.pickedFilePreview;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormRow(
              icon: AppIcons.filePlus,
              label: 'File',
              valueText:
                  refusal ??
                  (file != null
                      ? '${file.name} · ${formatBytes(file.size)}'
                      : (vaultCanDropFiles
                            ? 'Required — browse, or drop a file anywhere here'
                            : 'Required — tap to pick a file')),
              isPlaceholder: file == null,
              isError: file == null || refusal != null,
              onTap: pickVaultFile,
            ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: AppRadius.allMd,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Image.memory(preview, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            if (store.isUploading)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: AppUploadProgress(
                  sent: store.uploadSent,
                  total: store.uploadTotal,
                  onCancel: store.cancelUpload,
                ),
              ),
          ],
        );
      },
    );
  }
}
