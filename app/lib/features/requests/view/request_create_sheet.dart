import 'dart:math';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputFormatter;
import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';

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
  final _labelCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  final _callbackCtrl = TextEditingController();
  final _maxResponsesCtrl = TextEditingController();

  String? _selectedIdentityId;
  String? _selectedTemplateId;
  bool _requireHandshake = false;
  String _identityScope = 'any'; // 'any' | 'from_root' (only when handshake on)
  bool _allowExtraFields = false;
  DateTime? _expiresAt;

  String? _slugWarning;
  String? _suggestedSlug;
  bool _checkingSlug = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final edit = widget.editRequest;
    if (edit != null) {
      _labelCtrl.text = edit.label;
      _slugCtrl.text = edit.slug;
      _identifierCtrl.text = edit.identifier;
      _callbackCtrl.text = edit.callbackUrl;
      _maxResponsesCtrl.text = edit.maxResponses > 0
          ? edit.maxResponses.toString()
          : '';
      _selectedIdentityId = edit.identity.isEmpty ? null : edit.identity;
      _selectedTemplateId = edit.templateId.isEmpty ? null : edit.templateId;
      _requireHandshake = edit.requireHandshake;
      _identityScope = edit.identityScope.isEmpty ? 'any' : edit.identityScope;
      _allowExtraFields = edit.allowExtraFields;
      _expiresAt = edit.expiresAt != null
          ? DateTime.tryParse(edit.expiresAt!)
          : null;
    } else {
      _slugCtrl.text = _randomSlug(6);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.identities.loadIdentities();
      Stores.templates.loadTemplates(widget.authStore.activeWorkspace ?? '');
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _slugCtrl.dispose();
    _passwordCtrl.dispose();
    _identifierCtrl.dispose();
    _callbackCtrl.dispose();
    _maxResponsesCtrl.dispose();
    super.dispose();
  }

  String _randomSlug(int length) {
    final r = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _validateSlug(String input) async {
    if (input.isEmpty) {
      setState(() {
        _slugWarning = null;
        _suggestedSlug = null;
      });
      return;
    }
    if (input.length < 6) {
      setState(() {
        _slugWarning = 'Slug must be at least 6 characters.';
        _suggestedSlug = null;
      });
      return;
    }
    setState(() => _checkingSlug = true);
    final taken = await widget.store.isSlugTaken(input);
    if (!mounted) return;
    if (taken && widget.editRequest?.slug != input) {
      final alt = await widget.store.generateAlternativeSlug(input);
      if (!mounted) return;
      setState(() {
        _slugWarning = 'This slug is already taken.';
        _suggestedSlug = alt;
        _checkingSlug = false;
      });
    } else {
      setState(() {
        _slugWarning = null;
        _suggestedSlug = null;
        _checkingSlug = false;
      });
    }
  }

  bool _canSubmit() {
    if (_labelCtrl.text.trim().isEmpty) return false;
    final slug = _slugCtrl.text.trim();
    if (slug.length < 6) return false;
    if (_slugWarning != null) return false;
    if (_checkingSlug) return false;
    if (_selectedIdentityId == null) return false;
    return true;
  }

  Future<bool> _submit() async {
    final mr = int.tryParse(_maxResponsesCtrl.text.trim());

    final edit = widget.editRequest;
    if (edit != null) {
      final body = <String, dynamic>{
        'label': _labelCtrl.text.trim(),
        'slug': _slugCtrl.text.trim(),
        'identity': _selectedIdentityId,
        'template': _selectedTemplateId ?? '',
        'maxResponses': mr ?? 0,
        'identifier': _identifierCtrl.text.trim(),
        'callbackUrl': _callbackCtrl.text.trim(),
        'requireHandshake': _requireHandshake,
        'identityScope': _requireHandshake ? _identityScope : 'any',
        'allowExtraFields': _allowExtraFields,
        'expiresAt': _expiresAt?.toUtc().toIso8601String() ?? '',
      };
      if (_passwordCtrl.text.trim().isNotEmpty) {
        body['password'] = _passwordCtrl.text.trim();
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
      slug: _slugCtrl.text.trim(),
      label: _labelCtrl.text.trim(),
      identityId: _selectedIdentityId!,
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      templateId: _selectedTemplateId,
      password: _passwordCtrl.text.trim().isEmpty
          ? null
          : _passwordCtrl.text.trim(),
      expiresAt: _expiresAt,
      maxResponses: mr,
      identifier: _identifierCtrl.text.trim().isEmpty
          ? null
          : _identifierCtrl.text.trim(),
      callbackUrl: _callbackCtrl.text.trim().isEmpty
          ? null
          : _callbackCtrl.text.trim(),
      requireHandshake: _requireHandshake,
      identityScope: _requireHandshake ? _identityScope : 'any',
      allowExtraFields: _allowExtraFields,
    );
    if (!mounted) return false;
    if (ok) {
      final url = DeepLinks.request(_slugCtrl.text.trim());
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
    setState(() => _isSubmitting = true);
    final ok = await _submit();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      value: _allowExtraFields,
                      onChanged: (v) => setState(() => _allowExtraFields = v),
                    ),

                    const AppFormSectionHeader('Who can respond'),
                    _buildAccessSummary(),
                    AppFormToggleRow(
                      icon: AppIcons.shieldCheck,
                      label: 'Require a verified identity',
                      subtitle:
                          'Responder must be signed in with a cryptographic identity.',
                      value: _requireHandshake,
                      onChanged: (v) => setState(() => _requireHandshake = v),
                    ),
                    if (_requireHandshake) _buildIdentityScopeRow(),
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
                    label: widget.editRequest != null
                        ? 'Save changes'
                        : 'Create request',
                    busy: _isSubmitting,
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

  // --- Rows ------------------------------------------------------------

  /// The exact API request the current form would issue — drives the live
  /// developer preview (create vs update), mirroring [_submit].
  ApiRequestSpec _buildSpec() {
    final mr = int.tryParse(_maxResponsesCtrl.text.trim());
    final edit = widget.editRequest;
    if (edit != null) {
      final body = <String, dynamic>{
        'label': _labelCtrl.text.trim(),
        'slug': _slugCtrl.text.trim(),
        'identity': _selectedIdentityId,
        'template': _selectedTemplateId ?? '',
        'maxResponses': mr ?? 0,
        'identifier': _identifierCtrl.text.trim(),
        'callbackUrl': _callbackCtrl.text.trim(),
        'requireHandshake': _requireHandshake,
        'identityScope': _requireHandshake ? _identityScope : 'any',
        'allowExtraFields': _allowExtraFields,
        'expiresAt': _expiresAt?.toUtc().toIso8601String() ?? '',
        if (_passwordCtrl.text.trim().isNotEmpty)
          'password': _passwordCtrl.text.trim(),
      };
      return RequestsStore.updateRequestSpec(edit.id, body);
    }
    return RequestsStore.createRequestSpec(
      slug: _slugCtrl.text.trim(),
      label: _labelCtrl.text.trim(),
      identityId: _selectedIdentityId ?? '',
      user: widget.authStore.userId,
      workspace: widget.authStore.activeWorkspace ?? '',
      templateId: _selectedTemplateId,
      password: _passwordCtrl.text.trim().isEmpty
          ? null
          : _passwordCtrl.text.trim(),
      expiresAt: _expiresAt,
      maxResponses: mr,
      identifier: _identifierCtrl.text.trim().isEmpty
          ? null
          : _identifierCtrl.text.trim(),
      callbackUrl: _callbackCtrl.text.trim().isEmpty
          ? null
          : _callbackCtrl.text.trim(),
      requireHandshake: _requireHandshake,
      identityScope: _requireHandshake ? _identityScope : 'any',
      allowExtraFields: _allowExtraFields,
    );
  }

  Widget _buildTitleRow() {
    final v = _labelCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.fileText,
      label: 'Title',
      valueText: v.isEmpty ? 'Required' : v,
      isPlaceholder: v.isEmpty,
      isError: v.isEmpty,
      onTap: () => _editText(
        title: 'Title',
        description: 'A short name for this request.',
        controller: _labelCtrl,
        hint: 'e.g. Onboarding intake',
      ),
    );
  }

  Widget _buildSlugRow() {
    final slug = _slugCtrl.text.trim();
    final hasWarning = _slugWarning != null;
    return AppFormRow(
      icon: AppIcons.link,
      label: 'Slug',
      valueText: slug.isEmpty
          ? 'Required'
          : (hasWarning ? _slugWarning! : slug),
      isPlaceholder: slug.isEmpty,
      isError: slug.isEmpty || hasWarning,
      onTap: _editSlug,
    );
  }

  Widget _buildIdentityRow() {
    final store = Stores.identities;
    if (store.identities.isEmpty) {
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
    final name = _identityName();
    return AppFormRow(
      icon: AppIcons.shieldCheck,
      label: 'Cryptographic identity',
      valueText: name ?? 'Required',
      isPlaceholder: name == null,
      isError: name == null,
      onTap: _pickIdentity,
    );
  }

  Widget _buildTemplateRow() {
    final name = _templateName();
    return AppFormRow(
      icon: AppIcons.cardList,
      label: 'Template',
      valueText: name ?? 'None — free-form submission',
      isPlaceholder: name == null,
      onClear: () => setState(() => _selectedTemplateId = null),
      onTap: _pickTemplate,
    );
  }

  Widget _buildPasswordRow() {
    final has = _passwordCtrl.text.trim().isNotEmpty;
    return AppFormRow(
      icon: AppIcons.lock,
      label: 'Password',
      valueText: has ? '••••••••' : 'Not set',
      isPlaceholder: !has,
      onClear: () => setState(() => _passwordCtrl.clear()),
      onTap: () => _editText(
        title: 'Password',
        description: 'Senders must enter this password before they can submit.',
        controller: _passwordCtrl,
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
              value: _identityScope,
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
              onChanged: (v) => setState(() => _identityScope = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifierRow() {
    final v = _identifierCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.tag,
      label: 'Identifier',
      valueText: v.isEmpty ? 'Anonymous (no identifier)' : v,
      isPlaceholder: v.isEmpty,
      onClear: () => setState(() => _identifierCtrl.clear()),
      onTap: () => _editText(
        title: 'Identifier',
        description:
            'A secret you hand to one recipient. They must echo it back, which '
            'ties their response to it (a pseudonym) and blocks slug guessing.',
        controller: _identifierCtrl,
        hint: 'e.g. INV-2024-0093',
      ),
    );
  }

  /// Live summary translating the two access axes — "who can respond"
  /// (handshake) × "can we identify them" (identifier) — into a named mode,
  /// so the requester sees what they're actually configuring.
  Widget _buildAccessSummary() {
    final scheme = Theme.of(context).colorScheme;
    final hasIdentifier = _identifierCtrl.text.trim().isNotEmpty;
    final hs = _requireHandshake;
    final rootOnly = hs && _identityScope == 'from_root';

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
    final v = _maxResponsesCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.collection,
      label: 'Max responses',
      valueText: v.isEmpty ? 'Unlimited' : v,
      isPlaceholder: v.isEmpty,
      onClear: () => setState(() => _maxResponsesCtrl.clear()),
      onTap: () => _editText(
        title: 'Max responses',
        description: 'Auto-complete the request after this many submissions.',
        controller: _maxResponsesCtrl,
        hint: 'e.g. 1 — leave blank for unlimited',
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildExpiryRow() {
    return AppFormRow(
      icon: AppIcons.clock,
      label: 'Expires at',
      valueText: _expiresAt == null ? 'Never' : _formatDate(_expiresAt!),
      isPlaceholder: _expiresAt == null,
      onClear: () => setState(() => _expiresAt = null),
      onTap: _pickExpiry,
    );
  }

  Widget _buildCallbackRow() {
    final v = _callbackCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.send,
      label: 'Callback URL',
      valueText: v.isEmpty ? 'Not set' : v,
      isPlaceholder: v.isEmpty,
      onClear: () => setState(() => _callbackCtrl.clear()),
      onTap: () => _editText(
        title: 'Callback URL',
        description: 'Each submission is POSTed here as JSON.',
        controller: _callbackCtrl,
        hint: 'https://example.com/hook',
        keyboardType: TextInputType.url,
      ),
    );
  }

  // --- Sub-sheets ------------------------------------------------------

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
    if (mounted) setState(() {});
  }

  /// Slug editor — text field plus regenerate and live uniqueness validation.
  Future<void> _editSlug() async {
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
                          controller: _slugCtrl,
                          hint: 'intake-2024',
                          autofocus: true,
                          inputFormatters: [SlugInputFormatter()],
                          onChanged: (v) async {
                            await _validateSlug(v);
                            setSheet(() {});
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
                          _slugCtrl.text = s;
                          await _validateSlug(s);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  if (_checkingSlug) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        const AppSpinner(),
                        const SizedBox(width: AppSpacing.xs),
                        const Text('Checking availability…').muted.small,
                      ],
                    ),
                  ] else if (_slugWarning != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppErrorText(_slugWarning!),
                  ],
                  if (_suggestedSlug != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Use suggested: $_suggestedSlug',
                        onTap: () async {
                          _slugCtrl.text = _suggestedSlug!;
                          await _validateSlug(_slugCtrl.text);
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
                        (_slugCtrl.text.trim().length >= 6 &&
                            _slugWarning == null &&
                            !_checkingSlug)
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

  Future<void> _pickIdentity() async {
    final picked = await showAppSheet<String>(
      context: context,
      builder: (sheetCtx) {
        return Observer(
          builder: (_) {
            final identities = Stores.identities.identities;
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
                  child: Text('Choose identity').header,
                ),
                ...identities.map((id) {
                  final selected = id.id == _selectedIdentityId;
                  return AppTile(
                    padding: _pickerRowPadding,
                    title: Text(id.name),
                    subtitle: id.fingerprint.isEmpty
                        ? null
                        : Text(id.shortFingerprint).mono.small,
                    trailing: selected
                        ? Icon(
                            AppIcons.check,
                            color: Theme.of(sheetCtx).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetCtx).pop(id.id),
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
              ],
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedIdentityId = picked);
    }
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
                  trailing: _selectedTemplateId == null
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
                    final selected = t.id == _selectedTemplateId;
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
      setState(() => _selectedTemplateId = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) setState(() => _expiresAt = picked);
  }

  // --- Helpers ---------------------------------------------------------

  void _ensureIdentityDefault() {
    if (_selectedIdentityId != null) return;
    final store = Stores.identities;
    _selectedIdentityId =
        store.primaryIdentity?.id ??
        (store.identities.isNotEmpty ? store.identities.first.id : null);
  }

  String? _identityName() {
    if (_selectedIdentityId == null) return null;
    for (final id in Stores.identities.identities) {
      if (id.id == _selectedIdentityId) return id.name;
    }
    return null;
  }

  String? _templateName() {
    if (_selectedTemplateId == null) return null;
    for (final t in Stores.templates.templates) {
      if (t.id == _selectedTemplateId) return t.name;
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
