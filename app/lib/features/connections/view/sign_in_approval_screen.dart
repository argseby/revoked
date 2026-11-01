import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/connections/sign_in_approval.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for a `revoked://signin?…` link: a service asks to sign its user in.
/// The request is opened on the server the app is signed into, and the person
/// decides here — who is asking, what it learns, which entries it may read.
/// An approval needs the device unlocked and is signed with the identity key
/// on this device. Nothing about it happens in a browser. The answer goes to
/// the service through the default browser — or, when the service waits for
/// it on the page that asked, straight from the app, and the person compares
/// the check code that page shows.
class SignInApprovalScreen extends StatefulWidget {
  /// Null when the link was malformed; the screen then says so.
  final SignInRequest? request;

  const SignInApprovalScreen({super.key, required this.request});

  @override
  State<SignInApprovalScreen> createState() => _SignInApprovalScreenState();
}

enum _Stage { opening, consent, approved, declined, refused, failed }

class _SignInApprovalScreenState extends State<SignInApprovalScreen> {
  final _stage = Local<_Stage>(_Stage.opening);
  final _consent = Local<SignInConsent?>(null);
  final _busy = Local<bool>(false);
  final _error = Local<String?>(null);
  final _scopes = Local<Set<String>>({});
  final _links = Local<Map<String, String>>({});

  /// The name picked for this service: an option's token, [_newName], or
  /// empty for none.
  final _nameChoice = Local<String>('');

  @override
  void initState() {
    super.initState();
    if (widget.request != null) _open();
  }

  String _message(Object e) => switch (e) {
    ApiException(:final message) when message.isNotEmpty => message,
    SignInApprovalException(:final message) => message,
    _ => 'Something went wrong. Please try again.',
  };

  Future<void> _open() async {
    try {
      final opened = await Stores.signInApproval.open(widget.request!);
      if (!mounted) return;
      final consent = opened.consent;
      if (consent == null) {
        // The server refused the request; the service hears why.
        _stage.value = _Stage.refused;
        if (opened.refusal != null) await _answerService(opened.refusal!);
        return;
      }
      // The name has its own select, and starts where the person left it.
      _nameChoice.value = consent.nameSelected;
      _scopes.value = {
        for (final s in consent.scopes)
          if (s.scope != _profile) s.scope,
      };
      _links.value = {for (final l in consent.links) l.key: l.match?.id ?? ''};
      _consent.value = consent;
      _stage.value = _Stage.consent;
    } catch (e) {
      if (!mounted) return;
      _error.value = _message(e);
      _stage.value = _Stage.failed;
    }
  }

  Future<void> _decide(bool approve) async {
    final consent = _consent.value!;
    _busy.value = true;
    _error.value = null;
    try {
      final redirect = await Stores.signInApproval.decide(
        consent,
        approve: approve,
        scopes: {
          ..._scopes.value,
          if (_typingName || _pickedName != null) _profile,
        },
        links: _links.value,
        name: _pickedName,
        newName: _typingName ? Stores.signInApproval.nameDraft.text.trim() : '',
      );
      if (!mounted) return;
      _stage.value = approve ? _Stage.approved : _Stage.declined;
      await _answerService(redirect);
    } catch (e) {
      if (!mounted) return;
      _error.value = _message(e);
      // A refused approval spent the ticket; the service has to ask again.
      if (e is ApiException) _stage.value = _Stage.failed;
    } finally {
      if (mounted) _busy.value = false;
    }
  }

  /// Gives the service its answer. A service that waits on the page that
  /// asked gets it straight from the app. Any other — or a waiting one that
  /// cannot be reached from here — gets it through the default browser,
  /// where an ordinary web sign-in expects it.
  Future<void> _answerService(String redirect) async {
    if (widget.request!.background &&
        await Stores.signInApproval.deliver(redirect)) {
      return;
    }
    final uri = Uri.tryParse(redirect);
    if (uri == null) return;
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final r = widget.request;
    final consenting = _stage.value == _Stage.consent;
    return AppFlowScaffold(
      title: consenting
          ? 'Sign in to ${_consent.value!.clientHost}'
          : 'Sign in with Revoked',
      subtitle: r == null ? null : 'Requested by ${r.clientHost}',
      closeLabel: consenting ? 'Decline and go back' : 'Back to the app',
      onClose: () => consenting && !_busy.value
          ? _decide(false)
          : context.go(AppRoutes.overview),
      bottomBar: consenting ? _decision() : null,
      body: r == null
          ? _invalid(context)
          : switch (_stage.value) {
              _Stage.opening => const Center(child: AppSpinner(large: true)),
              _Stage.consent => _consentBody(_consent.value!),
              _Stage.approved => _finished(
                context,
                icon: AppIcons.checkCircle,
                accent: Theme.of(context).colorScheme.success,
                title: 'You’re signed in to ${r.clientHost}',
                message:
                    '${r.background ? 'Go back to the ${r.clientHost} page you started on. It carries on from there.' : '${r.clientHost} carries on in your browser.'} '
                    '${_nameIsEntry || _links.value.values.any((id) => id.isNotEmpty) ? 'What you shared stays in your vault. To stop sharing, go to Settings → Connected tools.' : 'You’ll find this sign-in under Settings → Connected tools.'}',
              ),
              _Stage.declined => _finished(
                context,
                icon: AppIcons.x,
                accent: Theme.of(context).colorScheme.onSurfaceVariant,
                title: 'Sign-in declined',
                message: 'Nothing was shared with ${r.clientHost}.',
              ),
              _Stage.refused => _finished(
                context,
                icon: AppIcons.exclamationTriangle,
                accent: Theme.of(context).colorScheme.error,
                title: 'This sign-in can’t continue',
                message:
                    '${r.clientHost} asked for something Revoked doesn’t '
                    'allow. Nothing was shared.',
              ),
              _Stage.failed => _finished(
                context,
                icon: AppIcons.exclamationTriangle,
                accent: Theme.of(context).colorScheme.error,
                title: 'Signing in didn’t work',
                message:
                    '${_error.value ?? ''} Start signing in again on '
                    '${r.clientHost}.',
              ),
            },
    );
  }

  Widget _invalid(BuildContext context) {
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: 'This link doesn’t work',
      message:
          'Revoked can’t continue this sign-in. Start again on the '
          'service.',
      actions: [
        AppButton(
          label: 'Back to the app',
          icon: AppIcons.arrowLeft,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.overview),
        ),
      ],
    );
  }

  Widget _finished(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String message,
  }) {
    return AppStatusMessage(
      icon: icon,
      accent: accent,
      title: title,
      message: message,
      actions: [
        AppButton(
          label: 'Done',
          icon: AppIcons.check,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.overview),
        ),
      ],
    );
  }

  static const _profile = 'profile';

  /// In the name select: type a new one instead of picking one.
  static const _newName = 'new';

  SignInNameOption? get _pickedName {
    for (final o in _consent.value?.nameOptions ?? const <SignInNameOption>[]) {
      if (o.token == _nameChoice.value) return o;
    }
    return null;
  }

  bool get _typingName => _nameChoice.value == _newName;

  /// Whether what the name comes from stays readable in the vault.
  bool get _nameIsEntry =>
      _typingName || _pickedName?.kind == SignInNameOption.fromRecord;

  String _nameLabel(SignInNameOption o) => o.kind == SignInNameOption.fromRecord
      ? '${o.label.isEmpty ? o.key : o.label} — ${o.value}'
      : '${o.value} — Your identity';

  /// "Your name": a service gets the name picked for it here, and nothing
  /// until one is picked.
  Widget _nameRow(SignInConsent c) {
    final busy = _busy.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Your name'),
        AppSpacing.gapSm,
        AppSelect<String>(
          value: _nameChoice.value,
          onChanged: busy ? null : (v) => _nameChoice.value = v ?? '',
          items: [
            const AppSelectItem('', Text('Don’t share')),
            for (final o in c.nameOptions)
              AppSelectItem(
                o.token,
                Text(_nameLabel(o), overflow: TextOverflow.ellipsis),
              ),
            const AppSelectItem(_newName, Text('Type a new name')),
          ],
        ),
        if (_typingName) ...[
          AppSpacing.gapSm,
          AppTextField(
            controller: Stores.signInApproval.nameDraft,
            hint: 'Your name on ${c.clientHost}',
            enabled: !busy,
          ),
        ],
        if (_nameIsEntry) ...[
          AppSpacing.gapSm,
          Text(
            'Saved in your vault. Change it there, and ${c.clientHost} can '
            'pick up the new name.',
          ).small.muted,
        ],
      ],
    );
  }

  Widget _consentBody(SignInConsent c) {
    final host = c.clientHost;
    const quiet = SizedBox.shrink();
    Widget pad(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: child,
    );
    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        // The page that asked may be on another screen: the code shows it is
        // the person's own, and not one someone else put in front of them.
        if (widget.request!.background)
          ToolCheckCode(name: host, challenge: widget.request!.challenge),
        AppListGroup(
          title: 'Who is asking',
          trailing: quiet,
          footer: const Text(
            'Check the address. Only continue if you recognise it and just '
            'started signing in there.',
          ),
          children: [
            AppDetailRow(icon: AppIcons.globe, label: 'Address', value: host),
            AppDetailRow(
              icon: AppIcons.person,
              label: 'Your account',
              value: c.accountEmail,
            ),
          ],
        ),
        AppListGroup(
          title: '$host learns',
          trailing: quiet,
          children: [
            pad(
              AppCheckRow(
                label: 'That it is you',
                subtitle: 'Through an ID made just for $host.',
                value: true,
                onChanged: null,
              ),
            ),
            for (final s in c.scopes)
              if (s.scope == _profile)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _nameRow(c),
                )
              else
                pad(
                  AppCheckRow(
                    label: signInScopeLabels[s.scope] ?? s.scope,
                    subtitle: s.value.isEmpty ? null : s.value,
                    value: _scopes.value.contains(s.scope),
                    onChanged: _busy.value
                        ? null
                        : (on) => _scopes.value = on
                              ? {..._scopes.value, s.scope}
                              : ({..._scopes.value}..remove(s.scope)),
                  ),
                ),
          ],
        ),
        if (c.links.isNotEmpty)
          AppListGroup(
            title: '$host may read',
            trailing: quiet,
            footer: Text(
              'Shared entries stay in your vault. $host reads them from '
              'there until you revoke them.',
            ),
            children: [
              for (final l in c.links)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Your entry “${l.key}”'),
                      AppSpacing.gapSm,
                      AppSelect<String>(
                        value: _links.value[l.key] ?? '',
                        onChanged: _busy.value
                            ? null
                            : (v) => _links.value = {
                                ..._links.value,
                                l.key: v ?? '',
                              },
                        items: [
                          const AppSelectItem('', Text('Don’t share')),
                          for (final o in l.options)
                            AppSelectItem(
                              o.id,
                              Text(
                                [
                                  o.label.isEmpty ? o.key : o.label,
                                  if (o.preview.isNotEmpty) o.preview,
                                ].join(' — '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (_error.value != null)
          AppAlert(destructive: true, content: Text(_error.value!)),
      ],
    );
  }

  Widget _decision() {
    final busy = _busy.value;
    final unnamed =
        _typingName && Stores.signInApproval.nameDraft.text.trim().isEmpty;
    return AppActionBar(
      note: const Text(
        'You confirm on this device. Nothing is shared until you do.',
      ).muted.small,
      children: [
        AppButton(
          label: 'Decline',
          icon: AppIcons.x,
          style: AppButtonStyle.accent,
          onTap: busy ? null : () => _decide(false),
        ),
        AppButton(
          label: 'Sign in',
          icon: AppIcons.check,
          busy: busy,
          onTap: busy || unnamed ? null : () => _decide(true),
        ),
      ],
    );
  }
}
