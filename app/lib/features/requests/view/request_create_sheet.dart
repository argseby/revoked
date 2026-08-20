import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';

/// Opens the request-create bottom sheet.
///
/// Single drawer: every setting is a row showing its current value. Tapping a
/// row opens a focused sub-sheet to edit it (text, password, picker, date);
/// boolean settings are toggled inline. Title, slug and identity are required
/// and gate the Create button — everything else is optional.
void openRequestCreateSheet({
  required BuildContext context,
  required RequestsStore store,
  required AuthStore authStore,
  DataRequest? editRequest,
}) {
  showAppSheet(
    context: context,
    builder: (_) => _RequestCreateForm(
      store: store,
      authStore: authStore,
      editRequest: editRequest,
    ),
  );
}

/// Inset for a row in a "choose one" sheet, so every picker lines up with
/// the sheet's own padding.
const _pickerRowPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.xl,
  vertical: AppSpacing.md,
);

class _RequestCreateForm extends StatefulWidget {
  final RequestsStore store;
  final AuthStore authStore;
  final DataRequest? editRequest;

  const _RequestCreateForm({
    required this.store,
    required this.authStore,
    this.editRequest,
  });

  @override
  State<_RequestCreateForm> createState() => _RequestCreateFormState();
}

class _RequestCreateFormState extends State<_RequestCreateForm> {
  RequestsStore get _store => Stores.requests;

  @override
  void initState() {
    super.initState();
    final edit = widget.editRequest;
    if (edit != null) {
      _store.startRequestDraft(
        label: edit.label,
        slug: edit.slug,
        identifier: edit.identifier,
        callback: edit.callbackUrl,
        maxResponses: edit.maxResponses > 0 ? edit.maxResponses.toString() : '',
        identityId: edit.identity.isEmpty ? null : edit.identity,
        templateId: edit.templateId.isEmpty ? null : edit.templateId,
        requireHandshake: edit.requireHandshake,
        identityScope: edit.identityScope.isEmpty ? 'any' : edit.identityScope,
        allowExtraFields: edit.allowExtraFields,
        expiresAt: edit.expiresAt != null
            ? DateTime.tryParse(edit.expiresAt!)
            : null,
      );
    } else {
      _store.startRequestDraft(slug: _randomSlug(6));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.identities.loadIdentities();
      Stores.templates.loadTemplates(widget.authStore.activeWorkspace ?? '');
    });
  }

  String _randomSlug(int length) {
    final r = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _validateSlug(String input) async {
    if (input.isEmpty) {
      _store.setDraftSlugCheck();
      return;
    }
    if (input.length < 6) {
      _store.setDraftSlugCheck(warning: 'Slug must be at least 6 characters.');
      return;
    }
    _store.setCheckingSlug(true);
    final taken = await widget.store.isSlugTaken(input);
    if (!mounted) return;
    if (taken && widget.editRequest?.slug != input) {
      final alt = await widget.store.generateAlternativeSlug(input);
      if (!mounted) return;
      _store.setDraftSlugCheck(
        warning: 'This slug is already taken.',
        suggestion: alt,
      );
      _store.setCheckingSlug(false);
    } else {
      _store.setDraftSlugCheck();
      _store.setCheckingSlug(false);
    }
  }

  bool _canSubmit() {
    if (_store.draftLabel.text.trim().isEmpty) return false;
    final slug = _store.draftSlug.text.trim();
    if (slug.length < 6) return false;
    if (_store.draftSlugWarning != null) return false;
    if (_store.isCheckingSlug) return false;
    if (_store.draftIdentityId == null) return false;
    return true;
  }

  Future<bool> _submit() async {
    final mr = int.tryParse(_store.draftMaxResponses.text.trim());

    final edit = widget.editRequest;
    if (edit != null) {
      final body = <String, dynamic>{
        'label': _store.draftLabel.text.trim(),
        'slug': _store.draftSlug.text.trim(),
        'identity': _store.draftIdentityId,
        'template': _store.draftTemplateId ?? '',
        'maxResponses': mr ?? 0,
        'identifier': _store.draftIdentifier.text.trim(),
        'callbackUrl': _store.draftCallback.text.trim(),
        'requireHandshake': _store.draftRequireHandshake,
        'identityScope': _store.draftRequireHandshake
            ? _store.draftIdentityScope
            : 'any',
        'allowExtraFields': _store.draftAllowExtraFields,
        'expiresAt': _store.draftExpiresAt?.toUtc().toIso8601String() ?? '',
      };
      if (_store.draftPassword.text.trim().isNotEmpty) {
        body['password'] = _store.draftPassword.text.trim();
      }
      final ok = await widget.store.updateRequest(edit.id, body);
      if (!mounted) return false;
      if (ok) {
        AppToast.success(context, 'Request updated');
        return true;
      }
      AppToast.error(
        context,
        'Could not update request',
        subtitle: widget.store.errorMessage,
      );
      return false;
    }

    final ok = await widget.store.createRequest(
      slug: _store.draftSlug.text.trim(),
      label: _store.draftLabel.text.trim(),
      identityId: _store.draftIdentityId!,
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      templateId: _store.draftTemplateId,
      password: _store.draftPassword.text.trim().isEmpty
          ? null
          : _store.draftPassword.text.trim(),
      expiresAt: _store.draftExpiresAt,
      maxResponses: mr,
      identifier: _store.draftIdentifier.text.trim().isEmpty
          ? null
          : _store.draftIdentifier.text.trim(),
      callbackUrl: _store.draftCallback.text.trim().isEmpty
          ? null
          : _store.draftCallback.text.trim(),
      requireHandshake: _store.draftRequireHandshake,
      identityScope: _store.draftRequireHandshake
          ? _store.draftIdentityScope
          : 'any',
      allowExtraFields: _store.draftAllowExtraFields,
    );
    if (!mounted) return false;
    if (ok) {
      final url = DeepLinks.request(
        _store.draftSlug.text.trim(),
        origin: Stores.api.originAuthority,
      );
      Clipboard.setData(ClipboardData(text: url));
      AppToast.success(
        context,
        'Request created',
        subtitle: 'Link copied to clipboard',
      );
      return true;
    }
    AppToast.error(
      context,
      'Could not create request',
      subtitle: widget.store.errorMessage,
    );
    return false;
  }

  Future<void> _onCreate() async {
    _store.setSubmittingRequest(true);
    final ok = await _submit();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _store.setSubmittingRequest(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                Text(
                  widget.editRequest != null
                      ? 'Edit request'
                      : 'New data request',
                ).header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'A public form anyone with the link can submit. '
                  'You receive each submission.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          // Body — every setting visible at once.
          Flexible(
            child: Observer(
              builder: (_) {
                _ensureIdentityDefault();
                return ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  shrinkWrap: true,
                  children: [
                    const AppFormSectionHeader('Basics'),
                    _buildTitleRow(),
                    _buildSlugRow(),
                    _buildIdentityRow(),

                    const AppFormSectionHeader('Template'),
                    _buildTemplateRow(),
                    AppFormToggleRow(
                      icon: AppIcons.plus,
                      label: 'Allow extra fields',
                      subtitle:
                          'Responders can add ad-hoc fields beyond the template.',
                      value: _store.draftAllowExtraFields,
                      onChanged: _store.setDraftAllowExtraFields,
                    ),

                    const AppFormSectionHeader('Who can respond'),
                    _buildAccessSummary(),
                    AppFormToggleRow(
                      icon: AppIcons.shieldCheck,
                      label: 'Require a verified identity',
                      subtitle:
                          'Responder must be signed in with a cryptographic identity.',
                      value: _store.draftRequireHandshake,
                      onChanged: _store.setDraftHandshake,
                    ),
                    if (_store.draftRequireHandshake) _buildIdentityScopeRow(),
                    _buildIdentifierRow(),
                    _buildPasswordRow(),

                    const AppFormSectionHeader('Limits & callback'),
                    _buildMaxResponsesRow(),
                    _buildExpiryRow(),
                    _buildCallbackRow(),

                    const AppFormSectionHeader('Developer'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.sm,
                      ),
                      child: ApiPreview(
                        spec: _buildSpec(),
                        title:
                            'API request · ${widget.editRequest != null ? 'update' : 'create'}',
                      ),
                    ),
                  ],
                );
              },
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
                    onTap: _store.isSubmittingRequest
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: AppButtonStyle.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: widget.editRequest != null
                        ? 'Save changes'
                        : 'Create Request',
                    busy: _store.isSubmittingRequest,
                    onTap: _canSubmit() ? _onCreate : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The exact API request the current form would issue — drives the live
  /// developer preview (create vs update), mirroring [_submit].
  ApiRequestSpec _buildSpec() {
    final mr = int.tryParse(_store.draftMaxResponses.text.trim());
    final edit = widget.editRequest;
    if (edit != null) {
      final body = <String, dynamic>{
        'label': _store.draftLabel.text.trim(),
        'slug': _store.draftSlug.text.trim(),
        'identity': _store.draftIdentityId,
        'template': _store.draftTemplateId ?? '',
        'maxResponses': mr ?? 0,
        'identifier': _store.draftIdentifier.text.trim(),
        'callbackUrl': _store.draftCallback.text.trim(),
        'requireHandshake': _store.draftRequireHandshake,
        'identityScope': _store.draftRequireHandshake
            ? _store.draftIdentityScope
            : 'any',
        'allowExtraFields': _store.draftAllowExtraFields,
        'expiresAt': _store.draftExpiresAt?.toUtc().toIso8601String() ?? '',
        if (_store.draftPassword.text.trim().isNotEmpty)
          'password': _store.draftPassword.text.trim(),
      };
      return RequestsStore.updateRequestSpec(edit.id, body);
    }
    return RequestsStore.createRequestSpec(
      slug: _store.draftSlug.text.trim(),
      label: _store.draftLabel.text.trim(),
      identityId: _store.draftIdentityId ?? '',
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      templateId: _store.draftTemplateId,
      password: _store.draftPassword.text.trim().isEmpty
          ? null
          : _store.draftPassword.text.trim(),
      expiresAt: _store.draftExpiresAt,
      maxResponses: mr,
      identifier: _store.draftIdentifier.text.trim().isEmpty
          ? null
          : _store.draftIdentifier.text.trim(),
      callbackUrl: _store.draftCallback.text.trim().isEmpty
          ? null
          : _store.draftCallback.text.trim(),
      requireHandshake: _store.draftRequireHandshake,
      identityScope: _store.draftRequireHandshake
          ? _store.draftIdentityScope
          : 'any',
      allowExtraFields: _store.draftAllowExtraFields,
    );
  }

  Widget _buildTitleRow() {
    final v = _store.draftLabel.text.trim();
    return AppFormRow(
      icon: AppIcons.fileText,
      label: 'Title',
      valueText: v.isEmpty ? 'Required' : v,
      isPlaceholder: v.isEmpty,
      isError: v.isEmpty,
      onTap: () => _editText(
        title: 'Title',
        description: 'A short name for this request.',
        controller: _store.draftLabel,
        hint: 'e.g. Onboarding intake',
      ),
    );
  }

  Widget _buildSlugRow() {
    final slug = _store.draftSlug.text.trim();
    final hasWarning = _store.draftSlugWarning != null;
    return AppFormRow(
      icon: AppIcons.link,
      label: 'Slug',
      valueText: slug.isEmpty
          ? 'Required'
          : (hasWarning ? _store.draftSlugWarning! : slug),
      isPlaceholder: slug.isEmpty,
      isError: slug.isEmpty || hasWarning,
      onTap: _editSlug,
    );
  }

  /// The same inline picker the share drawer uses. Choosing which key signs
  /// something is one decision with one control.
  Widget _buildIdentityRow() {
    if (Stores.identities.identities.isEmpty) {
      return AppFormRow(
        icon: AppIcons.shieldCheck,
        label: 'Cryptographic identity',
        valueText: 'Create an identity in Settings first',
        isPlaceholder: true,
        isError: true,
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.settings);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign this request with one of your identities so responders can '
            'cryptographically verify who is asking.',
          ).muted.small,
          AppSpacing.gapMd,
          IdentityPicker(
            selectedId: _store.draftIdentityId,
            onChanged: _store.setDraftIdentity,
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateRow() {
    final name = _templateName();
    return AppFormRow(
      icon: AppIcons.cardList,
      label: 'Template',
      valueText: name ?? 'None — free-form submission',
      isPlaceholder: name == null,
      onClear: () => _store.setDraftTemplate(null),
      onTap: _pickTemplate,
    );
  }

  Widget _buildPasswordRow() {
    final has = _store.draftPassword.text.trim().isNotEmpty;
    return AppFormRow(
      icon: AppIcons.lock,
      label: 'Password',
      valueText: has ? '••••••••' : 'Not set',
      isPlaceholder: !has,
      onClear: _store.draftPassword.clear,
      onTap: () => _editText(
        title: 'Password',
        description: 'Senders must enter this password before they can submit.',
        controller: _store.draftPassword,
        hint: 'Leave blank for no password',
        passwordToggle: true,
      ),
    );
  }

  Widget _buildIdentityScopeRow() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.shieldLock,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Accepted identities').small,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: AppSegmented<String>(
              value: _store.draftIdentityScope,
              items: const [
                AppSegmentedItem(
                  value: 'any',
                  icon: AppIcons.globe,
                  label: 'Any',
                ),
                AppSegmentedItem(
                  value: 'from_root',
                  icon: AppIcons.shieldCheck,
                  label: 'From this root',
                ),
              ],
              onChanged: _store.setDraftIdentityScope,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifierRow() {
    final v = _store.draftIdentifier.text.trim();
    return AppFormRow(
      icon: AppIcons.tag,
      label: 'Identifier',
      valueText: v.isEmpty ? 'Anonymous (no identifier)' : v,
      isPlaceholder: v.isEmpty,
      onClear: _store.draftIdentifier.clear,
      onTap: () => _editText(
        title: 'Identifier',
        description:
            'A secret you hand to one recipient. They must echo it back, which '
            'ties their response to it (a pseudonym) and blocks slug guessing.',
        controller: _store.draftIdentifier,
        hint: 'e.g. INV-2024-0093',
      ),
    );
  }

  /// Live summary translating the two access axes — "who can respond"
  /// (handshake) × "can we identify them" (identifier) — into a named mode,
  /// so the requester sees what they're actually configuring.
  Widget _buildAccessSummary() {
    final scheme = Theme.of(context).colorScheme;
    final hasIdentifier = _store.draftIdentifier.text.trim().isNotEmpty;
    final hs = _store.draftRequireHandshake;
    final rootOnly = hs && _store.draftIdentityScope == 'from_root';

    final IconData icon;
    final String mode;
    final String reach;
    final String desc;
    if (hs && hasIdentifier) {
      icon = AppIcons.shieldLock;
      mode = 'Locked to one recipient';
      reach = '1 ↔ 1';
      desc =
          'Only the holder of the identifier, signed in with their cryptographic '
          'identity, can respond. Maximum security.';
    } else if (hs) {
      icon = AppIcons.shieldCheck;
      mode = 'Verified identities';
      reach = 'Signed-in';
      desc =
          'Anyone signed in with a cryptographic identity can respond — every '
          'response is cryptographically attributable.';
    } else if (hasIdentifier) {
      icon = AppIcons.tag;
      mode = 'Pseudonymous';
      reach = 'Identifier holders';
      desc =
          'Only people you give the identifier to can respond, and each response '
          'is tied to that identifier. Also blocks slug guessing.';
    } else {
      icon = AppIcons.globe;
      mode = 'Open to anyone';
      reach = 'Many → one';
      desc =
          'Anyone with the link can respond, anonymously (a name is optional). '
          'Best for collecting from many people.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(mode).small),
                    AppBadge(
                      label: rootOnly ? 'This root' : reach,
                      accent: scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  rootOnly
                      ? '$desc Only identities issued by this server '
                            '(same-system accounts) are accepted.'
                      : desc,
                ).muted.small,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaxResponsesRow() {
    final v = _store.draftMaxResponses.text.trim();
    return AppFormRow(
      icon: AppIcons.collection,
      label: 'Max responses',
      valueText: v.isEmpty ? 'Unlimited' : v,
      isPlaceholder: v.isEmpty,
      onClear: _store.draftMaxResponses.clear,
      onTap: () => _editText(
        title: 'Max responses',
        description: 'Auto-complete the request after this many submissions.',
        controller: _store.draftMaxResponses,
        hint: 'e.g. 1 — leave blank for unlimited',
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildExpiryRow() {
    return AppFormRow(
      icon: AppIcons.clock,
      label: 'Expires at',
      valueText: _store.draftExpiresAt == null
          ? 'Never'
          : _formatDate(_store.draftExpiresAt!),
      isPlaceholder: _store.draftExpiresAt == null,
      onClear: () => _store.setDraftExpiry(null),
      onTap: _pickExpiry,
    );
  }

  Widget _buildCallbackRow() {
    final v = _store.draftCallback.text.trim();
    return AppFormRow(
      icon: AppIcons.send,
      label: 'Callback URL',
      valueText: v.isEmpty ? 'Not set' : v,
      isPlaceholder: v.isEmpty,
      onClear: _store.draftCallback.clear,
      onTap: () => _editText(
        title: 'Callback URL',
        description: 'Each submission is POSTed here as JSON.',
        controller: _store.draftCallback,
        hint: 'https://example.com/hook',
        keyboardType: TextInputType.url,
      ),
    );
  }

  Future<void> _editText({
    required String title,
    String? description,
    required TextEditingController controller,
    String? hint,
    bool passwordToggle = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) async {
    await showAppEditSheet(
      context: context,
      title: title,
      description: description,
      controller: controller,
      hint: hint,
      passwordToggle: passwordToggle,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
    );
  }

  /// Slug editor — text field plus regenerate and live uniqueness validation.
  Future<void> _editSlug() async {
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
                  Text('Slug').header,
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'The public URL path for this request. Min 6 characters.',
                  ).muted.small,
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _store.draftSlug,
                          hint: 'intake-2024',
                          autofocus: true,
                          inputFormatters: [SlugInputFormatter()],
                          onChanged: (v) async {
                            await _validateSlug(v);
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppButton(
                        icon: AppIcons.arrowClockwise,
                        tooltip: 'Suggest a slug',
                        style: AppButtonStyle.accent,
                        onTap: () async {
                          final s = _randomSlug(Random().nextInt(6) + 6);
                          _store.draftSlug.text = s;
                          await _validateSlug(s);
                        },
                      ),
                    ],
                  ),
                  if (_store.isCheckingSlug) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        const AppSpinner(),
                        const SizedBox(width: AppSpacing.xs),
                        const Text('Checking availability…').muted.small,
                      ],
                    ),
                  ] else if (_store.draftSlugWarning != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppErrorText(_store.draftSlugWarning!),
                  ],
                  if (_store.draftSuggestedSlug != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Use suggested: $_store.draftSuggestedSlug',
                        onTap: () async {
                          _store.draftSlug.text = _store.draftSuggestedSlug!;
                          await _validateSlug(_store.draftSlug.text);
                        },
                        style: AppButtonStyle.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Done',
                    onTap:
                        (_store.draftSlug.text.trim().length >= 6 &&
                            _store.draftSlugWarning == null &&
                            !_store.isCheckingSlug)
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

  Future<void> _pickTemplate() async {
    // Empty string sentinel = "None"; null = dismissed without choosing.
    final picked = await showAppSheet<String>(
      context: context,
      builder: (sheetCtx) {
        return Observer(
          builder: (_) {
            final templates = Stores.templates.templates;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxs,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text('Choose template').header,
                ),
                AppTile(
                  padding: _pickerRowPadding,
                  title: const Text('None'),
                  subtitle: const Text(
                    'Free-form key/value submission.',
                  ).muted.small,
                  trailing: _store.draftTemplateId == null
                      ? Icon(
                          AppIcons.check,
                          color: Theme.of(sheetCtx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(''),
                ),
                if (templates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.sm,
                    ),
                    child: AppButton(
                      label: 'Create a template',
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        Navigator.of(context).pop();
                        context.go(AppRoutes.templates);
                      },
                      style: AppButtonStyle.accent,
                    ),
                  )
                else
                  ...templates.map((t) {
                    final selected = t.id == _store.draftTemplateId;
                    final recCount =
                        (t.schema['records'] as List?)?.length ?? 0;
                    final secCount =
                        (t.schema['sections'] as List?)?.length ?? 0;
                    return AppTile(
                      padding: _pickerRowPadding,
                      title: Text(t.name),
                      subtitle: Text(
                        '$recCount record${recCount == 1 ? '' : 's'} · '
                        '$secCount section${secCount == 1 ? '' : 's'} · '
                        '${_requiredCount(t.schema)} required',
                      ).muted.small,
                      trailing: selected
                          ? Icon(
                              AppIcons.check,
                              color: Theme.of(sheetCtx).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetCtx).pop(t.id),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      _store.setDraftTemplate(picked.isEmpty ? null : picked);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _store.draftExpiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) _store.setDraftExpiry(picked);
  }

  void _ensureIdentityDefault() {
    if (_store.draftIdentityId != null) return;
    final store = Stores.identities;
    _store.draftIdentityId =
        store.primaryIdentity?.id ??
        (store.identities.isNotEmpty ? store.identities.first.id : null);
  }

  String? _templateName() {
    if (_store.draftTemplateId == null) return null;
    for (final t in Stores.templates.templates) {
      if (t.id == _store.draftTemplateId) return t.name;
    }
    return 'Selected template';
  }

  int _requiredCount(Map<String, dynamic> schema) {
    int n = 0;
    for (final raw in (schema['records'] as List? ?? const [])) {
      if (raw is Map && raw['required'] == true) n++;
    }
    for (final raw in (schema['sections'] as List? ?? const [])) {
      if (raw is Map) {
        for (final child in (raw['records'] as List? ?? const [])) {
          if (child is Map && child['required'] == true) n++;
        }
      }
    }
    return n;
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
