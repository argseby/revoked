import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/features/shares/view/share_contents_picker.dart';

/// Opens the link drawer. A new link can start with [records] and
/// [sections] already picked — "Share" on a record passes that record.
void openShareCreateSheet({
  required BuildContext context,
  Link? initialShare,
  Link? editShare,
  List<String> records = const [],
  List<String> sections = const [],
}) {
  Stores.shares.clearError();
  showAppSheet(
    context: context,
    builder: (_) => _ShareCreateForm(
      parentContext: context,
      initialShare: initialShare,
      editShare: editShare,
      records: records,
      sections: sections,
    ),
  );
}

/// How long a new link lives unless the owner says otherwise. A link that
/// never expires is the one forgotten about, so "never" is a choice, not
/// the default.
const _defaultLifetime = Duration(days: 30);

class _ShareCreateForm extends StatefulWidget {
  final BuildContext parentContext;
  final Link? initialShare;
  final Link? editShare;
  final List<String> records;
  final List<String> sections;

  const _ShareCreateForm({
    required this.parentContext,
    this.initialShare,
    this.editShare,
    this.records = const [],
    this.sections = const [],
  });

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
          : (link == null ? DateTime.now().add(_defaultLifetime) : null),
      records: widget.initialShare?.records ?? widget.records,
      sections: widget.initialShare?.sections ?? widget.sections,
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
      // A share watermarked without its own text stamps its label, so that
      // is what the row shows and what stays stamped on save.
      watermarkText: switch (link) {
        final l? when l.watermark =>
          l.watermarkText.isNotEmpty ? l.watermarkText : l.label,
        _ => '',
      },
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
      _store.setDraftSlugWarning('This address is already taken.');
    } else {
      _store.setDraftSlugWarning(null);
    }
  }

  bool get _isEdit => widget.editShare != null;

  /// The link's name: the one typed, or for a new link what it shares.
  String get _effectiveLabel {
    final typed = _store.draftLabel.text.trim();
    if (typed.isNotEmpty || _isEdit) return typed;
    return shareContentsSummary();
  }

  bool get _hasContents =>
      _store.draftRecords.isNotEmpty || _store.draftSections.isNotEmpty;

  bool _canSubmit() {
    return _effectiveLabel.isNotEmpty &&
        (_isEdit || _hasContents) &&
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
        'watermark': _store.draftWatermark,
        'watermarkText': _store.draftWatermarkText.text.trim(),
      };
      return Stores.shares.updateShareSpec(widget.editShare!.id, updates);
    }
    return Stores.shares.createShareSpec(
      slug: _store.draftSlug.text.trim(),
      label: _effectiveLabel,
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: _store.draftSections.toList(),
      records: _store.draftRecords.toList(),
      password: _store.draftPassword.text.isNotEmpty
          ? _store.draftPassword.text
          : null,
      maxViews: int.tryParse(_store.draftMaxViews.text),
      expiresAt: _store.draftExpiresAt,
      identityId: _store.draftIdentityId,
      requireHandshake: _store.draftRequireHandshake,
      watermark: _store.draftWatermark,
      watermarkText: _store.draftWatermarkText.text.trim(),
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
        'watermark': _store.draftWatermark,
        'watermarkText': _store.draftWatermarkText.text.trim(),
      };
      if (_store.draftPassword.text.isNotEmpty) {
        updates['password'] = _store.draftPassword.text;
      } else if (_store.draftRemovePassword) {
        updates['password'] = '';
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
          'The link could not be updated.',
          subtitle: Stores.shares.errorMessage,
        );
        return false;
      }
      AppToast.success(context, 'Link updated');
      return true;
    }

    final ok = await Stores.shares.createShare(
      slug: _store.draftSlug.text.trim(),
      label: _effectiveLabel,
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: _store.draftSections.toList(),
      records: _store.draftRecords.toList(),
      password: _store.draftPassword.text.isNotEmpty
          ? _store.draftPassword.text
          : null,
      maxViews: int.tryParse(_store.draftMaxViews.text),
      expiresAt: _store.draftExpiresAt,
      identityId: _store.draftIdentityId,
      requireHandshake: _store.draftRequireHandshake,
      watermark: _store.draftWatermark,
      watermarkText: _store.draftWatermarkText.text.trim(),
    );
    if (!mounted) return false;
    if (!ok) {
      AppToast.error(
        context,
        'The link could not be created.',
        subtitle: Stores.shares.errorMessage,
      );
      return false;
    }
    AppToast.success(
      context,
      widget.initialShare != null ? 'Link duplicated' : 'Link created',
    );
    return true;
  }

  Future<void> _onSubmit() async {
    _store.setSubmittingShare(true);
    final ok = await _submit();
    if (!mounted) return;
    if (!ok) {
      _store.setSubmittingShare(false);
      return;
    }
    Navigator.of(context).pop();
    // A new link is made to be sent: hand it over at once instead of leaving
    // the owner to find it in the list.
    final parent = widget.parentContext;
    if (!_isEdit && parent.mounted && Stores.shares.shares.isNotEmpty) {
      final created = Stores.shares.shares.first;
      await showShareSheet(
        context: parent,
        slug: created.slug,
        title: created.label,
        isRequest: false,
      );
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
        ? 'Edit link'
        : (isDup ? 'Duplicate link' : 'New link');
    final completeLabel = isEdit
        ? 'Save changes'
        : (isDup ? 'Duplicate link' : 'Create link');
    final completeIcon = isEdit
        ? AppIcons.check
        : (isDup ? AppIcons.copy : AppIcons.plus);

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
                  'Recipients see the latest version until the link expires '
                  'or is revoked.',
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
                    if (!isEdit) const ShareContentsRow(),
                    _buildLabelRow(),
                    _buildExpiryRow(),
                    _buildPasswordRow(),

                    AppFormAdvanced(
                      summary:
                          'Address, view limit, watermark, signature and API',
                      initiallyOpen: _store.draftSlugWarning != null,
                      children: [
                        _buildSlugRow(),
                        _buildMaxViewsRow(),
                        _buildWatermarkRow(),
                        const AppFormSectionHeader('Verification'),
                        _buildVerificationSection(),
                        ApiPreviewSection(
                          spec: _buildSpec(),
                          title:
                              'API request · ${isEdit ? 'update' : 'create'}',
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
                  style: AppButtonStyle.accent,
                  onTap: _store.isSubmittingShare
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    icon: completeIcon,
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
    final fallback = _effectiveLabel;
    return AppFormField(
      label: 'Label',
      explanation: 'The title shown to the recipient.',
      note: _store.draftLabel.text.trim().isEmpty && fallback.isNotEmpty
          ? 'Defaults to $fallback.'
          : null,
      child: AppTextField(
        controller: _store.draftLabel,
        hint: fallback.isEmpty ? 'Vendor Onboarding' : fallback,
      ),
    );
  }

  Widget _buildSlugRow() => AppFormField(
    label: 'Link address',
    explanation: 'The last part of the link\'s web address.',
    error: _store.draftSlugWarning,
    child: AppTextField(
      controller: _store.draftSlug,
      hint: 'vendor-onboarding-2024',
      mono: true,
      inputFormatters: [SlugInputFormatter()],
      onChanged: _validateSlug,
      trailing: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: AppButton(
          icon: AppIcons.arrowRepeat,
          style: AppButtonStyle.ghost,
          size: AppButtonSize.small,
          tooltip: 'Generate a random address',
          showTooltip: false,
          onTap: () async {
            final s = _generateRandomSlug();
            _store.draftSlug.text = s;
            await _validateSlug(s);
          },
        ),
      ),
    ),
  );

  Widget _buildWatermarkRow() {
    final tag = widget.editShare?.watermarkTag;
    return AppFormField(
      label: 'Watermark',
      explanation:
          'Every image and PDF gets this text, the date and the link '
          'tag${tag == null ? '' : ' (#$tag)'}. Other file types cannot be '
          'opened. Empty means no watermark.',
      child: AppTextField(
        controller: _store.draftWatermarkText,
        hint: 'Nur für Wohnungsbewerbung Musterstr. 5',
      ),
    );
  }

  Widget _buildMaxViewsRow() => AppFormField(
    label: 'Maximum views',
    explanation: 'The link stops working after this many views.',
    child: AppTextField(
      controller: _store.draftMaxViews,
      hint: 'Unlimited',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    ),
  );

  Widget _buildExpiryRow() {
    return AppFormField(
      label: 'Expiration date',
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

  Widget _buildPasswordRow() {
    final typed = _store.draftPassword.text.isNotEmpty;
    final stored = widget.editShare?.hasPassword ?? false;
    final removing = _store.draftRemovePassword;
    return AppFormField(
      label: 'Password',
      explanation: 'Required to open the link.',
      error: removing ? 'Removed on save.' : null,
      note: !stored
          ? null
          : typed
          ? 'Replaces the current one.'
          : 'Empty keeps the current one.',
      action: !stored
          ? null
          : removing
          ? AppButton(
              icon: AppIcons.lock,
              label: 'Keep the password',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => _store.setDraftRemovePassword(false),
            )
          : AppButton(
              icon: AppIcons.trash,
              label: 'Remove the password',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () {
                _store.draftPassword.clear();
                _store.setDraftRemovePassword(true);
              },
            ),
      child: AppTextField(
        controller: _store.draftPassword,
        hint: stored ? 'Unchanged when blank' : 'No password when blank',
        passwordToggle: true,
        onChanged: (v) {
          if (v.isNotEmpty) _store.setDraftRemovePassword(false);
        },
      ),
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
            'A signature lets recipients verify the link\'s origin.',
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
                'Viewers must prove a verified identity before any content '
                'is shown.',
            value: _store.draftRequireHandshake,
            onChanged: _store.setDraftHandshake,
            inset: false,
          ),
        ],
      ),
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
}
