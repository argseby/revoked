import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';

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
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _labelCtrl;
  String _selectedType = 'text';
  String _selectedFormat = 'default';

  String? _keyWarning;
  String? _suggestedKey;

  String? _typeWarning;
  String? _detectedType;

  /// If duplicating a record that lives in a section, link the new record
  /// to the same section on save.
  String? _originSectionId;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    _keyCtrl = TextEditingController(text: r != null ? '${r.key}_1' : '');
    _valueCtrl = TextEditingController(text: r?.value ?? '');
    _labelCtrl = TextEditingController(text: r?.label ?? '');
    if (r != null) {
      _selectedType = r.type;
      _selectedFormat = r.format;
      for (final sec in widget.store.sections) {
        if (sec.records.contains(r.id)) {
          _originSectionId = sec.id;
          break;
        }
      }
      // Defer key validation until after first build so the warning shows.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateKey(_keyCtrl.text);
      });
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _validateKey(String input) {
    if (input.isEmpty) {
      setState(() {
        _keyWarning = null;
        _suggestedKey = null;
      });
      return;
    }
    final exists = widget.store.records.any((r) => r.key == input);
    if (exists) {
      final alt = _generateAlternativeKey(input);
      setState(() {
        _keyWarning = 'This key is already taken.';
        _suggestedKey = alt;
      });
    } else {
      setState(() {
        _keyWarning = null;
        _suggestedKey = null;
      });
    }
  }

  void _validateAndDetectType(String value) {
    setState(() {
      _typeWarning = RecordTypeUtils.validateValue(_selectedType, value);
      final detected = RecordTypeUtils.detectType(value);
      if (detected != 'text' && detected != _selectedType) {
        _detectedType = detected;
      } else {
        _detectedType = null;
      }
    });
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

  bool _canSubmit() {
    return _labelCtrl.text.trim().isNotEmpty &&
        _keyCtrl.text.trim().isNotEmpty &&
        _valueCtrl.text.trim().isNotEmpty &&
        _keyWarning == null &&
        _typeWarning == null;
  }

  Future<void> _submit() async {
    if (!_canSubmit()) return;
    setState(() => _isSubmitting = true);

    final ok = await widget.store.createRecord(
      key: _keyCtrl.text.trim(),
      value: _valueCtrl.text,
      label: _labelCtrl.text.trim(),
      type: _selectedType,
      format: _selectedFormat,
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
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
      setState(() => _isSubmitting = false);
      return;
    }

    // If we duplicated a record that lived inside a section, attach the
    // new record to that section so the relationship survives.
    if (_originSectionId != null) {
      final newId = widget.store.records.first.id;
      final sec = widget.store.sections.firstWhere(
        (s) => s.id == _originSectionId,
        orElse: () => widget.store.sections.first,
      );
      if (sec.id == _originSectionId) {
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
    final isDup = widget.initialRecord != null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
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

          // Body
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                _buildLabelRow(),
                _buildKeyRow(),
                _buildValueRow(),
                _buildTypeRow(),

                const AppFormSectionHeader('Display'),
                AppFormToggleRow(
                  icon: _selectedFormat == 'hidden'
                      ? AppIcons.eyeSlash
                      : AppIcons.eye,
                  label: 'Hidden value',
                  subtitle: 'Mask the value when shown in the vault.',
                  value: _selectedFormat == 'hidden',
                  onChanged: (on) => setState(
                    () => _selectedFormat = on ? 'hidden' : 'default',
                  ),
                ),

                const AppFormSectionHeader('Developer'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: ApiPreview(
                    spec: VaultStore.createRecordSpec(
                      key: _keyCtrl.text.trim(),
                      value: _valueCtrl.text,
                      label: _labelCtrl.text.trim(),
                      type: _selectedType,
                      format: _selectedFormat,
                      user: widget.authStore.userId,
                      workspace: widget.authStore.activeWorkspace ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AppDivider(),

          // Footer
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
                    onTap: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: AppButtonStyle.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: isDup ? 'Duplicate' : 'Create',
                    busy: _isSubmitting,
                    onTap: _canSubmit() ? _submit : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Rows ------------------------------------------------------------

  Widget _buildLabelRow() {
    final v = _labelCtrl.text.trim();
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
          controller: _labelCtrl,
          hint: 'e.g. Production API Key',
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildKeyRow() {
    final k = _keyCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.hash,
      label: 'Key',
      valueText: k.isEmpty ? 'Required' : (_keyWarning ?? k),
      isPlaceholder: k.isEmpty,
      isError: k.isEmpty || _keyWarning != null,
      onTap: _editKey,
    );
  }

  Widget _buildValueRow() {
    final v = _valueCtrl.text;
    final empty = v.trim().isEmpty;
    final summary = _selectedFormat == 'hidden' ? '••••••••' : v;
    return AppFormRow(
      icon: AppIcons.key,
      label: 'Value',
      valueText: empty ? 'Required' : (_typeWarning ?? summary),
      isPlaceholder: empty,
      isError: empty || _typeWarning != null,
      onTap: _editValue,
    );
  }

  Widget _buildTypeRow() {
    final base = _selectedType.toUpperCase();
    return AppFormRow(
      icon: AppIcons.tag,
      label: 'Type',
      valueText: _detectedType != null
          ? '$base · suggested ${_detectedType!.toUpperCase()}'
          : base,
      onTap: _pickType,
    );
  }

  // --- Sub-sheets ------------------------------------------------------

  Future<void> _editValue() async {
    await showAppEditSheet(
      context: context,
      title: 'Value',
      description: 'The actual sensitive data or configuration value.',
      controller: _valueCtrl,
      hint: 'sk-123456789...',
    );
    if (mounted) _validateAndDetectType(_valueCtrl.text);
  }

  Future<void> _editKey() async {
    await showAppSheet(
      context: context,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
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
                    controller: _keyCtrl,
                    hint: 'prod_api_key',
                    autofocus: true,
                    inputFormatters: [KeyInputFormatter()],
                    onChanged: (v) {
                      _validateKey(v);
                      setSheet(() {});
                    },
                  ),
                  if (_keyWarning != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppErrorText(_keyWarning!),
                  ],
                  if (_suggestedKey != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Use suggested: $_suggestedKey',
                        onTap: () {
                          _keyCtrl.text = _suggestedKey!;
                          _validateKey(_keyCtrl.text);
                          setSheet(() {});
                        },
                        style: AppButtonStyle.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Done',
                    onTap:
                        (_keyCtrl.text.trim().isNotEmpty && _keyWarning == null)
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
    if (mounted) setState(() {});
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
              final selected = t == _selectedType;
              final suggested = t == _detectedType;
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
      _selectedType = picked;
      _validateAndDetectType(_valueCtrl.text);
    }
  }
}
