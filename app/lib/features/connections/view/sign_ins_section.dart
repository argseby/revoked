import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/widgets/copy_actions.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_service.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/connections/view/day_label.dart';

/// The services this account signed in to, one row each; a row opens what the
/// service learned and what it may still read.
class SignInServicesGroup extends StatelessWidget {
  const SignInServicesGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.signIns;
    return Observer(
      builder: (_) {
        if (store.services.isEmpty) {
          final error = store.loadState.error;
          if (error == null) return const SizedBox.shrink();
          return AppLoadError(
            title: 'Sign-ins could not be loaded',
            message: error,
            onRetry: store.load,
          );
        }
        return AppListGroup(
          title: 'Signed-in services',
          footer: const Text(
            'Each service receives a dedicated ID and only the data approved '
            'for it.',
          ),
          children: [
            for (final s in store.services)
              AppListRow(
                icon: AppIcons.globe,
                title: s.host,
                subtitle: _summary(s),
                trailing: s.isDisconnected
                    ? const AppBadge(label: 'Disconnected')
                    : s.isPaused
                    ? const AppBadge(label: 'Paused')
                    : null,
                onTap: () => context.go(AppRoutes.signInServiceFor(s.id)),
              ),
          ],
        );
      },
    );
  }

  String _summary(SignInService s) {
    final link = Stores.signIns.links[s.link];
    return [
      if (!s.isDisconnected && link != null && link.status == 'active')
        'Entries shared',
      'last signed in ${dayLabel(s.lastSignInAt)}',
    ].join(' · ');
  }
}

/// One service: when you signed in, what it learned, the entries it may read,
/// and the way to pause or disconnect it. None of that signs you out there:
/// the service keeps its own login.
class SignInServicePage extends StatefulWidget {
  final String serviceId;

  const SignInServicePage({super.key, required this.serviceId});

  @override
  State<SignInServicePage> createState() => _SignInServicePageState();
}

class _SignInServicePageState extends State<SignInServicePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // Opened straight from a link, or back from revoking under Shares.
      Stores.signIns.loadIfDue();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  SignInService? get _service {
    for (final s in Stores.signIns.services) {
      if (s.id == widget.serviceId) return s;
    }
    return null;
  }

  void _back() => context.go(AppRoutes.connectedTools);

  Widget _title(BuildContext context) =>
      AppBarTitle(title: 'Connected tools', onBack: _back);

  Future<void> _revoke(SignInService service, Link link) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Revoke ${link.label}?',
      message:
          '${service.host} loses access to these entries. The link can no '
          'longer be opened.',
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.linkSlash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (!await Stores.signIns.revokeLink(link) && mounted) {
      AppToast.error(
        context,
        'The link could not be revoked',
        subtitle: Stores.signIns.errorMessage,
      );
    }
  }

  Future<void> _report(String title, bool ok) async {
    if (!ok && mounted) {
      AppToast.error(context, title, subtitle: Stores.signIns.errorMessage);
    }
  }

  Future<void> _disconnect(SignInService service) async {
    final store = Stores.signIns;
    runInAction(() => store.newIdOnDisconnect = false);
    final ok = await showAppDialog(
      context: context,
      title: 'Disconnect ${service.host}?',
      message:
          'The service loses access to shared entries. Signing in again '
          'requires new approval. Existing sessions there are not ended.',
      content: Observer(
        builder: (_) => AppCheckRow(
          label: 'Get a new ID',
          subtitle: _newIdWarning,
          value: store.newIdOnDisconnect,
          onChanged: (v) => runInAction(() => store.newIdOnDisconnect = v),
        ),
      ),
      confirmLabel: 'Disconnect',
      confirmIcon: AppIcons.linkSlash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _report(
      'The service could not be disconnected',
      await store.disconnect(service),
    );
  }

  Future<void> _getNewId(SignInService service) async {
    final store = Stores.signIns;
    final ok = await showAppDialog(
      context: context,
      title: 'Get a new ID for ${service.host}?',
      message: _newIdWarning,
      confirmLabel: 'Get a new ID',
      confirmIcon: AppIcons.arrowRepeat,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    runInAction(() => store.newIdOnDisconnect = true);
    await _report(
      'A new ID could not be issued',
      await store.disconnect(service),
    );
  }

  static const _newIdWarning =
      'The next sign-in appears as a new account. The previous account there '
      'cannot be recovered.';

  String _signInFooter(SignInService service) {
    final host = service.host;
    if (service.isDisconnected) {
      return '${service.newIdOnReturn ? 'A new sign-in appears to $host as a new account.' : 'A new sign-in appears to $host as the same account.'} '
          'Existing sessions are ended on $host itself.';
    }
    if (service.isPaused) {
      return 'Sign-in to $host is unavailable while paused. Sessions are ended on '
          '$host itself.';
    }
    return 'Sessions are ended on $host itself.';
  }

  Widget? _manage(SignInService service) {
    final store = Stores.signIns;
    final busy = store.isChanging;
    if (service.isDisconnected) {
      if (service.newIdOnReturn) return null;
      return AppDetailManage(
        actions: [
          AppButton(
            label: 'Get a new ID',
            icon: AppIcons.arrowRepeat,
            style: AppButtonStyle.danger,
            busy: busy,
            onTap: busy ? null : () => _getNewId(service),
          ),
        ],
      );
    }
    return AppDetailManage(
      note: 'Existing sessions on ${service.host} are not ended.',
      actions: [
        if (service.isPaused)
          AppButton(
            label: 'Activate',
            icon: AppIcons.play,
            busy: busy,
            onTap: busy
                ? null
                : () async => _report(
                    'The service could not be activated',
                    await store.activate(service),
                  ),
          )
        else
          AppButton(
            label: 'Pause',
            icon: AppIcons.pause,
            style: AppButtonStyle.accent,
            busy: busy,
            onTap: busy
                ? null
                : () async => _report(
                    'The service could not be paused',
                    await store.pause(service),
                  ),
          ),
        AppButton(
          label: 'Disconnect',
          icon: AppIcons.linkSlash,
          style: AppButtonStyle.danger,
          onTap: busy ? null : () => _disconnect(service),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.signIns;
    final service = _service;
    if (service == null) {
      if (store.loadState.isFirstLoad) {
        return const AppDetailSkeleton(
          badges: [],
          icons: 0,
          sections: [
            AppSkeletonGroup('Sign-in', rows: 2),
            AppSkeletonGroup('Disclosed', rows: 2),
            AppSkeletonGroup('Shared entries', rows: 1),
          ],
        );
      }
      final error = store.loadState.error;
      if (error != null) {
        return AppLoadError(
          title: 'The sign-in could not be loaded',
          message: error,
          onRetry: store.load,
        );
      }
      return AppEmptyState(
        icon: AppIcons.globe,
        title: 'Sign-in not found',
        subtitle: 'No such sign-in exists for this account.',
        action: AppButton(
          icon: AppIcons.arrowLeft,
          label: 'Back to tools',
          style: AppButtonStyle.accent,
          onTap: _back,
        ),
      );
    }
    final host = service.host;
    final link = store.links[service.link];
    const quiet = SizedBox.shrink();
    final manage = _manage(service);

    return AppDetailPage(
      header: AppDetailHeader(
        badges: [
          if (service.isDisconnected) const AppBadge(label: 'Disconnected'),
          if (service.isPaused) const AppBadge(label: 'Paused'),
        ],
        title: host,
        subtitle: service.clientId,
        subtitleMono: true,
      ),
      sections: [
        AppListGroup(
          title: 'Sign-in',
          trailing: quiet,
          footer: Text(_signInFooter(service)),
          children: [
            AppDetailRow(
              icon: AppIcons.calendar,
              label: 'First signed in',
              value: dayTimeLabel(service.created),
            ),
            AppDetailRow(
              icon: AppIcons.clock,
              label: 'Last signed in',
              value: dayTimeLabel(service.lastSignInAt),
            ),
            if (service.isDisconnected)
              AppDetailRow(
                icon: AppIcons.linkSlash,
                label: 'Disconnected',
                value: dayTimeLabel(service.disconnectedAt),
              ),
          ],
        ),
        AppListGroup(
          title: 'Disclosed to $host',
          trailing: quiet,
          footer: Text(
            '$host may retain this data. It can be deleted only on $host.',
          ),
          children: [
            const AppDetailRow(icon: AppIcons.check, label: 'Account identity'),
            for (final s in service.scopes)
              if (s == 'profile' && service.nameRecord.isNotEmpty)
                AppListRow(
                  icon: AppIcons.check,
                  title: signInScopeLabels[s] ?? s,
                  subtitle: service.name.isEmpty
                      ? 'Stored in the vault'
                      : service.name,
                  onTap: () =>
                      context.go(AppRoutes.recordDetailFor(service.nameRecord)),
                )
              else
                AppDetailRow(
                  icon: AppIcons.check,
                  label: signInScopeLabels[s] ?? s,
                  value: s == 'profile' ? service.name : '',
                ),
          ],
        ),
        AppListGroup(
          title: 'Shared entries',
          trailing: quiet,
          footer: link == null ? null : _sharedFooter(host, link),
          children: [
            if (link != null)
              _linkRow(service, link)
            else
              AppDetailRow(
                icon: AppIcons.info,
                label: service.isDisconnected && service.link.isEmpty
                    ? 'Sharing ended'
                    : service.link.isEmpty
                    ? 'No entries shared'
                    : 'Shared from another workspace. Visible only in that '
                          'workspace.',
              ),
          ],
        ),
        ?manage,
      ],
    );
  }

  Widget? _sharedFooter(String host, Link link) => switch (link.status) {
    'active' => Text(
      'Shared entries remain in the vault. $host reads them there until '
      'revoked.',
    ),
    'paused' => Text('$host cannot read these entries while paused.'),
    'revoked' => Text('$host can no longer read these entries.'),
    _ => null,
  };

  Widget _linkRow(SignInService service, Link link) {
    final live = link.status == 'active' || link.status == 'paused';
    final count = link.records.length;
    final label = link.label.isEmpty ? link.slug : link.label;
    return AppListRow(
      icon: AppIcons.link,
      title: label,
      subtitle: '${link.status} · $count ${count == 1 ? 'entry' : 'entries'}',
      onTap: () => showAppOptionsSheet(
        context: context,
        title: label,
        subtitle: service.host,
        actions: [
          AppSheetAction(
            icon: AppIcons.share,
            label: 'Open link',
            onTap: () => context.go(AppRoutes.shareDetailFor(link.id)),
          ),
          ...copyIdActions(context, id: link.id),
          if (live)
            AppSheetAction(
              icon: AppIcons.linkSlash,
              label: 'Revoke',
              destructive: true,
              onTap: () => _revoke(service, link),
            ),
        ],
      ),
    );
  }
}
