import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_service.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
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
            title: 'Couldn’t load your sign-ins',
            message: error,
            onRetry: store.load,
          );
        }
        return AppListGroup(
          title: 'Services you signed in to',
          footer: const Text(
            'Each service gets an ID made just for it, and only what you '
            'agreed to share.',
          ),
          children: [
            for (final s in store.services)
              AppListRow(
                icon: AppIcons.globe,
                title: s.host,
                subtitle: _summary(s),
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
      if (link != null && link.status == 'active') 'Sharing entries',
      'last signed in ${dayLabel(s.lastSignInAt)}',
    ].join(' · ');
  }
}

/// One service: when you signed in, what it learned, and the entries it may
/// read. There is nothing to end here: the service keeps its own login.
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

  Widget _title(BuildContext context) => Observer(
    builder: (_) =>
        AppBarTitle(title: _service?.host ?? 'Sign-in', onBack: _back),
  );

  Future<void> _revoke(SignInService service, Link link) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Revoke ${link.label}?',
      message:
          '${service.host} can’t read these entries any more. Nobody will be '
          'able to open this link.',
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.linkSlash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (!await Stores.signIns.revokeLink(link) && mounted) {
      AppToast.error(
        context,
        'Couldn’t revoke',
        subtitle: Stores.signIns.errorMessage,
      );
    }
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
            AppSkeletonGroup('Learned', rows: 2),
            AppSkeletonGroup('Shared entries', rows: 1),
          ],
        );
      }
      final error = store.loadState.error;
      if (error != null) {
        return AppLoadError(
          title: 'Couldn’t load this sign-in',
          message: error,
          onRetry: store.load,
        );
      }
      return AppEmptyState(
        icon: AppIcons.globe,
        title: 'Sign-in not found',
        subtitle: 'This account has no sign-in here.',
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

    return AppDetailPage(
      header: AppDetailHeader(
        title: host,
        subtitle: service.clientId,
        subtitleMono: true,
      ),
      sections: [
        AppListGroup(
          title: 'Sign-in',
          trailing: quiet,
          footer: Text('To sign out, go to $host.'),
          children: [
            AppDetailRow(
              icon: AppIcons.calendar,
              label: 'First signed in',
              value: dayLabel(service.created),
            ),
            AppDetailRow(
              icon: AppIcons.clock,
              label: 'Last signed in',
              value: dayLabel(service.lastSignInAt),
            ),
          ],
        ),
        AppListGroup(
          title: '$host learned',
          trailing: quiet,
          footer: Text('$host may have saved these. Only it can delete them.'),
          children: [
            const AppDetailRow(icon: AppIcons.check, label: 'That it is you'),
            for (final s in service.scopes)
              if (s == 'profile' && service.nameRecord.isNotEmpty)
                AppListRow(
                  icon: AppIcons.check,
                  title: signInScopeLabels[s] ?? s,
                  subtitle: service.name.isEmpty
                      ? 'In your vault'
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
                label: service.link.isEmpty
                    ? 'You didn’t share any entries'
                    : 'Shared from another workspace. Switch workspace to see '
                          'it.',
              ),
          ],
        ),
      ],
    );
  }

  Widget? _sharedFooter(String host, Link link) => switch (link.status) {
    'active' => Text(
      'Shared entries stay in your vault. $host reads them from there until '
      'you revoke them.',
    ),
    'paused' => Text('$host can’t read these entries while they’re paused.'),
    'revoked' => Text('$host can’t read these entries any more.'),
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
