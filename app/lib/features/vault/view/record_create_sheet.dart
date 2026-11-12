import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
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
    panelWidth: vaultComposerWidth,
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

  final Map<String, TextEditingValue> _typeDrafts = {};
  final Local<bool> _preparingEncryption = Local(false);

  ({String kind, List<String> groups}) get _audience => chosenAudience(
    _visibility,
    _groups,
    canPublish: Stores.settings.canPublishVault && !_isFileType,
  );

  @override
  void initState() {
    super.initState();
    _store.clearError();
    unawaited(Stores.keys.ensureLoaded());
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
      if (widget.initialType == 'boolean') _store.recordValue.text = 'false';
    }
    if (_store.recordType == 'boolean' && _store.recordValue.text.isEmpty) {
      _store.recordValue.text = 'false';
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

  /// The key saved under: the one typed under Developer options, or one
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
    if (_preparingEncryption.value) return false;
    if (!_isFileType &&
        Stores.settings.canPublishVault &&
        _visibility.value == 'groups' &&
        _groups.value.isEmpty) {
      return false;
    }
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
    if (_store.isSubmittingRecord || !_canSubmit()) return;
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
            VaultComposerHeader(
              title: isDup ? 'Duplicate record' : 'New record',
              subtitle: isDup
                  ? 'Creates a copy of this record under a new key.'
                  : 'Your information, ready when you need it.',
              onClose: _store.isSubmittingRecord
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            const AppDivider(),
          ],
          Flexible(
            fit: widget.embedded ? FlexFit.tight : FlexFit.loose,
            child: ExcludeFocus(
              excluding: _store.isSubmittingRecord,
              child: IgnorePointer(
                ignoring: _store.isSubmittingRecord,
                child: RecordComposerLayout(
                  selectedType: _store.recordType,
                  onTypePicked: _pickType,
                  enabled: !_store.isSubmittingRecord,
                  children: [
                    _buildLabelField(),
                    if (_isFileType)
                      RecordComposerField(
                        label: 'File',
                        trailing: _maskToggle(),
                        child: const VaultFileRow(
                          inset: false,
                          showLabel: false,
                        ),
                      )
                    else
                      _buildValueField(),
                    _buildSettings(),
                  ],
                ),
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
            child: LayoutBuilder(
              builder: (context, box) {
                return Observer(
                  builder: (_) {
                    final canSubmit = _canSubmit();
                    final summary = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.lock, size: 16),
                        AppSpacing.gapXs,
                        Flexible(
                          child: Text(
                            '$_accessSummary · '
                            '${_store.recordFormat == 'hidden' ? 'Masked' : 'Visible'}'
                            '${!_isFileType && _store.recordSealed ? ' · E2E' : ''}',
                          ).small.muted,
                        ),
                      ],
                    );
                    final actions = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppButton(
                          label: 'Cancel',
                          onTap: _store.isSubmittingRecord
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: AppButtonStyle.ghost,
                        ),
                        AppSpacing.gapSm,
                        Flexible(
                          child: AppButton(
                            trailingIcon: isDup
                                ? AppIcons.copy
                                : AppIcons.arrowRight,
                            label: isDup ? 'Duplicate record' : 'Save record',
                            busy: _store.isSubmittingRecord,
                            onTap: canSubmit ? _submit : null,
                          ),
                        ),
                      ],
                    );
                    final scale =
                        MediaQuery.textScalerOf(context)
                            .scale(AppTextSize.body) /
                        AppTextSize.body;
                    if (box.maxWidth < 520 * scale) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          AppSpacing.gapSm,
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: summary),
                        AppSpacing.gapMd,
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
    return _wrapDropTarget(sheet);
  }

  Widget _buildLabelField() => RecordComposerField(
    label: 'Label',
    child: AppTextField(
      controller: _store.recordLabel,
      hint: 'e.g. Account IBAN',
      onSubmitted: (_) => _submit(),
    ),
  );

  Widget _buildKeyField() => AppFormField(
    label: 'Record key',
    inset: false,
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
    padding: EdgeInsets.zero,
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
  Widget _wrapDropTarget(Widget child) {
    if (_store.isSubmittingRecord) return child;
    return vaultDropTarget(
      child: child,
      onStaged: () async {
        if (mounted && !_isFileType) _pickType('file');
      },
    );
  }

  String get _accessSummary {
    if (!_isFileType &&
        Stores.settings.canPublishVault &&
        _visibility.value == 'groups' &&
        _groups.value.isEmpty) {
      return 'Choose groups';
    }
    return switch (_audience.kind) {
      'workspace' => 'Workspace',
      'groups' => 'Selected groups',
      _ => 'Private',
    };
  }

  Widget _maskToggle() => MergeSemantics(
    child: Tooltip(
      message: _isFileType
          ? 'Mask the file name until revealed in the vault.'
          : 'Mask the saved value until revealed in the vault.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_isFileType ? 'Mask name' : 'Mask value').small.muted,
          AppSpacing.gapXs,
          AppSwitch(
            value: _store.recordFormat == 'hidden',
            showCheckIcon: true,
            onChanged: (on) =>
                _store.setRecordFormat(on ? 'hidden' : 'default'),
          ),
        ],
      ),
    ),
  );

  Widget _buildSettings() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppRadius.allMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RecordComposerDisclosure(
            key: const ValueKey('record-access'),
            title: 'Access',
            summary: _accessSummary == 'Private'
                ? 'Private · only you'
                : _accessSummary,
            icon: AppIcons.group,
            child: _buildAccessOptions(),
          ),
          if (!_isFileType &&
              (Stores.keys.isAvailable || _store.recordSealed)) ...[
            const AppDivider(),
            RecordComposerDisclosure(
              key: const ValueKey('record-encryption'),
              title: 'Encryption',
              summary: _store.recordSealed
                  ? 'End-to-end · account devices only'
                  : 'Standard · end-to-end off',
              icon: AppIcons.shieldCheck,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCheckRow(
                    label: 'End-to-end encryption',
                    subtitle: 'Encrypt the value on this device before upload.',
                    badge: const AppBadge(label: 'Alpha'),
                    value: _store.recordSealed,
                    onChanged: _preparingEncryption.value
                        ? null
                        : _setEncrypted,
                  ),
                  AppSpacing.gapSm,
                  const Text(
                    'Only this account’s devices can read encrypted values. '
                    'Other workspace accounts cannot decrypt them yet.',
                  ).small.muted,
                  if (_preparingEncryption.value) ...[
                    AppSpacing.gapSm,
                    const Text('Preparing encryption…').small.muted,
                  ],
                  if (_store.recordSealed) ...[
                    AppSpacing.gapSm,
                    SealedReadabilityNote(
                      workspace: widget.authStore.activeWorkspace ?? '',
                    ),
                  ],
                ],
              ),
            ),
          ],
          const AppDivider(),
          RecordComposerDisclosure(
            key: const ValueKey('record-developer-options'),
            title: 'Developer options',
            summary: 'Key & API preview',
            icon: AppIcons.code,
            initiallyOpen: _store.recordKeyWarning != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_buildKeyField(), AppSpacing.gapLg, _apiPreview()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessOptions() {
    if (_isFileType) {
      return const Text('Files are private to your account.').small.muted;
    }
    if (!Stores.settings.canPublishVault) {
      return const Text(
        'Private to you. Publishing to the workspace vault requires permission from an admin.',
      ).small.muted;
    }
    final offerGroups = Stores.settings.groups.isNotEmpty;
    final selected = _visibility.value == 'groups' && !offerGroups
        ? 'private'
        : _visibility.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null) _visibility.value = value;
          },
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'private',
                title: const Text('Private').small,
                subtitle: const Text('Only you can see this record.')
                    .small
                    .muted,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                value: 'workspace',
                title: const Text('Workspace').small,
                subtitle: const Text('Members of this workspace.').small.muted,
                contentPadding: EdgeInsets.zero,
              ),
              if (offerGroups)
                RadioListTile<String>(
                  value: 'groups',
                  title: const Text('Specific groups').small,
                  subtitle: const Text('Only the groups you select.')
                      .small
                      .muted,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (selected == 'groups') ...[
          for (final group in Stores.settings.groups)
            AppCheckRow(
              label: group.name,
              value: _groups.value.contains(group.id),
              onChanged: (on) => _groups.value = on
                  ? {..._groups.value, group.id}
                  : ({..._groups.value}..remove(group.id)),
            ),
          if (_groups.value.isEmpty)
            const Text('Select at least one group to continue.').small.muted,
        ],
      ],
    );
  }

  Future<void> _setEncrypted(bool on) async {
    if (!on) {
      _store.setRecordSealed(false);
      return;
    }
    _preparingEncryption.value = true;
    try {
      final ready = await ensureSealingReady(
        context,
        widget.authStore.activeWorkspace ?? '',
      );
      if (mounted && ready) _store.setRecordSealed(true);
    } finally {
      if (mounted) _preparingEncryption.value = false;
    }
  }

  Widget _buildValueField() => RecordComposerField(
    label: 'Value',
    trailing: _maskToggle(),
    error: _store.recordTypeWarning,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ValueKey(_store.recordType),
          child: _store.recordType == 'text'
              ? AppTextField(
                  controller: _store.recordValue,
                  hint: 'Enter the value…',
                  minLines: 3,
                  maxLines: null,
                  onChanged: _validateAndDetectType,
                )
              : _store.recordType == 'boolean'
              ? RadioGroup<String>(
                  groupValue: _store.recordValue.text,
                  onChanged: (value) {
                    if (value == null) return;
                    _store.recordValue.text = value;
                    _validateAndDetectType(value);
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'true',
                        title: const Text('Yes'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        value: 'false',
                        title: const Text('No'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                )
              : RecordValueField(
                  type: _store.recordType,
                  controller: _store.recordValue,
                  onChanged: _validateAndDetectType,
                ),
        ),
        if (_store.recordDetectedType != null) ...[
          AppSpacing.gapSm,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: 'Use ${RecordTypeUtils.label(_store.recordDetectedType!)}',
              icon: AppIcons.stars,
              style: AppButtonStyle.outline,
              size: AppButtonSize.small,
              onTap: () =>
                  _pickType(_store.recordDetectedType!, useCurrentValue: true),
            ),
          ),
        ],
      ],
    ),
  );

  void _pickType(String type, {bool useCurrentValue = false}) {
    final from = _store.recordType;
    if (from == type) return;
    final current = _store.recordValue.value;
    _typeDrafts[from] = current;
    _store.setRecordType(type);
    _store.recordValue.value = useCurrentValue
        ? TextEditingValue(
            text: recordValueForType(type, current.text, from: from),
          )
        : _typeDrafts[type] ??
              TextEditingValue(text: type == 'boolean' ? 'false' : '');
    _validateAndDetectType(_store.recordValue.text);
  }
}
