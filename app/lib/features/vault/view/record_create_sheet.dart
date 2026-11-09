import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';
import 'package:revoked_app/features/vault/view/vault_file_row.dart';

/// Opens the record-create / duplicate drawer.
void openRecordCreateSheet({
  required BuildContext context,
  required VaultStore store,
  required AuthStore authStore,
  models.Record? initialRecord,
}) {
  store.clearError();
  unawaited(Stores.keys.ensureLoaded());
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

/// The record form on its own, for the vault's combined create drawer: the
/// same form, minus the title the drawer already carries.
Widget recordCreateForm({
  required BuildContext parentContext,
  String? initialType,
}) => _RecordCreateDrawer(
  parentContext: parentContext,
  store: Stores.vault,
  authStore: Stores.auth,
  initialRecord: null,
  initialType: initialType,
  embedded: true,
);

class _RecordCreateDrawer extends StatefulWidget {
  final BuildContext parentContext;
  final VaultStore store;
  final AuthStore authStore;
  final models.Record? initialRecord;

  /// The type a new record starts as; the form's own default when null.
  final String? initialType;

  /// Rendered inside a drawer that already has a title and its own tabs.
  final bool embedded;

  const _RecordCreateDrawer({
    required this.parentContext,
    required this.store,
    required this.authStore,
    required this.initialRecord,
    this.initialType,
    this.embedded = false,
  });

  @override
  State<_RecordCreateDrawer> createState() => _RecordCreateDrawerState();
}

class _RecordCreateDrawerState extends State<_RecordCreateDrawer> {
  VaultStore get _store => widget.store;

  /// Who sees the new entry: the workspace's default, else private. Only a
  /// member who may publish to the workspace vault can choose more.
  final Local<String> _visibility = Local(
    Stores.settings.canPublishVault
        ? Stores.settings.defaultAudienceFor('records')
        : 'private',
  );
  final Local<Set<String>> _groups = Local(const {});

  ({String kind, List<String> groups}) get _audience => chosenAudience(
    _visibility,
    _groups,
    canPublish: Stores.settings.canPublishVault && !_isFileType,
  );

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
    if (r == null && widget.initialType != null) {
      _store.setRecordType(widget.initialType!);
    }
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
      warning: exists ? 'This key is already in use.' : null,
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

  /// The key the record is saved under: the one typed under Advanced, or one
  /// made from the label. Most people never see a key, so it is never
  /// required of them.
  String get _effectiveKey {
    final typed = _store.recordKey.text.trim();
    if (typed.isNotEmpty) return typed;
    return keyFromLabel(
      _store.recordLabel.text,
      widget.store.records.map((r) => r.key),
    );
  }

  bool _canSubmit() {
    final base =
        _store.recordLabel.text.trim().isNotEmpty &&
        _store.recordKeyWarning == null;
    if (_isFileType) {
      return base && _store.pickedFile != null;
    }
    return base &&
        _store.recordValue.text.trim().isNotEmpty &&
        _store.recordTypeWarning == null;
  }

  Future<void> _submit() async {
    if (!_canSubmit()) return;
    _store.setSubmittingRecord(true);

    final ok = await widget.store.createRecord(
      key: _effectiveKey,
      value: _isFileType ? '' : _store.recordValue.text,
      label: _store.recordLabel.text.trim(),
      type: _store.recordType,
      format: _store.recordFormat,
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      file: _isFileType ? _store.pickedFile : null,
      sealed: !_isFileType && _store.recordSealed,
      audienceKind: _audience.kind,
      audienceGroups: _audience.groups,
    );

    if (!mounted) return;

    if (!ok) {
      if (widget.parentContext.mounted) {
        AppToast.error(
          widget.parentContext,
          'The record could not be created.',
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
        // Embedded, the form fills its tab so the footer sits on the drawer's
        // bottom edge rather than floating above a gap.
        mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded) ...[
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
                        ? 'Creates a copy of this record under a new key.'
                        : 'Stores a single value in the vault.',
                  ).muted.small,
                ],
              ),
            ),
            const AppDivider(),
          ],
          Flexible(
            fit: widget.embedded ? FlexFit.tight : FlexFit.loose,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                _buildLabelField(),
                // The type decides how the value is entered, so it comes
                // first.
                _buildTypeField(),
                if (_isFileType) const VaultFileRow() else _buildValueField(),
                _hiddenToggle(),
                if (!_isFileType && Stores.keys.isAvailable) _sealedToggle(),
                // A file stays with its owner for now.
                if (!_isFileType)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      0,
                    ),
                    child: VisibleToField(
                      value: _visibility,
                      groups: _groups,
                      canPublish: Stores.settings.canPublishVault,
                    ),
                  ),

                AppFormAdvanced(
                  summary: 'Key and API preview',
                  // A duplicate's key clashes until it is changed.
                  initiallyOpen: _store.recordKeyWarning != null,
                  children: [_buildKeyField(), _apiPreview()],
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
                AppButton(
                  label: 'Cancel',
                  onTap: _store.isSubmittingRecord
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: AppButtonStyle.accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: isDup ? AppIcons.copy : AppIcons.plus,
                    label: isDup ? 'Duplicate record' : 'Create record',
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

  Widget _buildLabelField() => AppFormField(
    label: 'Label',
    child: AppTextField(
      controller: _store.recordLabel,
      hint: 'IBAN',
      onSubmitted: (_) => _submit(),
    ),
  );

  Widget _buildKeyField() => AppFormField(
    label: 'Key',
    explanation: 'Identifier for templates, requests and scripts',
    error: _store.recordKeyWarning,
    note: _store.recordKey.text.trim().isEmpty
        ? 'Defaults to $_effectiveKey when empty.'
        : null,
    action: _store.recordSuggestedKey == null
        ? null
        : AppButton(
            icon: AppIcons.stars,
            label: 'Use suggested: ${_store.recordSuggestedKey}',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              _store.recordKey.text = _store.recordSuggestedKey!;
              _validateKey(_store.recordKey.text);
            },
          ),
    child: AppTextField(
      controller: _store.recordKey,
      hint: _effectiveKey,
      mono: true,
      inputFormatters: [KeyInputFormatter()],
      onChanged: _validateKey,
    ),
  );

  /// The request this form would send, for anyone scripting the same thing.
  Widget _apiPreview() => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      0,
      AppSpacing.xl,
      AppSpacing.sm,
    ),
    child: _isFileType
        ? const Text(
            'File records upload as multipart/form-data: the same fields as '
            'form parts, plus the file itself as a "file" part.',
          ).muted.small
        : _store.recordSealed
        ? const Text(
            'The value is encrypted on this device before upload. The request '
            'carries only encrypted data.',
          ).muted.small
        : ApiPreview(
            spec: VaultStore.createRecordSpec(
              key: _effectiveKey,
              value: _store.recordValue.text,
              label: _store.recordLabel.text.trim(),
              type: _store.recordType,
              format: _store.recordFormat,
              user: widget.authStore.userId,
              workspace: widget.authStore.activeWorkspace ?? '',
              audienceKind: _audience.kind,
              audienceGroups: _audience.groups,
            ),
          ),
  );

  /// Desktop drops land anywhere on the drawer; dropping a file flips the
  /// draft to the file type, because the gesture already said so.
  Widget _wrapDropTarget(Widget child) => vaultDropTarget(
    child: child,
    // The gesture already said this is a file.
    onStaged: () async {
      if (mounted && !_isFileType) _store.setRecordType('file');
    },
  );

  /// Below the value row: whether the vault masks the value.
  Widget _hiddenToggle() => RecordHiddenToggle(
    isFile: _isFileType,
    hidden: _store.recordFormat == 'hidden',
    onChanged: (on) => _store.setRecordFormat(on ? 'hidden' : 'default'),
  );

  Widget _sealedToggle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RecordSealedToggle(
        sealed: _store.recordSealed,
        onChanged: (on) async {
          if (!on) {
            _store.setRecordSealed(false);
            return;
          }
          final ready = await ensureSealingReady(
            context,
            widget.authStore.activeWorkspace ?? '',
          );
          if (ready) _store.setRecordSealed(true);
        },
      ),
      if (_store.recordSealed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: SealedReadabilityNote(
            workspace: widget.authStore.activeWorkspace ?? '',
          ),
        ),
    ],
  );

  Widget _buildValueField() => AppFormField(
    label: 'Value',
    error: _store.recordTypeWarning,
    child: RecordValueField(
      type: _store.recordType,
      controller: _store.recordValue,
      onChanged: _validateAndDetectType,
    ),
  );

  Widget _buildTypeField() => AppFormField(
    label: 'Type',
    child: RecordTypeChoice(
      selected: _store.recordType,
      detected: _store.recordDetectedType,
      includeFile: true,
      onPicked: _pickType,
    ),
  );

  void _pickType(String type) {
    final from = _store.recordType;
    _store.setRecordType(type);
    _store.recordValue.text = recordValueForType(
      type,
      _store.recordValue.text,
      from: from,
    );
    _validateAndDetectType(_store.recordValue.text);
  }
}
