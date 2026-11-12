import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';
import 'package:revoked_app/features/connections/sign_in_approval.dart';
import 'package:revoked_app/features/connections/view/day_label.dart';
import 'package:revoked_app/features/connections/view/sign_in_picker.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';

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

enum _Stage { opening, consent, approved, declined, refused, paused, failed }

class _SignInApprovalScreenState extends State<SignInApprovalScreen> {
  final _stage = Local<_Stage>(_Stage.opening);
  final _consent = Local<SignInConsent?>(null);
  final _busy = Local<bool>(false);
  final _error = Local<String?>(null);
  final _scopes = Local<Set<String>>({});
  final _links = Local<Map<String, String>>({});

  /// The name picked for this service: an option's token,
  /// [SignInPicker.newValue], or empty for none.
  final _nameChoice = Local<String>('');

  /// What each picker held before its switch was turned off.
  final Map<String, String> _lastPicks = {};

  /// The person's row for a service they paused, to offer activating it.
  final _pausedService = Local<String?>(null);

  @override
  void initState() {
    super.initState();
    if (widget.request != null) _open();
  }

  String _message(Object e) => switch (e) {
    ApiException(:final message) when message.isNotEmpty => message,
    SignInApprovalException(:final message) => message,
    _ => 'The request could not be completed.',
  };

  Future<void> _open() async {
    final settings = Stores.settings;
    if (settings.workspaces.isEmpty) {
      settings.loadWorkspaces(Stores.auth.userId);
    }
    try {
      final opened = await Stores.signInApproval.open(widget.request!);
      if (!mounted) return;
      final consent = opened.consent;
      if (consent == null) {
        // The server refused the request; the service hears why.
        _pausedService.value = opened.paused;
        _stage.value = opened.paused == null ? _Stage.refused : _Stage.paused;
        if (opened.refusal != null) await _answerService(opened.refusal!);
        return;
      }
      _lastPicks.clear();
      // The name has its own picker, and starts where the person left it.
      _nameChoice.value = consent.nameSelected;
      // Coming back under a new ID, anything shared could give it away, so
      // nothing starts out shared.
      _scopes.value = consent.newId
          ? {}
          : {
              for (final s in consent.scopes)
                if (s.scope != _profile) s.scope,
            };
      _links.value = {
        for (final l in consent.links)
          l.key: consent.newId ? '' : l.match?.id ?? '',
      };
      _consent.value = consent;
      _stage.value = _Stage.consent;
    } catch (e) {
      if (!mounted) return;
      _error.value = _message(e);
      _stage.value = _Stage.failed;
    }
  }

  /// Entries belong to a workspace, so what the service can be given changes
  /// with it, and the request is opened again to find out. The ticket from
  /// before simply expires.
  Future<void> _switchWorkspace(String workspaceId) async {
    final auth = Stores.auth;
    if (_busy.value || workspaceId == auth.activeWorkspace) return;
    _busy.value = true;
    _error.value = null;
    final switched = await Stores.workspaceContext.switchTo(
      userId: auth.userId,
      workspaceId: workspaceId,
      waitForReload: false,
    );
    if (!mounted) return;
    if (switched) {
      await _open();
    } else {
      _error.value =
          Stores.settings.errorMessage ??
          'The workspace could not be switched.';
    }
    if (mounted) _busy.value = false;
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
        links: {
          for (final e in _links.value.entries)
            if (e.value != SignInPicker.newValue) e.key: e.value,
        },
        name: _pickedName,
        newName: _typingName ? Stores.signInApproval.nameDraft.text.trim() : '',
        newValues: {
          for (final e in _links.value.entries)
            if (e.value == SignInPicker.newValue)
              e.key: Stores.signInApproval.valueDraft(e.key).text.trim(),
        },
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
      feature: Feature.tools,
      body: r == null
          ? _invalid(context)
          : switch (_stage.value) {
              _Stage.opening => const Center(child: AppSpinner(large: true)),
              _Stage.consent => _consentBody(_consent.value!),
              _Stage.approved => _finished(
                context,
                icon: AppIcons.checkCircle,
                accent: Theme.of(context).colorScheme.success,
                title: 'Signed in to ${r.clientHost}',
                message:
                    '${r.background ? 'The sign-in continues on the ${r.clientHost} page where it started.' : '${r.clientHost} continues in the browser.'} '
                    '${_nameIsEntry || _links.value.values.any((id) => id.isNotEmpty) ? 'Shared data remains in the vault. Sharing can be ended under Settings → Connected tools.' : 'This sign-in is listed under Settings → Connected tools.'}',
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
                title: 'This sign-in cannot continue',
                message:
                    '${r.clientHost} requested something Revoked does not '
                    'allow. Nothing was shared.',
              ),
              _Stage.paused => AppStatusMessage(
                icon: AppIcons.pause,
                accent: Theme.of(context).colorScheme.onSurfaceVariant,
                title: '${r.clientHost} is paused',
                message:
                    'Nothing was shared. Signing in requires activating it.',
                actions: [
                  AppButton(
                    label: 'Open service',
                    icon: AppIcons.globe,
                    style: AppButtonStyle.accent,
                    onTap: () => context.go(
                      AppRoutes.signInServiceFor(_pausedService.value!),
                    ),
                  ),
                  AppButton(
                    label: 'Done',
                    icon: AppIcons.check,
                    style: AppButtonStyle.accent,
                    onTap: () => context.go(AppRoutes.overview),
                  ),
                ],
              ),
              _Stage.failed => _finished(
                context,
                icon: AppIcons.exclamationTriangle,
                accent: Theme.of(context).colorScheme.error,
                title: 'Sign-in failed',
                message:
                    '${_error.value ?? ''} The sign-in must be restarted on '
                    '${r.clientHost}.',
              ),
            },
    );
  }

  Widget _invalid(BuildContext context) {
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: 'Invalid link',
      message:
          'This sign-in cannot continue. It must be restarted on the '
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

  SignInNameOption? get _pickedName {
    for (final o in _consent.value?.nameOptions ?? const <SignInNameOption>[]) {
      if (o.token == _nameChoice.value) return o;
    }
    return null;
  }

  bool get _typingName => _nameChoice.value == SignInPicker.newValue;

  /// Whether what the name comes from stays readable in the vault.
  bool get _nameIsEntry =>
      _typingName || _pickedName?.kind == SignInNameOption.fromRecord;

  String? get _workspaceName {
    final spaces = Stores.settings.workspaces;
    if (spaces.length < 2) return null;
    for (final w in spaces) {
      if (w.id == Stores.auth.activeWorkspace) return w.name;
    }
    return null;
  }

  List<SignInChoice> _nameChoices(SignInConsent c) => [
    for (final o in c.nameOptions)
      SignInChoice(
        id: o.token,
        recordId: o.kind == SignInNameOption.fromRecord ? o.id : null,
        value: o.value,
        title: o.kind == SignInNameOption.fromRecord
            ? (o.label.isEmpty ? o.key : o.label)
            : 'Your identity',
        key: o.key,
        shared: o.shared,
        madeFor: o.madeFor,
      ),
  ];

  List<SignInChoice> _linkChoices(SignInLinkAsk l) => [
    for (final o in l.options)
      SignInChoice(
        id: o.id,
        recordId: o.id,
        value: o.preview,
        title: o.label.isEmpty ? o.key : o.label,
        key: o.key,
        shared: o.shared,
        madeFor: o.madeFor,
      ),
  ];

  /// Remembers what a picker held when it's turned off, for turning it back on.
  void _pick(
    String slot,
    String current,
    String next,
    void Function(String) set,
  ) {
    if (current.isNotEmpty) _lastPicks[slot] = current;
    set(next);
  }

  /// A service gets the name picked for it here, and nothing until one is.
  Widget _nameRow(SignInConsent c) {
    const slot = 'profile';
    return SignInPicker(
      heading: 'Your name',
      preview: 'Shown to ${c.clientHost} as',
      nothing: 'No name',
      newHint: 'New name',
      askedKey: 'name',
      allFit: true,
      selected: _nameChoice.value,
      lastPick: _lastPicks[slot],
      choices: _nameChoices(c),
      draft: Stores.signInApproval.nameDraft,
      maxLength: SignInApproval.maxNameLength,
      isNew: c.isNewScope(_profile),
      workspace: _workspaceName,
      busy: _busy.value,
      note: _nameIsEntry
          ? 'Stored in the vault. Changes made there reach '
                '${c.clientHost}.'
          : null,
      onChanged: (v) => _pick(slot, _nameChoice.value, v, (next) {
        _nameChoice.value = next;
      }),
      onSwitchWorkspace: _switchWorkspace,
      browse: () =>
          _browseData(_nameChoices(_consent.value!), _nameChoice.value),
    );
  }

  /// One key the service asked for: an entry to share under it, a new value
  /// saved in the vault, or nothing.
  Widget _linkRow(SignInConsent c, SignInLinkAsk l) {
    final choice = _links.value[l.key] ?? '';
    SignInLinkOption? picked;
    for (final o in l.options) {
      if (o.id == choice) picked = o;
    }
    final section = 'Sign-in · ${c.clientHost}';
    return SignInPicker(
      heading: 'Your ${l.key.replaceAll('_', ' ')}',
      preview: 'Shown to ${c.clientHost}',
      nothing: 'Nothing',
      newHint: 'New value',
      askedKey: l.key,
      selected: choice,
      lastPick: _lastPicks[l.key],
      choices: _linkChoices(l),
      draft: Stores.signInApproval.valueDraft(l.key),
      workspace: _workspaceName,
      busy: _busy.value,
      note: choice == SignInPicker.newValue
          ? 'Stored in the vault under $section.'
          : l.match == null && picked != null && !picked.isFile
          ? 'An alias “${l.key}” is added to the vault under '
                '$section.'
          : null,
      onChanged: (v) => _pick(l.key, choice, v, (next) {
        _links.value = {..._links.value, l.key: next};
      }),
      onSwitchWorkspace: _switchWorkspace,
      browse: () {
        final asks = _consent.value!.links.where((a) => a.key == l.key);
        return _browseData(
          asks.isEmpty ? const [] : _linkChoices(asks.first),
          _links.value[l.key] ?? '',
        );
      },
    );
  }

  SignInBrowseData _browseData(List<SignInChoice> choices, String selected) =>
      SignInBrowseData(
        choices: choices,
        sections: _consent.value!.sections,
        selected: selected,
        busy: _busy.value,
      );

  Widget _consentBody(SignInConsent c) {
    final host = c.clientHost;
    const quiet = SizedBox.shrink();
    final asksName = c.scopes.any((s) => s.scope == _profile);
    final chip = WorkspaceChip(onSwitch: _switchWorkspace);
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
        // A disconnected service has its own note below, saying the same.
        if (c.returning case final back? when c.disconnectedAt == null)
          AppAlert(
            leading: const Icon(AppIcons.info),
            title: Text("You've signed in to $host before"),
            content: Text(
              'Last time on ${dayLabel(back.lastAt)}. It keeps the same ID '
              'for you and gets what you allow below.',
            ).small,
          ),
        if (c.disconnectedAt != null)
          AppAlert(
            leading: const Icon(AppIcons.info),
            content: Text(
              c.newId
                  ? '$host was disconnected on ${dayTimeLabel(c.disconnectedAt)}. It '
                        'sees this account as new. '
                        '${c.scopes.isEmpty && c.links.isEmpty ? '' : 'Shared data could still identify the account, so nothing is preselected.'}'
                  : '$host was disconnected on ${dayTimeLabel(c.disconnectedAt)}. '
                        'Signing in restores the previous account there.',
            ),
          ),
        AppListGroup(
          title: 'Requesting service',
          trailing: quiet,
          footer: const Text(
            'Continue only if the address is recognised and the sign-in was '
            'just started there.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.globe,
              label: 'Address',
              value: host,
              badge: WorksWithChip(origin: c.client),
            ),
            AppDetailRow(
              icon: AppIcons.person,
              label: 'Your account',
              value: c.accountEmail,
            ),
          ],
        ),
        AppListGroup(
          title: 'Disclosed to $host',
          trailing: c.links.isEmpty && asksName ? chip : quiet,
          children: [
            pad(
              AppCheckRow(
                label: 'Account identity',
                subtitle: 'Through an ID dedicated to $host',
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
                    badge: c.isNewScope(s.scope)
                        ? const AppBadge(label: 'New')
                        : null,
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
            title: 'Readable by $host',
            trailing: chip,
            footer: Text(
              'Shared entries remain in the vault. $host reads them there '
              'until revoked.',
            ),
            children: [
              for (final l in c.links)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _linkRow(c, l),
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
        (_typingName && Stores.signInApproval.nameDraft.text.trim().isEmpty) ||
        _links.value.entries.any(
          (e) =>
              e.value == SignInPicker.newValue &&
              Stores.signInApproval.valueDraft(e.key).text.trim().isEmpty,
        );
    return AppActionBar(
      note: const Text(
        'Nothing is shared until confirmed on this device.',
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
