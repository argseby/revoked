import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';

/// Opens the record-create / duplicate drawer.
void openRecordCreateSheet({
  required BuildContext context,
  required VaultStore store,
  required AuthStore authStore,
  models.Record? initialRecord,
}) {
  store.clearError();
  showAppSheet(
    context: context,
    builder: (drawerContext) => _RecordCreateDrawer(
      parentContext: context,
      store: store,
      authStore: authStore,
      initialRecord: initialRecord,
    ),
  );
}

/// Inset for a row in a "choose one" sheet, so every picker lines up with
/// the sheet's own padding.
const _pickerRowPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.xl,
  vertical: AppSpacing.md,
);

class _RecordCreateDrawer extends StatefulWidget {
  final BuildContext parentContext;
  final VaultStore store;
  final AuthStore authStore;
  final models.Record? initialRecord;

  const _RecordCreateDrawer({
    required this.parentContext,
    required this.store,
    required this.authStore,
    required this.initialRecord,
  });

  @override
  State<_RecordCreateDrawer> createState() => _RecordCreateDrawerState();
}

class _RecordCreateDrawerState extends State<_RecordCreateDrawer> {
  VaultStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    String? sectionId;
    if (r != null) {
      for (final sec in widget.store.sections) {
        if (sec.records.contains(r.id)) {
          sectionId = sec.id;
          break;
        }
      }
    }
    _store.startRecordDraft(from: r, sectionId: sectionId);
    if (r != null) {
      // Defer key validation until after first build so the warning shows.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateKey(_store.recordKey.text);
      });
    }
  }

  void _validateKey(String input) {
    if (input.isEmpty) {
      _store.setRecordKeyCheck();
      return;
    }
    final exists = widget.store.records.any((r) => r.key == input);
    _store.setRecordKeyCheck(
      warning: exists ? 'This key is already taken.' : null,
      suggestion: exists ? _generateAlternativeKey(input) : null,
    );
  }

  void _validateAndDetectType(String value) {
    final detected = RecordTypeUtils.detectType(value);
    _store.setRecordTypeCheck(
      warning: RecordTypeUtils.validateValue(_store.recordType, value),
      detected: (detected != 'text' && detected != _store.recordType)
          ? detected
          : null,
    );
  }

  String _generateAlternativeKey(String baseKey) {
    String sanitized = baseKey.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (sanitized.isEmpty) sanitized = 'key';
    int counter = 1;
    while (true) {
      final candidate = '${sanitized}_$counter';
      if (!widget.store.records.any((r) => r.key == candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  bool get _isFileType => _store.recordType == 'file';

  static bool get _canDropFiles =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  bool _canSubmit() {
    final base =
        _store.recordLabel.text.trim().isNotEmpty &&
        _store.recordKey.text.trim().isNotEmpty &&
        _store.recordKeyWarning == null;
    if (_isFileType) {
      return base && _store.pickedFileBytes != null;
    }
    return base &&
        _store.recordValue.text.trim().isNotEmpty &&
        _store.recordTypeWarning == null;
  }

  Future<void> _submit() async {
    if (!_canSubmit()) return;
    _store.setSubmittingRecord(true);

    final ok = await widget.store.createRecord(
      key: _store.recordKey.text.trim(),
      value: _isFileType ? '' : _store.recordValue.text,
      label: _store.recordLabel.text.trim(),
      type: _store.recordType,
      format: _store.recordFormat,
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      fileName: _isFileType ? _store.pickedFileName : null,
      fileBytes: _isFileType ? _store.pickedFileBytes : null,
    );

    if (!mounted) return;

    if (!ok) {
      if (widget.parentContext.mounted) {
        AppToast.error(
          widget.parentContext,
          'Could not create record',
          subtitle: widget.store.errorMessage,
        );
      }
      _store.setSubmittingRecord(false);
      return;
    }

    // If we duplicated a record that lived inside a section, attach the
    // new record to that section so the relationship survives.
    if (_store.recordOriginSectionId != null) {
      final newId = widget.store.records.first.id;
      final sec = widget.store.sections.firstWhere(
        (s) => s.id == _store.recordOriginSectionId,
        orElse: () => widget.store.sections.first,
      );
      if (sec.id == _store.recordOriginSectionId) {
        final merged = List<String>.from(sec.records)..add(newId);
        await widget.store.updateSection(sec.id, {'records': merged});
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (widget.parentContext.mounted) {
      AppToast.success(
        widget.parentContext,
        widget.initialRecord != null ? 'Record duplicated' : 'Record created',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final isDup = widget.initialRecord != null;

    final sheet = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
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
                Text(isDup ? 'Duplicate record' : 'New record').header,
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  isDup
                      ? 'Duplicate this record with a new unique key. The value can stay the same.'
                      : 'Store a new piece of information in your vault.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                _buildLabelRow(),
                _buildKeyRow(),
                if (_isFileType) _buildFileRow() else _buildValueRow(),
                _buildTypeRow(),

                const AppFormSectionHeader('Display'),
                AppFormToggleRow(
                  icon: _store.recordFormat == 'hidden'
                      ? AppIcons.eyeSlash
                      : AppIcons.eye,
                  label: 'Hidden value',
                  subtitle: 'Mask the value when shown in the vault.',
                  value: _store.recordFormat == 'hidden',
                  onChanged: (on) =>
                      _store.setRecordFormat(on ? 'hidden' : 'default'),
                ),

                const AppFormSectionHeader('Developer'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: _isFileType
                      ? const Text(
                          'File records upload as multipart/form-data: the '
                          'same fields as form parts, plus the file itself '
                          'as a "file" part.',
                        ).muted.small
                      : ApiPreview(
                          spec: VaultStore.createRecordSpec(
                            key: _store.recordKey.text.trim(),
                            value: _store.recordValue.text,
                            label: _store.recordLabel.text.trim(),
                            type: _store.recordType,
                            format: _store.recordFormat,
                            user: widget.authStore.userId,
                            workspace: widget.authStore.activeWorkspace ?? '',
                          ),
                        ),
                ),
              ],
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
                    onTap: _store.isSubmittingRecord
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: AppButtonStyle.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: isDup ? 'Duplicate Record' : 'Create Record',
                    busy: _store.isSubmittingRecord,
                    onTap: _canSubmit() ? _submit : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return _wrapDropTarget(sheet);
  }

  Widget _buildLabelRow() {
    final v = _store.recordLabel.text.trim();
    return AppFormRow(
      icon: AppIcons.fileText,
      label: 'Label',
      valueText: v.isEmpty ? 'Required' : v,
      isPlaceholder: v.isEmpty,
      isError: v.isEmpty,
      onTap: () async {
        await showAppEditSheet(
          context: context,
          title: 'Label',
          description: 'A friendly display name for this record.',
          controller: _store.recordLabel,
          hint: 'e.g. Production API Key',
        );
      },
    );
  }

  Widget _buildKeyRow() {
    final k = _store.recordKey.text.trim();
    return AppFormRow(
      icon: AppIcons.hash,
      label: 'Key',
      valueText: k.isEmpty ? 'Required' : (_store.recordKeyWarning ?? k),
      isPlaceholder: k.isEmpty,
      isError: k.isEmpty || _store.recordKeyWarning != null,
      onTap: _editKey,
    );
  }

  /// Desktop drops land anywhere on the drawer; dropping a file flips the
  /// draft to the file type, because the gesture already said so.
  Widget _wrapDropTarget(Widget child) {
    if (!_canDropFiles) return child;
    return DropTarget(
      onDragDone: (detail) async {
        if (detail.files.isEmpty) return;
        final dropped = detail.files.first;
        final bytes = await dropped.readAsBytes();
        if (!mounted) return;
        _store.setPickedFile(dropped.name, bytes);
        if (!_isFileType) _store.setRecordType('file');
      },
      child: child,
    );
  }

  static bool _looksLikeImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.bmp');
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    _store.setPickedFile(picked.name, bytes);
  }

  Widget _buildFileRow() {
    final name = _store.pickedFileName;
    final bytes = _store.pickedFileBytes;
    final hasFile = name != null && bytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormRow(
          icon: AppIcons.filePlus,
          label: 'File',
          valueText: hasFile
              ? '$name · ${formatBytes(bytes.length)}'
              : (_canDropFiles
                    ? 'Required — browse, or drop a file anywhere here'
                    : 'Required — tap to pick a file'),
          isPlaceholder: !hasFile,
          isError: !hasFile,
          onTap: _pickFile,
        ),
        if (hasFile && _looksLikeImage(name))
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
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildValueRow() {
    final v = _store.recordValue.text;
    final empty = v.trim().isEmpty;
    final summary = _store.recordFormat == 'hidden' ? '••••••••' : v;
    return AppFormRow(
      icon: AppIcons.key,
      label: 'Value',
      valueText: empty ? 'Required' : (_store.recordTypeWarning ?? summary),
      isPlaceholder: empty,
      isError: empty || _store.recordTypeWarning != null,
      onTap: _editValue,
    );
  }

  Widget _buildTypeRow() {
    final base = _store.recordType.toUpperCase();
    return AppFormRow(
      icon: AppIcons.tag,
      label: 'Type',
      valueText: _store.recordDetectedType != null
          ? '$base · suggested ${_store.recordDetectedType!.toUpperCase()}'
          : base,
      onTap: _pickType,
    );
  }

  Future<void> _editValue() async {
    await showAppEditSheet(
      context: context,
      title: 'Value',
      description: 'The actual sensitive data or configuration value.',
      controller: _store.recordValue,
      hint: 'sk-123456789...',
    );
    if (mounted) _validateAndDetectType(_store.recordValue.text);
  }

  Future<void> _editKey() async {
    await showAppSheet(
      context: context,
      builder: (sheetCtx) {
        return Observer(
          builder: (ctx) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Key').header,
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'A stable identifier used for sharing and templates.',
                  ).muted.small,
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _store.recordKey,
                    hint: 'prod_api_key',
                    autofocus: true,
                    inputFormatters: [KeyInputFormatter()],
                    onChanged: (v) {
                      _validateKey(v);
                    },
                  ),
                  if (_store.recordKeyWarning != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppErrorText(_store.recordKeyWarning!),
                  ],
                  if (_store.recordSuggestedKey != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Use suggested: $_store.recordSuggestedKey',
                        onTap: () {
                          _store.recordKey.text = _store.recordSuggestedKey!;
                          _validateKey(_store.recordKey.text);
                        },
                        style: AppButtonStyle.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Done',
                    onTap:
                        (_store.recordKey.text.trim().isNotEmpty &&
                            _store.recordKeyWarning == null)
                        ? () => Navigator.of(sheetCtx).pop()
                        : null,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickType() async {
    final picked = await showAppSheet<String>(
      context: context,
      builder: (sheetCtx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text('Value type').header,
            ),
            ...RecordTypeUtils.supportedTypes.map((t) {
              final selected = t == _store.recordType;
              final suggested = t == _store.recordDetectedType;
              return AppTile(
                padding: _pickerRowPadding,
                title: Text(t.toUpperCase()),
                subtitle: suggested
                    ? const Text('Suggested for this value').muted.small
                    : null,
                trailing: selected
                    ? Icon(
                        AppIcons.check,
                        color: Theme.of(sheetCtx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetCtx).pop(t),
              );
            }),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      _store.recordType = picked;
      _validateAndDetectType(_store.recordValue.text);
    }
  }
}
