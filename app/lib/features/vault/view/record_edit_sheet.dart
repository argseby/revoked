import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_upload_progress.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';

/// Edits one vault record — its label, value or file, type and masking — in a
/// bottom sheet. Opened from the record's detail page.
void openRecordEditSheet(
  BuildContext context,
  VaultStore store,
  models.Record record,
) {
  store.clearError();
  store.startRecordEdit(record);

  showAppSheet(
    context: context,
    builder: (sheetContext) {
      return Builder(
        builder: (ctx) {
          void validateAndDetectType(String value) {
            final detected = RecordTypeUtils.detectType(value);
            store.setEditRecordTypeCheck(
              warning: RecordTypeUtils.validateValue(
                store.editRecordType,
                value,
              ),
              detected: detected != 'text' && detected != store.editRecordType
                  ? detected
                  : null,
            );
          }

          final isFile = record.isFile;

          return Observer(
            builder: (observerContext) {
              final _ = store.errorMessage;
              final theme = Theme.of(ctx);

              return Column(
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
                        const Text('Edit record').header,
                        const SizedBox(height: AppSpacing.xxs),
                        const Text(
                          'Modify record parameters in your workspace.',
                        ).muted.small,
                      ],
                    ),
                  ),
                  const AppDivider(),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fieldLabel(
                            ctx,
                            'Label',
                            isRequired: true,
                            explanation:
                                'A friendly display name for this record.',
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          AppTextField(
                            controller: store.editRecordLabel,
                            hint: 'My Secret',
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          _fieldLabel(
                            ctx,
                            'Key',
                            isRequired: true,
                            explanation:
                                'A stable identifier for sharing and templates.',
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: AppRadius.allMd,
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(record.key).mono.muted.small,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          if (isFile) ...[
                            _fieldLabel(
                              ctx,
                              'File name',
                              isRequired: true,
                              explanation:
                                  'What a recipient downloads this file as. '
                                  'Renaming never touches the file itself.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: store.editRecordFilename,
                              hint: 'Lebenslauf.pdf',
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            _fieldLabel(
                              ctx,
                              'File',
                              explanation:
                                  'Replacing it updates every active share '
                                  'on its next read.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    store.editPickedFile?.name ??
                                        '${record.displayName} · ${formatBytes(record.size)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ).mono.muted.small,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                AppButton(
                                  icon: AppIcons.arrowRepeat,
                                  label: 'Replace',
                                  size: AppButtonSize.small,
                                  style: AppButtonStyle.accent,
                                  onTap: () async {
                                    final picked = await FilePicker.pickFile();
                                    if (picked == null) return;
                                    await store.stageFile(
                                      await PendingUpload.fromPicked(picked),
                                      forEdit: true,
                                    );
                                  },
                                ),
                              ],
                            ),
                            if (store.pickedFileError != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              AppErrorText(store.pickedFileError!),
                            ],
                            if (store.isUploading) ...[
                              const SizedBox(height: AppSpacing.sm),
                              AppUploadProgress(
                                sent: store.uploadSent,
                                total: store.uploadTotal,
                                onCancel: store.cancelUpload,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                          ] else ...[
                            _fieldLabel(
                              ctx,
                              'Value',
                              isRequired: true,
                              explanation:
                                  'The actual sensitive data or configuration value.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: store.editRecordValue,
                              hint: 'sk-1234...',
                              onChanged: (v) => validateAndDetectType(v),
                            ),
                            if (store.editRecordTypeWarning != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              AppErrorText(store.editRecordTypeWarning!),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                          ],

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: isFile
                                      ? [
                                          _fieldLabel(
                                            ctx,
                                            'Type',
                                            explanation:
                                                'A file record stays a file. '
                                                'To store something else, '
                                                'make a new record.',
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          const Align(
                                            alignment: Alignment.centerLeft,
                                            child: AppBadge(label: 'FILE'),
                                          ),
                                        ]
                                      : [
                                          _fieldLabel(
                                            ctx,
                                            'Type',
                                            explanation:
                                                'How this data should be interpreted.',
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (store
                                                      .editRecordDetectedType !=
                                                  null)
                                                AppButton(
                                                  icon: AppIcons.stars,
                                                  label:
                                                      'Auto: ${store.editRecordDetectedType!.toUpperCase()}',
                                                  size: AppButtonSize.small,
                                                  onTap: () {
                                                    store.setEditRecordType(
                                                      store
                                                          .editRecordDetectedType!,
                                                    );
                                                    validateAndDetectType(
                                                      store
                                                          .editRecordValue
                                                          .text,
                                                    );
                                                  },
                                                ),
                                              ...RecordTypeUtils.supportedTypes.map((
                                                type,
                                              ) {
                                                final isSelected =
                                                    store.editRecordType ==
                                                    type;
                                                return isSelected
                                                    ? AppButton(
                                                        icon:
                                                            RecordTypeUtils.icon(
                                                              type,
                                                            ),
                                                        label: type
                                                            .toUpperCase(),
                                                        onTap: () {},
                                                      )
                                                    : AppButton(
                                                        icon:
                                                            RecordTypeUtils.icon(
                                                              type,
                                                            ),
                                                        label: type
                                                            .toUpperCase(),
                                                        onTap: () {
                                                          store
                                                              .setEditRecordType(
                                                                type,
                                                              );
                                                          validateAndDetectType(
                                                            store
                                                                .editRecordValue
                                                                .text,
                                                          );
                                                        },
                                                        style: AppButtonStyle
                                                            .accent,
                                                      );
                                              }),
                                            ],
                                          ),
                                        ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _fieldLabel(
                                      ctx,
                                      isFile ? 'Hidden name' : 'Hidden Value',
                                      explanation: isFile
                                          ? 'Mask the file name on screen — '
                                                'a name is content too.'
                                          : 'Mask value on screen.',
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    AppButton(
                                      icon: store.editRecordFormat == 'hidden'
                                          ? AppIcons.eyeSlash
                                          : AppIcons.eye,
                                      label: store.editRecordFormat == 'hidden'
                                          ? 'Hidden'
                                          : 'Visible',
                                      style: AppButtonStyle.accent,
                                      onTap: () => store.setEditRecordFormat(
                                        store.editRecordFormat == 'hidden'
                                            ? 'default'
                                            : 'hidden',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          if (store.errorMessage != null) ...[
                            AppAlert(
                              destructive: true,
                              leading: const Icon(AppIcons.exclamation),
                              title: const Text('Error'),
                              content: Text(store.errorMessage!),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],

                          if (isFile)
                            const Text(
                              'Renaming is a normal record update; replacing '
                              'the file sends the same fields as '
                              'multipart/form-data with a "file" part.',
                            ).muted.small
                          else
                            ApiPreview(
                              spec: VaultStore.updateRecordSpec(record.id, {
                                'value': store.editRecordValue.text.trim(),
                                'label': store.editRecordLabel.text.trim(),
                                'type': store.editRecordType,
                                'format': store.editRecordFormat,
                              }),
                              title: 'API request · update',
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
                            onTap: store.isSubmittingEditRecord
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            style: AppButtonStyle.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: AppButton(
                            icon: AppIcons.check,
                            label: 'Save changes',
                            busy: store.isSubmittingEditRecord,
                            onTap:
                                (store.editRecordLabel.text.trim().isEmpty ||
                                    (isFile
                                        ? store.editRecordFilename.text
                                              .trim()
                                              .isEmpty
                                        : store.editRecordValue.text
                                                  .trim()
                                                  .isEmpty ||
                                              store.editRecordTypeWarning !=
                                                  null))
                                ? null
                                : () async {
                                    store.setSubmittingEditRecord(true);

                                    final bool ok;
                                    if (isFile) {
                                      final fields = {
                                        'filename': store
                                            .editRecordFilename
                                            .text
                                            .trim(),
                                        'label': store.editRecordLabel.text
                                            .trim(),
                                        'format': store.editRecordFormat,
                                      };
                                      final staged = store.editPickedFile;
                                      // One write: a rename and a replacement
                                      // must not be able to half-apply.
                                      ok = staged == null
                                          ? await store.updateRecord(
                                              record.id,
                                              fields,
                                            )
                                          : await store.updateRecordFile(
                                              record.id,
                                              staged,
                                              fields: fields,
                                            );
                                    } else {
                                      ok = await store.updateRecord(record.id, {
                                        'value': store.editRecordValue.text
                                            .trim(),
                                        'label': store.editRecordLabel.text
                                            .trim(),
                                        'type': store.editRecordType,
                                        'format': store.editRecordFormat,
                                      });
                                    }

                                    if (ok && ctx.mounted) {
                                      Navigator.of(sheetContext).pop();
                                      AppToast.success(
                                        context,
                                        'Record updated successfully',
                                      );
                                    } else {
                                      store.setSubmittingEditRecord(false);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

Widget _fieldLabel(
  BuildContext context,
  String text, {
  bool isRequired = false,
  String? explanation,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (isRequired)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs),
              child: const AppErrorText('*'),
            ),
        ],
      ),
      if (explanation != null) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(explanation).muted.small,
      ],
    ],
  );
}
