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
import 'package:revoked_app/features/shares/store/shares_store.dart';

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
  SharesStore get _store => Stores.shares;

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
    _store.startShareDraft(
      label: link != null
          ? (widget.editShare != null ? link.label : '${link.label} Copy')
          : '',
      slug: widget.editShare != null
          ? widget.editShare!.slug
          : _generateRandomSlug(),
      maxViews: (link?.maxViews ?? 0) > 0 ? link!.maxViews.toString() : '',
      expiresAt: link?.expiresAt != null
          ? DateTime.tryParse(link!.expiresAt!)
          : null,
      // PocketBase returns "" for an unset relation, which `??` does not catch;
      // an empty id matches no option, so editing an unsigned share showed the
      // picker with nothing selected at all.
      identityId: switch (link?.identity) {
        final String id when id.isNotEmpty => id,
        // Editing keeps the share's own answer, including "unsigned".
        _ when widget.editShare != null => null,
        _ => Stores.identities.primaryIdentity?.id,
      },
      requireHandshake: link?.requireHandshake ?? false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_store.draftSlug.text.isNotEmpty && widget.editShare == null) {
        _validateSlug(_store.draftSlug.text);
      }
    });
  }

  Future<void> _validateSlug(String input) async {
    if (input.isEmpty) {
      _store.setDraftSlugWarning(null);
      return;
    }
    final taken = await Stores.shares.isSlugTaken(input);
    if (!mounted) return;
    if (taken &&
        (widget.editShare == null || widget.editShare!.slug != input)) {
      _store.setDraftSlugWarning('This slug is already taken.');
    } else {
      _store.setDraftSlugWarning(null);
    }
  }

  bool _canSubmit() {
    return _store.draftLabel.text.trim().isNotEmpty &&
        _store.draftSlug.text.trim().isNotEmpty &&
        _store.draftSlugWarning == null;
  }

  /// The exact API request the current form would issue — drives the live
  /// developer preview (create vs update), mirroring [_submit].
  ApiRequestSpec _buildSpec() {
    if (widget.editShare != null) {
      final updates = <String, dynamic>{
        'label': _store.draftLabel.text.trim(),
        'slug': _store.draftSlug.text.trim(),
        'maxViews': int.tryParse(_store.draftMaxViews.text) ?? 0,
        if (_store.draftPassword.text.isNotEmpty)
          'password': _store.draftPassword.text,
        'expiresAt': _store.draftExpiresAt?.toIso8601String() ?? '',
        'identity': _store.draftIdentityId ?? '',
        'requireHandshake': _store.draftRequireHandshake,
      };
      return Stores.shares.updateShareSpec(widget.editShare!.id, updates);
    }
    return Stores.shares.createShareSpec(
      slug: _store.draftSlug.text.trim(),
      label: _store.draftLabel.text.trim(),
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: widget.initialShare?.sections ?? const [],
      records: widget.initialShare?.records ?? const [],
      password: _store.draftPassword.text.isNotEmpty
          ? _store.draftPassword.text
          : null,
      maxViews: int.tryParse(_store.draftMaxViews.text),
      expiresAt: _store.draftExpiresAt,
      identityId: _store.draftIdentityId,
      requireHandshake: _store.draftRequireHandshake,
    );
  }

  Future<bool> _submit() async {
    if (widget.editShare != null) {
      final updates = <String, dynamic>{
        'label': _store.draftLabel.text.trim(),
        'slug': _store.draftSlug.text.trim(),
        'maxViews': int.tryParse(_store.draftMaxViews.text) ?? 0,
        'identity': _store.draftIdentityId ?? '',
        'requireHandshake': _store.draftRequireHandshake,
      };
      if (_store.draftPassword.text.isNotEmpty) {
        updates['password'] = _store.draftPassword.text;
      }
      if (_store.draftExpiresAt != null) {
        updates['expiresAt'] = _store.draftExpiresAt!.toIso8601String();
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
      slug: _store.draftSlug.text.trim(),
      label: _store.draftLabel.text.trim(),
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: widget.initialShare?.sections ?? [],
      records: widget.initialShare?.records ?? [],
      password: _store.draftPassword.text.isNotEmpty
          ? _store.draftPassword.text
          : null,
      maxViews: int.tryParse(_store.draftMaxViews.text),
      expiresAt: _store.draftExpiresAt,
      identityId: _store.draftIdentityId,
      requireHandshake: _store.draftRequireHandshake,
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
    _store.setSubmittingShare(true);
    final ok = await _submit();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _store.setSubmittingShare(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final isEdit = widget.editShare != null;
    final isDup = widget.initialShare != null;
    final title = isEdit
        ? 'Edit share'
        : (isDup ? 'Duplicate share' : 'New share link');
    final completeLabel = isEdit
        ? 'Save changes'
        : (isDup ? 'Duplicate Share' : 'Create Share');

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
                    onTap: _store.isSubmittingShare
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    label: completeLabel,
                    busy: _store.isSubmittingShare,
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

  Widget _buildLabelRow() {
    final v = _store.draftLabel.text.trim();
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
          controller: _store.draftLabel,
          hint: 'Vendor Onboarding',
        );
      },
    );
  }

  Widget _buildSlugRow() {
    final slug = _store.draftSlug.text.trim();
    return AppFormRow(
      icon: AppIcons.link,
      label: 'URL slug',
      valueText: slug.isEmpty ? 'Required' : (_store.draftSlugWarning ?? slug),
      isPlaceholder: slug.isEmpty,
      isError: slug.isEmpty || _store.draftSlugWarning != null,
      onTap: _editSlug,
    );
  }

  Widget _buildMaxViewsRow() {
    final v = _store.draftMaxViews.text.trim();
    return AppFormRow(
      icon: AppIcons.collection,
      label: 'Maximum views',
      valueText: v.isEmpty ? 'Unlimited' : v,
      isPlaceholder: v.isEmpty,
      onClear: _store.draftMaxViews.clear,
      onTap: () async {
        await showAppEditSheet(
          context: context,
          title: 'Maximum views',
          description: 'Auto-expire the link after this many views.',
          controller: _store.draftMaxViews,
          hint: 'e.g. 5 — leave blank for unlimited',
          keyboardType: TextInputType.number,
        );
      },
    );
  }

  Widget _buildExpiryRow() {
    return AppFormRow(
      icon: AppIcons.clock,
      label: 'Expiration date',
      valueText: _store.draftExpiresAt == null
          ? 'Never'
          : _formatDate(_store.draftExpiresAt!),
      isPlaceholder: _store.draftExpiresAt == null,
      onClear: () => _store.setDraftExpiry(null),
      onTap: _pickExpiry,
    );
  }

  Widget _buildPasswordRow() {
    final has = _store.draftPassword.text.isNotEmpty;
    return AppFormRow(
      icon: AppIcons.lock,
      label: 'Password',
      valueText: has ? '••••••••' : 'Not set',
      isPlaceholder: !has,
      onClear: _store.draftPassword.clear,
      onTap: () async {
        await showAppEditSheet(
          context: context,
          title: 'Password',
          description: 'Recipients must enter this before viewing the share.',
          controller: _store.draftPassword,
          hint: 'Leave blank for no password',
          passwordToggle: true,
        );
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
            selectedId: _store.draftIdentityId,
            allowNone: true,
            onChanged: _store.setDraftIdentity,
          ),
          AppSpacing.gapXxs,
          AppFormToggleRow(
            label: 'Require a verified viewer',
            subtitle:
                'Viewers must prove control of a cryptographic identity '
                '(handshake) before the data is revealed.',
            value: _store.draftRequireHandshake,
            onChanged: _store.setDraftHandshake,
            inset: false,
          ),
        ],
      ),
    );
  }

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
                          controller: _store.draftSlug,
                          hint: 'vendor-onboarding-2024',
                          autofocus: true,
                          inputFormatters: [SlugInputFormatter()],
                          onChanged: (v) async {
                            await _validateSlug(v);
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
                          _store.draftSlug.text = s;
                          await _validateSlug(s);
                        },
                      ),
                    ],
                  ),
                  if (_store.draftSlugWarning != null) ...[
                    AppSpacing.gapSm,
                    Text(_store.draftSlugWarning!).small,
                  ],
                  AppSpacing.gapLg,
                  AppButton(
                    label: 'Done',
                    onTap:
                        (_store.draftSlug.text.trim().isNotEmpty &&
                            _store.draftSlugWarning == null)
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

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
