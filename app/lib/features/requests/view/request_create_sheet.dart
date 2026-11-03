import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collapsible_group.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/core/widgets/tool_proposal_alert.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';

/// Opens the request-create bottom sheet.
///
/// Single drawer: every setting is a row showing its current value. Tapping a
/// row opens a focused sub-sheet to edit it (text, password, picker, date);
/// boolean settings are toggled inline. What is asked comes first and is
/// required — a form with no template and no extra fields could only ever
/// collect empty answers. The rest sits under Advanced.
void openRequestCreateSheet({
  required BuildContext context,
  required RequestsStore store,
  required AuthStore authStore,
  DataRequest? editRequest,
  RequestProposal? proposal,
}) {
  showAppSheet(
    context: context,
    builder: (_) => _RequestCreateForm(
      parentContext: context,
      store: store,
      authStore: authStore,
      editRequest: editRequest,
      proposal: proposal,
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
  final BuildContext parentContext;
  final RequestsStore store;
  final AuthStore authStore;
  final DataRequest? editRequest;
  final RequestProposal? proposal;

  const _RequestCreateForm({
    required this.parentContext,
    required this.store,
    required this.authStore,
    this.editRequest,
    this.proposal,
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
      final proposal = widget.proposal;
      final days = proposal?.days;
      _store.startRequestDraft(
        slug: _randomSlug(6),
        label: proposal?.label ?? '',
        expiresAt: days == null
            ? null
            : DateTime.now().add(Duration(days: days)),
        proposal: proposal,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Stores.identities.loadIdentities();
      await Stores.templates.loadTemplates(
        widget.authStore.activeWorkspace ?? '',
      );
      _applyProposedTemplate();
    });
  }

  /// A tool names its template; the owner's own copy of it is found by name.
  void _applyProposedTemplate() {
    final name = widget.proposal?.template.toLowerCase();
    if (name == null || !mounted || _store.draftTemplateId != null) return;
    for (final t in Stores.templates.templates) {
      if (t.name.toLowerCase() == name) {
        _store.setDraftTemplate(t.id);
        return;
      }
    }
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
      _store.setDraftSlugCheck(warning: 'At least 6 characters are required.');
      return;
    }
    _store.setCheckingSlug(true);
    final taken = await widget.store.isSlugTaken(input);
    if (!mounted) return;
    if (taken && widget.editRequest?.slug != input) {
      final alt = await widget.store.generateAlternativeSlug(input);
      if (!mounted) return;
      _store.setDraftSlugCheck(
        warning: 'This address is already taken.',
        suggestion: alt,
      );
      _store.setCheckingSlug(false);
    } else {
      _store.setDraftSlugCheck();
      _store.setCheckingSlug(false);
    }
  }

  /// The request's title: the one typed, or the template's name.
  String get _effectiveLabel {
    final typed = _store.draftLabel.text.trim();
    if (typed.isNotEmpty) return typed;
    return _store.draftTemplateId == null ? '' : (_templateName() ?? '');
  }

  /// Whether the form asks for anything at all: a template's fields, or
  /// fields the responder adds.
  bool get _asksSomething =>
      _store.draftTemplateId != null || _store.draftAllowExtraFields;

  bool _canSubmit() {
    if (!_asksSomething) return false;
    if (_effectiveLabel.isEmpty) return false;
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
        'label': _effectiveLabel,
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
        'The request could not be updated.',
        subtitle: widget.store.errorMessage,
      );
      return false;
    }

    final ok = await widget.store.createRequest(
      slug: _store.draftSlug.text.trim(),
      label: _effectiveLabel,
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
      AppToast.success(context, 'Request created');
      return true;
    }
    AppToast.error(
      context,
      'The request could not be created.',
      subtitle: widget.store.errorMessage,
    );
    return false;
  }

  Future<void> _onCreate() async {
    _store.setSubmittingRequest(true);
    final ok = await _submit();
    if (!mounted) return;
    if (!ok) {
      _store.setSubmittingRequest(false);
      return;
    }
    final slug = _store.draftSlug.text.trim();
    final title = _effectiveLabel;
    Navigator.of(context).pop();
    // A new request is made to be passed on: hand its link over at once.
    final parent = widget.parentContext;
    if (widget.editRequest == null && parent.mounted) {
      await showShareSheet(
        context: parent,
        slug: slug,
        title: title,
        isRequest: true,
      );
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
                  widget.editRequest != null ? 'Edit request' : 'New request',
                ).header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Requests collect answers through a form. Responding '
                  'requires an account.',
                ).muted.small,
                if (widget.proposal case final p?
                    when !p.proposer.isEmpty && widget.editRequest == null) ...[
                  AppSpacing.gapSm,
                  ToolProposalAlert(proposer: p.proposer),
                ],
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
                    const AppFormSectionHeader('Fields'),
                    _buildTemplateRow(),
                    AppFormToggleRow(
                      icon: AppIcons.plus,
                      label: 'Allow extra fields',
                      subtitle: _store.draftTemplateId == null
                          ? 'Respondents add their own fields. Required '
                                'when no template is selected.'
                          : 'Respondents may add fields beyond the template.',
                      value: _store.draftAllowExtraFields,
                      onChanged: _store.setDraftAllowExtraFields,
                    ),

                    const AppFormSectionHeader('Details'),
                    _buildTitleRow(),
                    _buildExpiryRow(),
                    // Required, so it stays in view until one is picked.
                    if (_store.draftIdentityId == null) _buildIdentityRow(),
                    _buildAccessSummary(),

                    AppFormAdvanced(
                      summary:
                          'Address, identity checks, password, limits, '
                          'callback and API',
                      initiallyOpen: _store.draftSlugWarning != null,
                      children: [
                        _buildSlugRow(),
                        if (_store.draftIdentityId != null) _buildIdentityRow(),
                        const AppFormSectionHeader('Respondents'),
                        AppFormToggleRow(
                          icon: AppIcons.shieldCheck,
                          label: 'Require a verified identity',
                          subtitle:
                              'Respondents prove who they are with a verified identity.',
                          value: _store.draftRequireHandshake,
                          onChanged: _store.setDraftHandshake,
                        ),
                        if (_store.draftRequireHandshake)
                          _buildIdentityScopeRow(),
                        _buildIdentifierRow(),
                        _buildPasswordRow(),

                        const AppFormSectionHeader('Limits and callback'),
                        _buildMaxResponsesRow(),
                        _buildCallbackRow(),
                        _buildCallbackTestRow(),

                        ApiPreviewSection(
                          spec: _buildSpec(),
                          title:
                              'API request · ${widget.editRequest != null ? 'update' : 'create'}',
                        ),
                      ],
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
                AppButton(
                  label: 'Cancel',
                  onTap: _store.isSubmittingRequest
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: AppButtonStyle.accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: widget.editRequest != null
                        ? AppIcons.check
                        : AppIcons.plus,
                    label: widget.editRequest != null
                        ? 'Save changes'
                        : 'Create request',
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
        'label': _effectiveLabel,
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
      label: _effectiveLabel,
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

  Widget _buildTitleRow() => AppFormField(
    label: 'Title',
    explanation: 'The heading shown on the form.',
    note: _store.draftLabel.text.trim().isEmpty && _effectiveLabel.isNotEmpty
        ? 'Defaults to $_effectiveLabel when empty.'
        : null,
    child: AppTextField(
      controller: _store.draftLabel,
      hint: _effectiveLabel.isEmpty ? 'Onboarding intake' : _effectiveLabel,
    ),
  );

  Widget _buildSlugRow() => AppFormField(
    label: 'Link address',
    explanation:
        'The last part of the link\'s web address. At least 6 characters.',
    error: _store.draftSlugWarning,
    note: _store.isCheckingSlug ? 'Checking…' : null,
    child: AppTextField(
      controller: _store.draftSlug,
      hint: 'intake-2024',
      mono: true,
      inputFormatters: [SlugInputFormatter()],
      onChanged: _validateSlug,
      trailing: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: AppButton(
          icon: AppIcons.arrowClockwise,
          tooltip: 'Suggest an address',
          showTooltip: false,
          style: AppButtonStyle.ghost,
          size: AppButtonSize.small,
          onTap: () async {
            final s = _randomSlug(Random().nextInt(6) + 6);
            _store.draftSlug.text = s;
            await _validateSlug(s);
          },
        ),
      ),
    ),
  );

  /// The same inline picker the share drawer uses. Choosing which key signs
  /// something is one decision with one control.
  Widget _buildIdentityRow() {
    if (Stores.identities.identities.isEmpty) {
      return AppFormField(
        label: 'Your identity',
        error: 'An identity is required. Identities are managed in Settings.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            icon: AppIcons.shieldCheck,
            label: 'Open Settings',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              Navigator.of(context).pop();
              context.go(AppRoutes.settings);
            },
          ),
        ),
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
            'The request is signed with this identity, so respondents can '
            'verify its origin.',
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
    return AppFormField(
      label: 'Template',
      note: name == null && _store.draftAllowExtraFields
          ? 'None — respondents add their own fields.'
          : null,
      child: AppPickerField(
        leading: AppIcons.cardList,
        text: name ?? 'No template selected',
        isPlaceholder: name == null,
        onClear: () => _store.setDraftTemplate(null),
        onTap: _pickTemplate,
      ),
    );
  }

  Widget _buildPasswordRow() => AppFormField(
    label: 'Password',
    explanation: 'Required to respond.',
    child: AppTextField(
      controller: _store.draftPassword,
      hint: 'No password',
      passwordToggle: true,
    ),
  );

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
                  label: 'This server only',
                ),
              ],
              onChanged: _store.setDraftIdentityScope,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifierRow() => AppFormField(
    label: 'Identifier',
    explanation:
        'Entered by the respondent to respond; each response is tied to '
        'it. The link alone is not sufficient.',
    child: AppTextField(
      controller: _store.draftIdentifier,
      hint: 'INV-2024-0093',
    ),
  );

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
      mode = 'One person only';
      reach = '1 ↔ 1';
      desc =
          'Only the holder of the identifier can respond, with a verified '
          'identity. The most restrictive option.';
    } else if (hs) {
      icon = AppIcons.shieldCheck;
      mode = 'Verified identities';
      reach = 'Verified';
      desc =
          'Anyone with a verified identity can respond. Every response is '
          'attributed.';
    } else if (hasIdentifier) {
      icon = AppIcons.tag;
      mode = 'People with the identifier';
      reach = 'By identifier';
      desc =
          'Only holders of the identifier can respond. Each response is tied '
          'to its identifier.';
    } else {
      icon = AppIcons.globe;
      mode = 'Anyone signed in';
      reach = 'Many → one';
      desc =
          'Anyone with the link can respond after signing in. Suited to '
          'large audiences.';
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
                      label: rootOnly ? 'This server' : reach,
                      accent: scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  rootOnly
                      ? '$desc Only identities from this server are accepted.'
                      : desc,
                ).muted.small,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaxResponsesRow() => AppFormField(
    label: 'Max responses',
    explanation: 'The request closes after this many responses.',
    child: AppTextField(
      controller: _store.draftMaxResponses,
      hint: 'Unlimited',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    ),
  );

  Widget _buildExpiryRow() {
    return AppFormField(
      label: 'Expires at',
      child: AppPickerField(
        text: _store.draftExpiresAt == null
            ? 'Never'
            : formatCalendarDay(_store.draftExpiresAt!),
        isPlaceholder: _store.draftExpiresAt == null,
        opens: AppIcons.calendar,
        onClear: () => _store.setDraftExpiry(null),
        onTap: _pickExpiry,
      ),
    );
  }

  Widget _buildCallbackRow() => AppFormField(
    label: 'Callback URL',
    explanation: 'Each response is sent here as JSON (POST).',
    child: AppTextField(
      controller: _store.draftCallback,
      hint: 'https://example.com/hook',
      keyboardType: TextInputType.url,
    ),
  );

  /// Sits under the callback row only once there is something to test.
  Widget _buildCallbackTestRow() {
    return Observer(
      builder: (context) {
        final url = _store.draftCallback.text.trim();
        if (url.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              icon: AppIcons.send,
              label: 'Send a test',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              busy: _store.callbackTesting,
              onTap: () => _testCallback(url),
            ),
          ),
        );
      },
    );
  }

  Future<void> _testCallback(String url) async {
    final result = await _store.testCallback(
      url,
      requestId: widget.editRequest?.id,
    );
    if (!mounted) return;
    if (result.ok) {
      AppToast.success(context, 'Callback reached', subtitle: result.detail);
      return;
    }
    // Every one of these reads as "not found" if you only print what came
    // back, and each has a different fix.
    final title = switch (result.code) {
      CallbackTestResult.codeBlocked => 'Address not allowed',
      CallbackTestResult.codeUnreachable => 'Address unreachable',
      CallbackTestResult.codeStatus => 'Rejected by the address',
      CallbackTestResult.codeApi => 'Test could not be requested',
      _ => 'Callback failed',
    };
    final hint = switch (result.code) {
      CallbackTestResult.codeBlocked =>
        'Local and private addresses are blocked by default. They are '
            'allowed when the server runs with ALLOW_PRIVATE_CALLBACKS=true.',
      CallbackTestResult.codeApi =>
        'The server may predate test callbacks. Test callbacks require an '
            'updated server.',
      _ => result.detail,
    };
    AppToast.error(context, title, subtitle: hint);
  }

  Future<void> _pickTemplate() async {
    // Empty string sentinel = "None"; null = dismissed without choosing.
    final picked = await showAppSheet<String>(
      context: context,
      dismissible: true,
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
                  child: Text('Template').header,
                ),
                AppTile(
                  padding: _pickerRowPadding,
                  title: const Text('None'),
                  subtitle: const Text(
                    'Respondents add their own fields. Enables extra '
                    'fields.',
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
                      icon: AppIcons.plus,
                      label: 'Create a template',
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        Navigator.of(context).pop();
                        context.go(AppRoutes.templates);
                      },
                      style: AppButtonStyle.accent,
                    ),
                  )
                else ...[
                  if (templates.any((t) => t.isBuiltin))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xs,
                        AppSpacing.xl,
                        0,
                      ),
                      child: AppCollapsibleGroup(
                        icon: AppIcons.folder,
                        title: 'Built-in',
                        children: [
                          for (final t in templates.where((t) => t.isBuiltin))
                            _templatePickerTile(sheetCtx, t, inGroup: true),
                        ],
                      ),
                    ),
                  for (final t in templates.where((t) => !t.isBuiltin))
                    _templatePickerTile(sheetCtx, t, inGroup: false),
                ],
              ],
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      _store.setDraftTemplate(picked.isEmpty ? null : picked);
      // Without a template, extra fields are the only thing a form can ask.
      if (picked.isEmpty) _store.setDraftAllowExtraFields(true);
    }
  }

  Widget _templatePickerTile(
    BuildContext sheetCtx,
    Template t, {
    required bool inGroup,
  }) {
    final selected = t.id == _store.draftTemplateId;
    final recCount = (t.schema['records'] as List?)?.length ?? 0;
    final secCount = (t.schema['sections'] as List?)?.length ?? 0;
    return AppTile(
      padding: inGroup
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            )
          : _pickerRowPadding,
      title: Text(t.name),
      subtitle: Text(
        '$recCount record${recCount == 1 ? '' : 's'} · '
        '$secCount section${secCount == 1 ? '' : 's'} · '
        '${_requiredCount(t.schema)} required',
      ).muted.small,
      trailing: selected
          ? Icon(AppIcons.check, color: Theme.of(sheetCtx).colorScheme.primary)
          : null,
      onTap: () => Navigator.of(sheetCtx).pop(t.id),
    );
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
}
