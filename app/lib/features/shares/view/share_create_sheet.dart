import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';

void openShareCreateSheet({
  required BuildContext context,
  Link? initialShare,
  Link? editShare,
}) {
  Stores.shares.clearError();
  showAppSheet(
    context: context,
    builder: (_) =>
        _ShareCreateForm(initialShare: initialShare, editShare: editShare),
  );
}

class _ShareCreateForm extends StatefulWidget {
  final Link? initialShare;
  final Link? editShare;

  const _ShareCreateForm({this.initialShare, this.editShare});

  @override
  State<_ShareCreateForm> createState() => _ShareCreateFormState();
}

class _ShareCreateFormState extends State<_ShareCreateForm> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _slugCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _maxViewsCtrl;
  DateTime? _expiresAt;
  String? _identityId;
  bool _requireHandshake = false;

  String? _slugWarning;
  bool _isSubmitting = false;

  String _generateRandomSlug() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final length = 6 + random.nextInt(7);
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final link = widget.editShare ?? widget.initialShare;
    _labelCtrl = TextEditingController(
      text: link != null
          ? (widget.editShare != null ? link.label : '${link.label} Copy')
          : '',
    );
    final defaultSlug = widget.editShare != null
        ? widget.editShare!.slug
        : _generateRandomSlug();
    _slugCtrl = TextEditingController(text: defaultSlug);
    _passwordCtrl = TextEditingController();
    _maxViewsCtrl = TextEditingController(
      text: (link?.maxViews ?? 0) > 0 ? link!.maxViews.toString() : '',
    );
    _expiresAt = link?.expiresAt != null
        ? DateTime.tryParse(link!.expiresAt!)
        : null;
    _identityId = link?.identity;
    _requireHandshake = link?.requireHandshake ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_slugCtrl.text.isNotEmpty && widget.editShare == null) {
        _validateSlug(_slugCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _slugCtrl.dispose();
    _passwordCtrl.dispose();
    _maxViewsCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateSlug(String input) async {
    if (input.isEmpty) {
      setState(() => _slugWarning = null);
      return;
    }
    final taken = await Stores.shares.isSlugTaken(input);
    if (!mounted) return;
    if (taken &&
        (widget.editShare == null || widget.editShare!.slug != input)) {
      setState(() => _slugWarning = 'This slug is already taken.');
    } else {
      setState(() => _slugWarning = null);
    }
  }

  bool _canSubmit() {
    return _labelCtrl.text.trim().isNotEmpty &&
        _slugCtrl.text.trim().isNotEmpty &&
        _slugWarning == null;
  }

  /// The exact API request the current form would issue — drives the live
  /// developer preview (create vs update), mirroring [_submit].
  ApiRequestSpec _buildSpec() {
    if (widget.editShare != null) {
      final updates = <String, dynamic>{
        'label': _labelCtrl.text.trim(),
        'slug': _slugCtrl.text.trim(),
        'maxViews': int.tryParse(_maxViewsCtrl.text) ?? 0,
        if (_passwordCtrl.text.isNotEmpty) 'password': _passwordCtrl.text,
        'expiresAt': _expiresAt?.toIso8601String() ?? '',
        'identity': _identityId ?? '',
        'requireHandshake': _requireHandshake,
      };
      return Stores.shares.updateShareSpec(widget.editShare!.id, updates);
    }
    return Stores.shares.createShareSpec(
      slug: _slugCtrl.text.trim(),
      label: _labelCtrl.text.trim(),
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: widget.initialShare?.sections ?? const [],
      records: widget.initialShare?.records ?? const [],
      password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
      maxViews: int.tryParse(_maxViewsCtrl.text),
      expiresAt: _expiresAt,
      identityId: _identityId,
      requireHandshake: _requireHandshake,
    );
  }

  Future<bool> _submit() async {
    if (widget.editShare != null) {
      final updates = <String, dynamic>{
        'label': _labelCtrl.text.trim(),
        'slug': _slugCtrl.text.trim(),
        'maxViews': int.tryParse(_maxViewsCtrl.text) ?? 0,
        'identity': _identityId ?? '',
        'requireHandshake': _requireHandshake,
      };
      if (_passwordCtrl.text.isNotEmpty) {
        updates['password'] = _passwordCtrl.text;
      }
      if (_expiresAt != null) {
        updates['expiresAt'] = _expiresAt!.toIso8601String();
      } else {
        updates['expiresAt'] = '';
      }

      final ok = await Stores.shares.updateShare(widget.editShare!.id, updates);
      if (!mounted) return false;
      if (!ok) {
        AppToast.error(
          context,
          'Could not update share',
          subtitle: Stores.shares.errorMessage,
        );
        return false;
      }
      AppToast.success(context, 'Share updated');
      return true;
    }

    final ok = await Stores.shares.createShare(
      slug: _slugCtrl.text.trim(),
      label: _labelCtrl.text.trim(),
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: widget.initialShare?.sections ?? [],
      records: widget.initialShare?.records ?? [],
      password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
      maxViews: int.tryParse(_maxViewsCtrl.text),
      expiresAt: _expiresAt,
      identityId: _identityId,
      requireHandshake: _requireHandshake,
    );
    if (!mounted) return false;
    if (!ok) {
      AppToast.error(
        context,
        'Could not create share',
        subtitle: Stores.shares.errorMessage,
      );
      return false;
    }
    AppToast.success(
      context,
      widget.initialShare != null ? 'Share duplicated' : 'Share created',
    );
    return true;
  }

  Future<void> _onSubmit() async {
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
    final isEdit = widget.editShare != null;
    final isDup = widget.initialShare != null;
    final title = isEdit
        ? 'Edit share'
        : (isDup ? 'Duplicate share' : 'New share link');
    final completeLabel = isEdit
        ? 'Save changes'
        : (isDup ? 'Duplicate' : 'Create share');

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
                Text(title).header,
                AppSpacing.gapXxs,
                const Text(
                  'A public link to view the shared records. '
                  'Gate it with a password, view cap or expiry.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Flexible(
            child: Observer(
              builder: (_) {
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  children: [
                    const AppFormSectionHeader('Details'),
                    _buildLabelRow(),
                    _buildSlugRow(),

                    const AppFormSectionHeader('Access'),
                    _buildMaxViewsRow(),
                    _buildExpiryRow(),
                    _buildPasswordRow(),

                    const AppFormSectionHeader('Verification'),
                    _buildVerificationSection(),

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
                        title: 'API request · ${isEdit ? 'update' : 'create'}',
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
                    style: AppButtonStyle.accent,
                    onTap: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    label: completeLabel,
                    busy: _isSubmitting,
                    onTap: _canSubmit() ? _onSubmit : null,
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
          description: 'A friendly name for this share link.',
          controller: _labelCtrl,
          hint: 'Vendor Onboarding',
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildSlugRow() {
    final slug = _slugCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.link,
      label: 'URL slug',
      valueText: slug.isEmpty ? 'Required' : (_slugWarning ?? slug),
      isPlaceholder: slug.isEmpty,
      isError: slug.isEmpty || _slugWarning != null,
      onTap: _editSlug,
    );
  }

  Widget _buildMaxViewsRow() {
    final v = _maxViewsCtrl.text.trim();
    return AppFormRow(
      icon: AppIcons.collection,
      label: 'Maximum views',
      valueText: v.isEmpty ? 'Unlimited' : v,
      isPlaceholder: v.isEmpty,
      onClear: () => setState(() => _maxViewsCtrl.clear()),
      onTap: () async {
        await showAppEditSheet(
          context: context,
          title: 'Maximum views',
          description: 'Auto-expire the link after this many views.',
          controller: _maxViewsCtrl,
          hint: 'e.g. 5 — leave blank for unlimited',
          keyboardType: TextInputType.number,
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildExpiryRow() {
    return AppFormRow(
      icon: AppIcons.clock,
      label: 'Expiration date',
      valueText: _expiresAt == null ? 'Never' : _formatDate(_expiresAt!),
      isPlaceholder: _expiresAt == null,
      onClear: () => setState(() => _expiresAt = null),
      onTap: _pickExpiry,
    );
  }

  Widget _buildPasswordRow() {
    final has = _passwordCtrl.text.isNotEmpty;
    return AppFormRow(
      icon: AppIcons.lock,
      label: 'Password',
      valueText: has ? '••••••••' : 'Not set',
      isPlaceholder: !has,
      onClear: () => setState(() => _passwordCtrl.clear()),
      onTap: () async {
        await showAppEditSheet(
          context: context,
          title: 'Password',
          description: 'Recipients must enter this before viewing the share.',
          controller: _passwordCtrl,
          hint: 'Leave blank for no password',
          passwordToggle: true,
        );
        if (mounted) setState(() {});
      },
    );
  }

  /// Optional cryptographic origin + viewer gating. Signing the share lets
  /// recipients verify who shared it; requiring a handshake forces viewers to
  /// prove control of an identity before the data is revealed.
  Widget _buildVerificationSection() {
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
          const Text(
            'Sign this share with one of your identities so recipients can '
            'cryptographically verify who shared it.',
          ).muted.small,
          AppSpacing.gapMd,
          IdentityPicker(
            selectedId: _identityId,
            allowNone: true,
            onChanged: (v) => setState(() => _identityId = v),
          ),
          AppSpacing.gapXxs,
          AppFormToggleRow(
            label: 'Require a verified viewer',
            subtitle:
                'Viewers must prove control of a cryptographic identity '
                '(handshake) before the data is revealed.',
            value: _requireHandshake,
            onChanged: (v) => setState(() => _requireHandshake = v),
            inset: false,
          ),
        ],
      ),
    );
  }

  // --- Sub-sheets ------------------------------------------------------

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
                  Text('URL slug').header,
                  AppSpacing.gapXxs,
                  const Text(
                    'The public URL path for this share link.',
                  ).muted.small,
                  AppSpacing.gapLg,
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _slugCtrl,
                          hint: 'vendor-onboarding-2024',
                          autofocus: true,
                          inputFormatters: [SlugInputFormatter()],
                          onChanged: (v) async {
                            await _validateSlug(v);
                            setSheet(() {});
                          },
                        ),
                      ),
                      AppSpacing.gapSm,
                      AppButton(
                        icon: AppIcons.arrowRepeat,
                        style: AppButtonStyle.accent,
                        tooltip: 'Generate a random slug',
                        onTap: () async {
                          final s = _generateRandomSlug();
                          _slugCtrl.text = s;
                          await _validateSlug(s);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  if (_slugWarning != null) ...[
                    AppSpacing.gapSm,
                    Text(_slugWarning!).small,
                  ],
                  AppSpacing.gapLg,
                  AppButton(
                    label: 'Done',
                    onTap:
                        (_slugCtrl.text.trim().isNotEmpty &&
                            _slugWarning == null)
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

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
