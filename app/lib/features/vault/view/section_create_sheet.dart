import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/section.dart';
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
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/view/section_views.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_editor.dart';

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

/// The section form, the Section tab of the vault's create drawer
/// (`openVaultCreateSheet`), which is the only way to it: a new section, or
/// with [duplicateOf] a copy of one under a new key.
Widget sectionCreateForm({
  required BuildContext parentContext,
  Section? duplicateOf,
}) => _SectionCreateDrawer(
  parentContext: parentContext,
  store: Stores.vault,
  authStore: Stores.auth,
  initialSection: duplicateOf,
);

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

  /// Who sees the new section, from the workspace's default (VISIBILITY.md).
  final Local<String> _visibility = Local(
    Stores.settings.defaultAudienceFor('sections'),
  );
  final Local<Set<String>> _groups = Local(const {});

  /// How the new section shows as a card; a duplicate starts from the
  /// original's.
  late final Local<Map<String, dynamic>?> _view = Local(
    widget.initialSection?.view,
  );
  ({String kind, List<String> groups}) get _audience => chosenAudience(
    _visibility,
    _groups,
    canPublish: Stores.settings.canPublishVault,
  );

  @override
  void initState() {
    super.initState();
    // The drawer has no opener to start the draft, and the tab is built
    // whether or not it is the one on screen.
    _store.clearError();
    _store.startSectionDraft(from: widget.initialSection);
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
      warning: 'This key is already in use.',
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
      audienceKind: _audience.kind,
      audienceGroups: _audience.groups,
      view: _view.value,
    );

    if (!mounted) return;
    if (!ok) {
      _store.setSubmittingSection(false);
      if (widget.parentContext.mounted) {
        AppToast.error(
          widget.parentContext,
          'The section could not be created.',
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
      constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
      child: Column(
        // The form fills its tab so the footer sits on the drawer's bottom
        // edge rather than floating above a gap.
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: FlexFit.tight,
            child: AppComposerSections(
              enabled: !_store.isSubmittingSection,
              sections: [
                AppComposerSection(
                  title: 'Section',
                  icon: AppIcons.folder,
                  children: [_buildNameRow(), _buildKeyRow()],
                ),
                AppComposerSection(
                  title: 'Access',
                  icon: AppIcons.group,
                  children: [
                    AppComposerVisibility(
                      field: VisibleToField(
                        value: _visibility,
                        groups: _groups,
                        showLabel: false,
                      ),
                    ),
                  ],
                ),
                AppComposerSection(
                  title: 'View',
                  icon: AppIcons.dashboard,
                  children: [
                    AppComposerCard(
                      title: 'Section view',
                      description:
                          'Optional. How the section shows as one card; '
                          'without one, it shows as a list of records.',
                      child: ViewCodeEditor(
                        initial: widget.initialSection?.view,
                        data: ViewData(
                          section: [
                            for (final r in Stores.vault.records)
                              if (widget.initialSection?.records.contains(
                                    r.id,
                                  ) ??
                                  false)
                                r,
                          ],
                          vault: Stores.vault.records,
                        ),
                        examples: viewExamples(Stores.templates.templates),
                        onChanged: (view) => _view.value = view,
                      ),
                    ),
                  ],
                ),
                AppComposerSection(
                  title: 'Developer',
                  icon: AppIcons.code,
                  children: [
                    AppComposerApiPreview(
                      preview: ApiPreviewSection(
                        embedded: true,
                        spec: VaultStore.createSectionSpec(
                          key: _store.sectionKey.text.trim(),
                          name: _store.sectionName.text.trim(),
                          records: widget.initialSection?.records ?? const [],
                          user: widget.authStore.userId,
                          workspace: widget.authStore.activeWorkspace ?? '',
                          audienceKind: _audience.kind,
                          audienceGroups: _audience.groups,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const AppDivider(),
          _SheetFooter(
            busy: _store.isSubmittingSection,
            confirmLabel: isDup ? 'Duplicate section' : 'Create section',
            confirmIcon: isDup ? AppIcons.copy : AppIcons.plus,
            onConfirm: _canSubmit() ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNameRow() => AppComposerField(
    label: 'Name',
    explanation: 'How this section is named in your vault.',
    missing: _store.sectionName.text.trim().isEmpty,
    child: AppTextField(controller: _store.sectionName, hint: 'My Section'),
  );

  Widget _buildKeyRow() => AppComposerField(
    label: 'Key',
    explanation: 'Identifier for links and templates.',
    missing: _store.sectionKey.text.trim().isEmpty,
    error: _store.sectionKeyWarning,
    action: _store.sectionSuggestedKey == null
        ? null
        : AppButton(
            icon: AppIcons.stars,
            label: 'Use suggested: ${_store.sectionSuggestedKey}',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              _store.sectionKey.text = _store.sectionSuggestedKey!;
              _validateKey(_store.sectionKey.text);
            },
          ),
    child: AppTextField(
      controller: _store.sectionKey,
      hint: 'section_key',
      mono: true,
      inputFormatters: [KeyInputFormatter()],
      onChanged: _validateKey,
    ),
  );
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
          'The section could not be renamed.',
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
      constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(
            title: 'Rename section',
            description: 'A new display name for this section.',
          ),
          const AppDivider(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                const AppFormSectionHeader('Details'),
                AppComposerField(
                  label: 'Name',
                  explanation: 'Display name for this section',
                  missing: name.isEmpty,
                  child: AppTextField(
                    controller: _store.renameSectionName,
                    hint: 'My Section',
                    autofocus: true,
                    onSubmitted: (_) {
                      if (name.isNotEmpty) _submit();
                    },
                  ),
                ),
                ApiPreviewSection(
                  spec: VaultStore.updateSectionSpec(widget.section.id, {
                    'name': name,
                  }),
                ),
              ],
            ),
          ),
          const AppDivider(),
          _SheetFooter(
            busy: _store.isRenamingSection,
            confirmLabel: 'Save',
            confirmIcon: AppIcons.check,
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
  final IconData confirmIcon;
  final VoidCallback? onConfirm;

  const _SheetFooter({
    required this.busy,
    required this.confirmLabel,
    required this.confirmIcon,
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
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.accent,
            onTap: busy ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppButton(
              icon: confirmIcon,
              label: confirmLabel,
              busy: busy,
              onTap: onConfirm,
            ),
          ),
        ],
      ),
    );
  }
}
