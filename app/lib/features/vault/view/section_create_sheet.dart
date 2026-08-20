import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';

/// Opens the section create / duplicate drawer.
void openSectionCreateSheet({
  required BuildContext context,
  required VaultStore store,
  required AuthStore authStore,
  Section? initialSection,
}) {
  store.clearError();
  store.startSectionDraft(from: initialSection);
  showAppSheet(
    context: context,
    builder: (drawerContext) => _SectionCreateDrawer(
      parentContext: context,
      store: store,
      authStore: authStore,
      initialSection: initialSection,
    ),
  );
}

/// Opens the rename drawer for an existing section.
void openSectionRenameSheet({
  required BuildContext context,
  required VaultStore store,
  required Section section,
}) {
  store.clearError();
  store.startSectionRename(section);
  showAppSheet(
    context: context,
    builder: (drawerContext) => _SectionRenameDrawer(
      parentContext: context,
      store: store,
      section: section,
    ),
  );
}

class _SectionCreateDrawer extends StatefulWidget {
  final BuildContext parentContext;
  final VaultStore store;
  final AuthStore authStore;
  final Section? initialSection;

  const _SectionCreateDrawer({
    required this.parentContext,
    required this.store,
    required this.authStore,
    required this.initialSection,
  });

  @override
  State<_SectionCreateDrawer> createState() => _SectionCreateDrawerState();
}

class _SectionCreateDrawerState extends State<_SectionCreateDrawer> {
  VaultStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    // A duplicate opens with `<key>_1` already filled, so the collision check
    // has to run before the user touches anything.
    if (_store.sectionKey.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _validateKey(_store.sectionKey.text),
      );
    }
  }

  void _validateKey(String input) {
    if (input.isEmpty || !_store.sections.any((s) => s.key == input)) {
      _store.setSectionKeyCheck();
      return;
    }
    _store.setSectionKeyCheck(
      warning: 'This key is already taken.',
      suggestion: _generateAlternativeKey(input),
    );
  }

  String _generateAlternativeKey(String baseKey) {
    var sanitized = baseKey.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (sanitized.isEmpty) sanitized = 'section';
    var counter = 1;
    while (true) {
      final candidate = '${sanitized}_$counter';
      if (!_store.sections.any((s) => s.key == candidate)) return candidate;
      counter++;
    }
  }

  bool _canSubmit() =>
      _store.sectionName.text.trim().isNotEmpty &&
      _store.sectionKey.text.trim().isNotEmpty &&
      _store.sectionKeyWarning == null;

  Future<void> _submit() async {
    if (!_canSubmit()) return;
    _store.setSubmittingSection(true);
    _store.setSectionError(null);

    final isDup = widget.initialSection != null;
    final ok = await _store.createSection(
      key: _store.sectionKey.text.trim(),
      name: _store.sectionName.text.trim(),
      recordIds: widget.initialSection?.records ?? const [],
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
    );

    if (!mounted) return;
    if (!ok) {
      _store.setSubmittingSection(false);
      if (widget.parentContext.mounted) {
        AppToast.error(
          widget.parentContext,
          'Could not create section',
          subtitle: _store.errorMessage,
        );
      }
      return;
    }

    Navigator.of(context).pop();
    if (widget.parentContext.mounted) {
      AppToast.success(
        widget.parentContext,
        isDup ? 'Section duplicated' : 'Section created',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final isDup = widget.initialSection != null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            title: isDup ? 'Duplicate section' : 'New section',
            description: isDup
                ? 'Duplicate this section with a new unique key.'
                : 'Group records together within a section.',
          ),
          const AppDivider(),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                _buildNameRow(),
                _buildKeyRow(),

                const AppFormSectionHeader('Developer'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: ApiPreview(
                    spec: VaultStore.createSectionSpec(
                      key: _store.sectionKey.text.trim(),
                      name: _store.sectionName.text.trim(),
                      records: widget.initialSection?.records ?? const [],
                      user: widget.authStore.userId,
                      workspace: widget.authStore.activeWorkspace ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AppDivider(),

          _SheetFooter(
            busy: _store.isSubmittingSection,
            confirmLabel: isDup ? 'Duplicate Section' : 'Create Section',
            onConfirm: _canSubmit() ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNameRow() {
    final name = _store.sectionName.text.trim();
    return AppFormRow(
      icon: AppIcons.fileText,
      label: 'Name',
      valueText: name.isEmpty ? 'Required' : name,
      isPlaceholder: name.isEmpty,
      isError: name.isEmpty,
      onTap: () => showAppEditSheet(
        context: context,
        title: 'Name',
        description: 'A friendly display name for this section.',
        controller: _store.sectionName,
        hint: 'My Section',
      ),
    );
  }

  Widget _buildKeyRow() {
    final key = _store.sectionKey.text.trim();
    return AppFormRow(
      icon: AppIcons.hash,
      label: 'Key',
      valueText: key.isEmpty ? 'Required' : (_store.sectionKeyWarning ?? key),
      isPlaceholder: key.isEmpty,
      isError: key.isEmpty || _store.sectionKeyWarning != null,
      onTap: _editKey,
    );
  }

  Future<void> _editKey() async {
    await showAppSheet(
      context: context,
      builder: (sheetCtx) => Observer(
        builder: (ctx) => Padding(
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
              const Text('Key').header,
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'A stable identifier used for sharing and templates.',
              ).muted.small,
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _store.sectionKey,
                hint: 'section_key',
                autofocus: true,
                inputFormatters: [KeyInputFormatter()],
                onChanged: _validateKey,
              ),
              if (_store.sectionKeyWarning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppErrorText(_store.sectionKeyWarning!),
              ],
              if (_store.sectionSuggestedKey != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Use suggested: ${_store.sectionSuggestedKey}',
                    style: AppButtonStyle.accent,
                    size: AppButtonSize.small,
                    onTap: () {
                      _store.sectionKey.text = _store.sectionSuggestedKey!;
                      _validateKey(_store.sectionKey.text);
                    },
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Done',
                onTap:
                    (_store.sectionKey.text.trim().isNotEmpty &&
                        _store.sectionKeyWarning == null)
                    ? () => Navigator.of(sheetCtx).pop()
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionRenameDrawer extends StatefulWidget {
  final BuildContext parentContext;
  final VaultStore store;
  final Section section;

  const _SectionRenameDrawer({
    required this.parentContext,
    required this.store,
    required this.section,
  });

  @override
  State<_SectionRenameDrawer> createState() => _SectionRenameDrawerState();
}

class _SectionRenameDrawerState extends State<_SectionRenameDrawer> {
  VaultStore get _store => widget.store;

  Future<void> _submit() async {
    final name = _store.renameSectionName.text.trim();
    if (name.isEmpty) return;
    _store.setRenamingSection(true);
    _store.setRenameSectionError(null);

    final ok = await _store.updateSection(widget.section.id, {'name': name});

    if (!mounted) return;
    if (!ok) {
      _store.setRenamingSection(false);
      if (widget.parentContext.mounted) {
        AppToast.error(
          widget.parentContext,
          'Could not rename section',
          subtitle: _store.errorMessage,
        );
      }
      return;
    }

    Navigator.of(context).pop();
    if (widget.parentContext.mounted) {
      AppToast.success(widget.parentContext, 'Section renamed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final name = _store.renameSectionName.text.trim();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(
            title: 'Rename section',
            description: 'Change the display name of this section.',
          ),
          const AppDivider(),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                AppFormRow(
                  icon: AppIcons.fileText,
                  label: 'Name',
                  valueText: name.isEmpty ? 'Required' : name,
                  isPlaceholder: name.isEmpty,
                  isError: name.isEmpty,
                  onTap: () => showAppEditSheet(
                    context: context,
                    title: 'Name',
                    description: 'A friendly display name for this section.',
                    controller: _store.renameSectionName,
                    hint: 'My Section',
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
                    spec: VaultStore.updateSectionSpec(widget.section.id, {
                      'name': name,
                    }),
                  ),
                ),
              ],
            ),
          ),
          const AppDivider(),

          _SheetFooter(
            busy: _store.isRenamingSection,
            confirmLabel: 'Save',
            onConfirm: name.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// The title + description block every vault drawer opens with.
class _SheetHeader extends StatelessWidget {
  final String title;
  final String description;

  const _SheetHeader({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title).header,
          const SizedBox(height: AppSpacing.xxs),
          Text(description).muted.small,
        ],
      ),
    );
  }
}

/// Cancel + confirm, the pair every vault drawer closes with.
class _SheetFooter extends StatelessWidget {
  final bool busy;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  const _SheetFooter({
    required this.busy,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              style: AppButtonStyle.accent,
              onTap: busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppButton(label: confirmLabel, busy: busy, onTap: onConfirm),
          ),
        ],
      ),
    );
  }
}
