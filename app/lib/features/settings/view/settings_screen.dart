import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
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
      if (Stores.features.visible(Feature.developer)) {
        Stores.webhooks.loadIfDue();
      }
      Stores.passkeys.load();
      Stores.keys.ensureLoaded();
      Stores.connections.load();
      Stores.signIns.loadIfDue();
      Stores.credentials.load();
      Stores.serverSettings.loadServerVersion();
      Stores.updates.checkIfDue();
      Stores.features.loadIfDue();
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

  /// "1 tool connected · 2 sign-ins", leaving out whichever there are none of.
  String _toolsSummary() {
    final tools = Stores.connections.connections.length;
    final signIns = Stores.signIns.services.length;
    return [
      if (tools > 0 || signIns == 0)
        _count(
          tools,
          'tool connected',
          'tools connected',
          'No tools connected',
        ),
      if (signIns > 0) _count(signIns, 'sign-in', 'sign-ins', ''),
    ].join(' · ');
  }

  _SettingsDestination _page(
    SettingsPage page,
    IconData icon,
    String subtitle,
  ) {
    return _SettingsDestination(
      icon: icon,
      title: page.title,
      subtitle: subtitle,
      trailing: _stageBadges(page),
      onTap: () => goReturning(context, page.route),
    );
  }

  /// "New" and the alpha or beta tag, for a topic that carries either.
  Widget? _stageBadges(SettingsPage page) {
    final stage = page.stage;
    if (!page.isNew && stage == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        if (page.isNew)
          AppBadge(label: 'New', accent: Theme.of(context).colorScheme.primary),
        if (stage != null)
          AppBadge(label: stage.label, variant: AppBadgeVariant.experimental),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final auth = Stores.auth;
    final features = Stores.features;
    final openInvites = Stores.invites.invites.where((i) => i.isActive).length;
    final ownTemplates = Stores.templates.templates
        .where((t) => !t.isBuiltin)
        .length;
    final verdict = Stores.settings.domainVerdict;

    final groups = <Widget>[
      const AppCollectionHeader(
        title: 'Your settings',
        description:
            'Your account, workspace and the way Revoked works for you.',
      ),
      _SettingsCategory(
        title: 'Account',
        children: [
          _page(
            SettingsPage.appearance,
            AppIcons.brightnessAuto,
            '${switch (Stores.theme.mode) {
              ThemeMode.system => 'System theme',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }} · ${(DisplayPreferences.textScale * 100).round()}% text',
          ),
          _page(SettingsPage.features, AppIcons.sliders, _featuresSummary()),
          _page(
            SettingsPage.passkeys,
            AppIcons.key,
            _count(
              Stores.passkeys.passkeys.length,
              'passkey',
              'passkeys',
              'No passkeys',
            ),
          ),
          if (Stores.keys.isAvailable)
            _page(
              SettingsPage.encryption,
              AppIcons.lock,
              'End-to-end encryption',
            ),
        ],
      ),
      _SettingsCategory(
        title: 'Workspace',
        children: [
          _page(
            SettingsPage.workspaces,
            AppIcons.personWorkspace,
            _count(
              Stores.settings.workspaces.length,
              'workspace',
              'workspaces',
              'Separate spaces for records and links',
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
          if (features.visible(Feature.attestations))
            _page(
              SettingsPage.identities,
              AppIcons.personBoundingBox,
              _count(
                Stores.identities.identities.length,
                'identity',
                'identities',
                'Verifiable identities',
              ),
            ),
          if (features.visible(Feature.tools))
            _page(SettingsPage.connectedTools, AppIcons.plug, _toolsSummary()),
        ],
      ),
      _SettingsCategory(
        title: 'Developer',
        children: [
          if (features.visible(Feature.developer))
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
          if (features.visible(Feature.developer))
            _page(
              SettingsPage.webhooks,
              AppIcons.send,
              _count(
                Stores.webhooks.endpoints.length,
                'webhook',
                'webhooks',
                'Event notifications over HTTP',
              ),
            ),
          if (features.visible(Feature.developer))
            _page(
              SettingsPage.mcp,
              AppIcons.stars,
              'Setup for AI applications',
            ),
          if (features.visible(Feature.requests))
            _page(
              SettingsPage.templates,
              AppIcons.cardList,
              _count(
                ownTemplates,
                'custom template',
                'custom templates',
                'Reusable request forms',
              ),
            ),
          _page(
            SettingsPage.domain,
            AppIcons.server,
            verdict == null ? 'Domain verification' : verdict.domain,
          ),
        ],
      ),
      AppListGroup(
        title: 'About',
        trailing: const SizedBox.shrink(),
        footer: const Text(
          'Bug reports are public. Record values, links and private keys '
          'must never be included.',
        ),
        children: [
          AppListRow(
            icon: AppIcons.play,
            title: 'Take the tour',
            subtitle: 'Records, links and revocation in one minute',
            onTap: () => goReturning(context, AppRoutes.tour),
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
          'Data stays on the server after logging out. Switching servers '
          'requires logging out first.',
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
          // Nothing shows while both are current or the check has no answer.
          if (Stores.updates.appUpdate)
            _UrlRow(
              icon: AppIcons.download,
              title: 'App update available',
              subtitle:
                  '${Stores.updates.latestApp} · downloads on the release '
                  'page',
              url: AppConfig.latestReleaseUrl,
            ),
          if (Stores.updates.serverUpdate)
            _UrlRow(
              icon: AppIcons.server,
              title: 'Server update available',
              subtitle:
                  '${Stores.updates.latestServer} · installed by the server '
                  'operator',
              url: '${AppConfig.docsUrl}/installation/#upgrade',
            ),
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
            style: AppButtonStyle.danger,
            busy: auth.isDeletingAccount,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    ];
    return _SettingsGridLayout(groups: groups);
  }

  /// "Vault, Sharing and Requests", or what a fresh account is told.
  String _featuresSummary() {
    final store = Stores.features;
    final on = [
      'Vault',
      for (final f in store.ordered)
        if (store.visible(f)) store.labelFor(f),
    ];
    if (on.length == 1) return 'Vault only';
    return '${on.sublist(0, on.length - 1).join(', ')} and ${on.last}';
  }

  String _host() {
    final base = Stores.api.baseUrl;
    final host = Uri.tryParse(base)?.host ?? '';
    return host.isEmpty ? base : host;
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete this account?',
      message:
          'All workspaces, records and identities are deleted. Every share '
          'and request link stops working immediately. This cannot be '
          'undone.',
      confirmLabel: 'Delete account',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    if (!await Stores.auth.deleteAccount() && mounted) {
      AppToast.error(
        context,
        'The account could not be deleted.',
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
    message: 'All data stays on the server.',
    confirmLabel: 'Log out',
    confirmIcon: AppIcons.boxArrowLeft,
  );
  if (confirmed) await Stores.auth.logout();
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

  /// What the row says under its title; the address itself by default.
  final String? subtitle;

  const _UrlRow({
    required this.icon,
    required this.title,
    required this.url,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      icon: icon,
      title: title,
      subtitle: subtitle ?? url,
      // Leaves the app, so it carries an outward arrow, not a chevron.
      showChevron: false,
      trailing: Icon(
        AppIcons.boxArrowUpRight,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () async {
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          AppToast.error(context, '$url could not be opened');
        }
      },
    );
  }
}

/// The same responsive card grid used for collection destinations.
class _SettingsCategory extends StatelessWidget {
  final String title;
  final List<_SettingsDestination> children;

  const _SettingsCategory({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListHeader(title: title),
        AppCollectionGrid(children: children),
      ],
    ),
  );
}

class _SettingsDestination extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: SizedBox(
        height: _SettingsCardHeight.of(context),
        child: AppCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: AppRadius.allMd,
                    ),
                    child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (trailing != null) ...[trailing!, AppSpacing.gapXs],
                  Icon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              AppSpacing.gapMd,
              AppText(title).bold,
              AppSpacing.gapXxs,
              AppText(subtitle).small.muted,
            ],
          ),
        ),
      ),
    );
  }
}

/// Measure the longest visible destination once so every category shares a
/// height. Text remains fully readable as the window and text scale change.
class _SettingsGridLayout extends StatelessWidget {
  final List<Widget> groups;
  const _SettingsGridLayout({required this.groups});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = math.min(
        AppSpacing.contentMaxWidth,
        box.maxWidth - AppSpacing.screenH(context) * 2,
      );
      final scaler = MediaQuery.textScalerOf(context);
      final scale = scaler.scale(16) / 16;
      final columns = (width / (220 * scale)).floor().clamp(1, 3);
      final textWidth = math.max(
        1.0,
        (width - AppSpacing.md * (columns - 1)) / columns - AppSpacing.lg * 2,
      );
      final base = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontFamily: AppFont.sans);
      double textHeight(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: base.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: textWidth);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      var height = 0.0;
      for (final category in groups.whereType<_SettingsCategory>()) {
        for (final tile in category.children) {
          final content =
              textHeight(
                tile.title,
                const TextStyle(
                  fontSize: AppTextSize.body,
                  height: AppTextSize.bodyHeight,
                  fontWeight: FontWeight.w600,
                ),
              ) +
              textHeight(
                tile.subtitle,
                const TextStyle(
                  fontSize: AppTextSize.small,
                  height: AppTextSize.smallHeight,
                  fontWeight: FontWeight.w400,
                ),
              );
          height = math.max(height, content);
        }
      }
      // Padding, icon/badge row, and the two gaps between the copy.
      height +=
          AppSpacing.lg * 2 +
          40 * math.max(1, scale) +
          AppSpacing.md +
          AppSpacing.xxs +
          2;
      return _SettingsCardHeight(
        height: height.ceilToDouble(),
        child: AppListPage(groups: groups),
      );
    },
  );
}

class _SettingsCardHeight extends InheritedWidget {
  final double height;
  const _SettingsCardHeight({required this.height, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsCardHeight>()!.height;

  @override
  bool updateShouldNotify(_SettingsCardHeight oldWidget) =>
      oldWidget.height != height;
}
