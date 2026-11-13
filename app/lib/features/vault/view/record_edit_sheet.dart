import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_upload_progress.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/view/record_actions.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';

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
          // As the record's own Visibility and Encrypt actions offer them.
          final offerAccess =
              record.user == Stores.auth.userId &&
              !isFile &&
              !record.isAlias &&
              record.requestedBy == null;
          final offerEncryption =
              (Stores.keys.isAvailable || record.sealed) && !record.isAlias;

          Future<void> setEncrypted(bool on) async {
            if (!on) {
              store.setEditRecordSealed(false);
              return;
            }
            store.setPreparingEditEncryption(true);
            try {
              final ready = await ensureSealingReady(ctx, record.workspace);
              if (ready) store.setEditRecordSealed(true);
            } finally {
              store.setPreparingEditEncryption(false);
            }
          }

          return Observer(
            builder: (observerContext) {
              final _ = store.errorMessage;
              final theme = Theme.of(ctx);
              final hidden = store.editRecordFormat == 'hidden';
              void setHidden(bool on) =>
                  store.setEditRecordFormat(on ? 'hidden' : 'default');
              void pickType(String type) {
                final from = store.editRecordType;
                store.setEditRecordType(type);
                store.editRecordValue.text = recordValueForType(
                  type,
                  store.editRecordValue.text,
                  from: from,
                );
                validateAndDetectType(store.editRecordValue.text);
              }

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
                        const Text('Label, key and value').muted.small,
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
                            explanation: 'Display name for this record',
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
                            explanation: 'Identifier for links and templates',
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
                          _fieldLabel(
                            ctx,
                            'Type',
                            explanation: isFile
                                ? 'The type of a file record cannot be '
                                      'changed.'
                                : 'Kind of value stored',
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          if (isFile)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: AppBadge(label: 'FILE'),
                            )
                          else
                            RecordTypeChoice(
                              selected: store.editRecordType,
                              detected: store.editRecordDetectedType,
                              onPicked: pickType,
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          if (isFile) ...[
                            _fieldLabel(
                              ctx,
                              'File name',
                              isRequired: true,
                              explanation:
                                  'The name used for downloads. The file '
                                  'itself is unchanged.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: store.editRecordFilename,
                              hint: 'Lebenslauf.pdf',
                            ),
                            RecordHiddenToggle(
                              isFile: true,
                              hidden: hidden,
                              onChanged: setHidden,
                              inset: false,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _fieldLabel(
                              ctx,
                              'File',
                              explanation:
                                  'A replacement is served to every open '
                                  'link.',
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
                              const SizedBox(height: AppSpacing.sm),
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
                          ] else ...[
                            _fieldLabel(
                              ctx,
                              'Value',
                              isRequired: true,
                              explanation:
                                  'The stored value, such as a password or '
                                  'an IBAN',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            RecordValueField(
                              type: store.editRecordType,
                              controller: store.editRecordValue,
                              onChanged: validateAndDetectType,
                            ),
                            if (store.editRecordTypeWarning != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              AppErrorText(store.editRecordTypeWarning!),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                            RecordHiddenToggle(
                              hidden: hidden,
                              onChanged: setHidden,
                              inset: false,
                            ),
                          ],
                          if (offerAccess) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _fieldLabel(
                              ctx,
                              'Visible to',
                              explanation: 'Who in this workspace can see it.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            VisibleToField(
                              showLabel: false,
                              value: store.editRecordAudience,
                              groups: store.editRecordGroups,
                              canPublish: Stores.settings.canPublishVault,
                            ),
                          ],
                          if (offerEncryption) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _fieldLabel(
                              ctx,
                              'End-to-end encryption',
                              explanation: isFile
                                  ? 'Encrypts the file and its name on this '
                                        'device before upload.'
                                  : 'Encrypts the value on this device before '
                                        'upload.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppCheckRow(
                              label: isFile
                                  ? 'Encrypt this file'
                                  : 'Encrypt this value',
                              subtitle:
                                  'Only this account’s devices can open it.',
                              badge: const AppBadge(label: 'Alpha'),
                              value: store.editRecordSealed,
                              onChanged: store.isPreparingEditEncryption
                                  ? null
                                  : setEncrypted,
                            ),
                            if (store.isPreparingEditEncryption) ...[
                              const SizedBox(height: AppSpacing.sm),
                              const Text('Preparing encryption…').small.muted,
                            ],
                            if (store.editRecordSealed) ...[
                              const SizedBox(height: AppSpacing.sm),
                              SealedReadabilityNote(
                                workspace: record.workspace,
                              ),
                            ],
                          ],
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
                          else if (!record.sealed && !store.editRecordSealed)
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
                        AppButton(
                          label: 'Cancel',
                          onTap: store.isSubmittingEditRecord
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          style: AppButtonStyle.accent,
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

                                    // Encryption changes first: its
                                    // confirmations can still stop the save
                                    // before anything is written.
                                    if (store.editRecordSealed !=
                                        record.sealed) {
                                      final actions = RecordActions(ctx);
                                      final changed = store.editRecordSealed
                                          ? await actions.seal(record)
                                          : await actions.unseal(record);
                                      if (!changed) {
                                        store.setSubmittingEditRecord(false);
                                        return;
                                      }
                                    }

                                    var ok = true;
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

                                    if (ok &&
                                        offerAccess &&
                                        Stores.settings.canPublishVault) {
                                      ok = await _saveAudience(store, record);
                                    }

                                    if (ok && ctx.mounted) {
                                      Navigator.of(sheetContext).pop();
                                      AppToast.success(
                                        context,
                                        'Record updated',
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

/// Sends the audience chosen in the sheet, when it differs from the record's
/// current one. Compared with the record as it is now: encrypting it first
/// may already have changed who sees it.
Future<bool> _saveAudience(VaultStore store, models.Record record) async {
  final chosen = chosenAudience(
    store.editRecordAudience,
    store.editRecordGroups,
  );
  final current = store.visibleRecord(record.id) ?? record;
  final sameGroups =
      chosen.groups.length == current.audienceGroups.length &&
      chosen.groups.toSet().containsAll(current.audienceGroups);
  if (chosen.kind == current.audienceKind && sameGroups) return true;
  return store.updateRecord(record.id, {
    'audienceKind': chosen.kind,
    'editing': chosen.kind == 'private' ? 'owner' : current.editing,
    'audienceGroups': chosen.groups,
  });
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
