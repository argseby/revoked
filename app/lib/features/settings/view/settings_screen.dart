import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/version_summary.dart';
import 'package:revoked_app/core/widgets/official_server_badge.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:revoked_app/features/settings/account_name.dart';

/// The Settings tab — one list, built like the vault: grouped rows, each
/// opening its topic's own page. What is hard to undo — signing out, deleting
/// the account — sits apart at the foot.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Loaded here as well as on each page, so the rows can say how many.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Stores.auth;
      if (!auth.isAuthenticated) return;
      final ws = auth.activeWorkspace ?? '';
      Stores.settings.loadWorkspaces(auth.userId);
      Stores.identities.loadIdentities();
      Stores.settings.ensureDomainChecked();
      Stores.apiKeys.loadApiKeys();
      Stores.passkeys.load();
      Stores.connections.load();
      Stores.credentials.load();
      Stores.serverSettings.loadServerVersion();
      if (ws.isNotEmpty) {
        Stores.invites.load(ws);
        Stores.invites.loadMembers(ws);
        Stores.templates.loadTemplates(ws);
      }
    });
  }

  /// "3 members", or the topic's description while nothing is loaded.
  String _count(int n, String one, String many, String otherwise) =>
      n == 0 ? otherwise : '$n ${n == 1 ? one : many}';

  Widget _page(SettingsPage page, IconData icon, String subtitle) {
    return AppListRow(
      icon: icon,
      title: page.title,
      subtitle: subtitle,
      onTap: () => context.go(page.route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final auth = Stores.auth;
    final openInvites = Stores.invites.invites.where((i) => i.isActive).length;
    final ownTemplates = Stores.templates.templates
        .where((t) => !t.isBuiltin)
        .length;
    final verdict = Stores.settings.domainVerdict;

    return AppListPage(
      groups: [
        AppListGroup(
          title: 'Account',
          trailing: const SizedBox.shrink(),
          children: [
            AppListRow(
              icon: AppIcons.person,
              title: 'Name',
              subtitle: (auth.currentUser?.name ?? '').isEmpty
                  ? 'Not set · used when you sign in to services with Revoked'
                  : auth.currentUser!.name,
              onTap: () => openAccountNameSheet(context),
            ),
            _AppearanceRow(),
            _page(
              SettingsPage.passkeys,
              AppIcons.key,
              _count(
                Stores.passkeys.passkeys.length,
                'passkey',
                'passkeys',
                'How you sign in',
              ),
            ),
          ],
        ),
        AppListGroup(
          title: 'Workspace',
          trailing: const SizedBox.shrink(),
          children: [
            _page(
              SettingsPage.workspaces,
              AppIcons.personWorkspace,
              _count(
                Stores.settings.workspaces.length,
                'workspace',
                'workspaces',
                'Separate your data and sharing',
              ),
            ),
            _page(
              SettingsPage.members,
              AppIcons.person,
              _count(
                Stores.invites.members.length,
                'member',
                'members',
                'Who has access',
              ),
            ),
            _page(
              SettingsPage.invites,
              AppIcons.personPlus,
              _count(
                openInvites,
                'open invite',
                'open invites',
                'No open invites',
              ),
            ),
            _page(
              SettingsPage.identities,
              AppIcons.personBoundingBox,
              _count(
                Stores.identities.identities.length,
                'identity',
                'identities',
                'Sign and verify what you share',
              ),
            ),
            _page(
              SettingsPage.connectedTools,
              AppIcons.plug,
              _count(
                Stores.connections.connections.length,
                'tool connected',
                'tools connected',
                'No tools connected',
              ),
            ),
          ],
        ),
        AppListGroup(
          title: 'Developer',
          trailing: const SizedBox.shrink(),
          children: [
            _page(
              SettingsPage.apiKeys,
              AppIcons.code,
              _count(
                Stores.apiKeys.apiKeys.length,
                'key',
                'keys',
                'Programmatic access',
              ),
            ),
            _page(
              SettingsPage.templates,
              AppIcons.cardList,
              _count(
                ownTemplates,
                'template of your own',
                'templates of your own',
                'Reusable blueprints for requests',
              ),
            ),
            _page(
              SettingsPage.domain,
              AppIcons.server,
              verdict == null
                  ? 'Prove this server controls its domain'
                  : verdict.domain,
            ),
          ],
        ),
        AppListGroup(
          title: 'About',
          trailing: const SizedBox.shrink(),
          footer: const Text(
            'An issue is public: never paste a record value, a share or '
            'request link, or a private key into one.',
          ),
          children: [
            AppListRow(
              icon: AppIcons.play,
              title: 'Take the tour',
              subtitle: 'Records, links and revoking, in one minute',
              onTap: () => context.go(AppRoutes.tour),
            ),
            const _UrlRow(
              icon: AppIcons.code,
              title: 'Source code',
              url: AppConfig.repoUrl,
            ),
            const _UrlRow(
              icon: AppIcons.fileText,
              title: 'Documentation',
              url: AppConfig.docsUrl,
            ),
            const _UrlRow(
              icon: AppIcons.bug,
              title: 'Report a bug',
              url: AppConfig.issuesUrl,
            ),
          ],
        ),
        AppListGroup(
          title: 'Session',
          trailing: const SizedBox.shrink(),
          footer: const Text(
            'Signing out leaves everything on the server — sign back in any '
            'time to pick up where you left off. To use another server, sign '
            'out.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.envelope,
              label: 'Signed in as',
              value: auth.userEmail,
            ),
            AppDetailRow(
              icon: AppIcons.server,
              label: 'Server',
              value: _host(),
              badge: AppConfig.isOfficialServer(Stores.api.baseUrl)
                  ? const OfficialServerBadge()
                  : null,
            ),
            const _VersionRow(),
          ],
        ),
        AppDetailManage(
          actions: [
            AppButton(
              icon: AppIcons.boxArrowLeft,
              label: 'Log out',
              style: AppButtonStyle.accent,
              onTap: () => confirmLogout(context),
            ),
            AppButton(
              icon: AppIcons.trash,
              label: 'Delete account',
              style: AppButtonStyle.destructive,
              busy: auth.isDeletingAccount,
              onTap: _confirmDeleteAccount,
            ),
          ],
        ),
      ],
    );
  }

  String _host() {
    final base = Stores.api.baseUrl;
    final host = Uri.tryParse(base)?.host ?? '';
    return host.isEmpty ? base : host;
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete your account?',
      message:
          'Your workspaces, records and identities are deleted, and every '
          'share and request link you created stops working — anyone still '
          'holding one loses access immediately. This cannot be undone.',
      confirmLabel: 'Delete account',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    if (!await Stores.auth.deleteAccount() && mounted) {
      AppToast.error(
        context,
        'Could not delete the account',
        subtitle: Stores.auth.errorMessage,
      );
    }
  }
}

/// Asks before ending the session on this device. Settings and the account
/// menu both log out through here.
Future<void> confirmLogout(BuildContext context) async {
  final confirmed = await showAppDialog(
    context: context,
    title: 'Log out?',
    message:
        'Your session on this device ends. Everything stays on the server '
        '- log back in any time.',
    confirmLabel: 'Log out',
    confirmIcon: AppIcons.boxArrowLeft,
  );
  if (confirmed) await Stores.auth.logout();
}

/// Theme, detail, text size and motion, summed up in the row that opens them.
class _AppearanceRow extends StatelessWidget {
  static const _themes = {
    ThemeMode.system: 'System theme',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final detail = DisplayPreferences.detailLevel == DetailLevel.full
        ? 'Full detail'
        : 'Essentials';
    final size = '${(DisplayPreferences.textScale * 100).round()}% text';
    return AppListRow(
      icon: AppIcons.brightnessAuto,
      title: SettingsPage.appearance.title,
      subtitle: '${_themes[Stores.theme.mode]} · $detail · $size',
      onTap: () => context.go(SettingsPage.appearance.route),
    );
  }
}

/// Both releases and whether they match, beside the server they belong to.
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.serverSettings;
        return AppDetailRow(
          icon: AppIcons.device,
          label: 'Version',
          value: describeVersions(store.serverVersion),
          badge: versionStandingBadge(context, store.versionStanding),
        );
      },
    );
  }
}

class _UrlRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String url;

  const _UrlRow({required this.icon, required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      icon: icon,
      title: title,
      subtitle: url,
      onTap: () async {
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          AppToast.error(context, 'Could not open $url');
        }
      },
    );
  }
}
