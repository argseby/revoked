import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/spacing.dart';
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
      // Which templates the requests use, for the Templates card.
      if (Stores.features.visible(Feature.requests)) {
        Stores.requests.loadIfDue();
      }
    });
  }

  /// "3 members", or [none] when there are none.
  String _count(int n, String one, String many, String none) =>
      n == 0 ? none : '$n ${n == 1 ? one : many}';

  /// "1 tool connected · 2 sign-ins", or that nothing is connected.
  String _toolsStatus() {
    final tools = Stores.connections.connections.length;
    final signIns = Stores.signIns.services.length;
    if (tools == 0 && signIns == 0) return 'Nothing connected';
    return [
      if (tools > 0) _count(tools, 'tool connected', 'tools connected', ''),
      if (signIns > 0) _count(signIns, 'sign-in', 'sign-ins', ''),
    ].join(' · ');
  }

  /// A topic's card: its title, a status where there is one worth stating,
  /// and its description (or [description] in its place).
  _SettingsDestination _page(
    SettingsPage page,
    IconData icon, {
    String? status,
    Color? statusColor,
    String? description,
  }) {
    return _SettingsDestination(
      icon: icon,
      title: page.title,
      status: status,
      statusColor: statusColor,
      subtitle: description ?? page.description,
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
    final scheme = Theme.of(context).colorScheme;
    final activeWorkspace = Stores.settings.workspaces
        .where((w) => w.id == auth.activeWorkspace)
        .firstOrNull;
    final usedTemplates = Stores.requests.requests
        .map((r) => r.templateId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

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
            status:
                '${switch (Stores.theme.mode) {
                  ThemeMode.system => 'System theme',
                  ThemeMode.light => 'Light theme',
                  ThemeMode.dark => 'Dark theme',
                }} · ${(DisplayPreferences.textScale * 100).round()}% text',
          ),
          _page(
            SettingsPage.features,
            AppIcons.sliders,
            status: _featuresStatus(),
          ),
          _page(
            SettingsPage.passkeys,
            AppIcons.key,
            status: _count(
              Stores.passkeys.passkeys.length,
              'passkey set up',
              'passkeys set up',
              'No passkeys yet',
            ),
          ),
          if (Stores.keys.isAvailable)
            _page(
              SettingsPage.encryption,
              AppIcons.lock,
              status: switch (Stores.keys.status) {
                SealingStatus.ready => 'Ready on this device',
                SealingStatus.notSetUp => 'Not set up',
                _ => 'Needs attention on this device',
              },
              statusColor: switch (Stores.keys.status) {
                SealingStatus.ready => scheme.success,
                SealingStatus.notSetUp => null,
                _ => scheme.warning,
              },
            ),
        ],
      ),
      _SettingsCategory(
        title: 'Workspace',
        children: [
          _page(
            SettingsPage.workspaces,
            AppIcons.personWorkspace,
            // The one in use says more than how many there are.
            status: activeWorkspace == null
                ? null
                : 'Working in ${activeWorkspace.name}',
          ),
          _page(
            SettingsPage.members,
            AppIcons.person,
            status: switch (Stores.invites.members.length) {
              0 => null,
              1 => 'Only you',
              final n => '$n members',
            },
          ),
          _page(
            SettingsPage.invites,
            AppIcons.personPlus,
            status: _count(
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
              status: _count(
                Stores.identities.identities.length,
                'identity',
                'identities',
                'No identities yet',
              ),
            ),
          if (features.visible(Feature.tools))
            _page(
              SettingsPage.connectedTools,
              AppIcons.plug,
              status: _toolsStatus(),
            ),
        ],
      ),
      _SettingsCategory(
        title: 'Developer',
        children: [
          if (features.visible(Feature.developer))
            _page(
              SettingsPage.apiKeys,
              AppIcons.code,
              status: _count(
                Stores.apiKeys.apiKeys.length,
                'API key',
                'API keys',
                'No API keys',
              ),
            ),
          if (features.visible(Feature.developer))
            _page(
              SettingsPage.webhooks,
              AppIcons.send,
              status: _count(
                Stores.webhooks.endpoints.length,
                'endpoint',
                'endpoints',
                'No endpoints',
              ),
            ),
          if (features.visible(Feature.developer))
            _page(
              SettingsPage.mcp,
              AppIcons.stars,
              status: 'Setup guide for AI assistants',
            ),
          if (features.visible(Feature.requests))
            _page(
              SettingsPage.templates,
              AppIcons.cardList,
              status: usedTemplates > 0
                  ? '$usedTemplates used by requests'
                  : _count(
                      ownTemplates,
                      'custom template',
                      'custom templates',
                      'Built-in templates only',
                    ),
            ),
          _page(
            SettingsPage.domain,
            AppIcons.server,
            status: _domainStatus(verdict),
            statusColor: switch (verdict?.state) {
              null => null,
              TrustState.verified => scheme.success,
              TrustState.dnsMissing || TrustState.unverified => scheme.warning,
              TrustState.spoofed || TrustState.revoked => scheme.error,
            },
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

  /// "All features enabled", "5 of 6 features enabled", or vault only.
  String _featuresStatus() {
    final store = Stores.features;
    final total = store.ordered.length;
    final on = store.ordered.where(store.visible).length;
    if (on == 0) return 'Only the vault is shown';
    if (on == total) return 'All features enabled';
    return '$on of $total features enabled';
  }

  /// "Verified · example.com": how the check went, and for which domain.
  String? _domainStatus(TrustVerdict? verdict) {
    if (verdict == null) return null;
    final state = switch (verdict.state) {
      TrustState.verified => 'Verified',
      TrustState.dnsMissing || TrustState.unverified => 'Not verified',
      TrustState.spoofed || TrustState.revoked => 'Check failed',
    };
    return verdict.domain.isEmpty ? state : '$state · ${verdict.domain}';
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
  final String? status;
  final Color? statusColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.status,
    this.statusColor,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The title has the row to itself, beside its icon.
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  AppSpacing.gapSm,
                  Expanded(
                    child: AppText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).bold,
                  ),
                  if (trailing != null) ...[AppSpacing.gapXs, trailing!],
                  AppSpacing.gapXs,
                  Icon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              AppSpacing.gapXxs,
              // Where it stands, on a line of its own; the line is kept
              // while the status loads so cards keep one height.
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: statusColor ?? scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                child: Text(
                  status ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).small,
              ),
              AppSpacing.gapSm,
              Divider(height: 1, color: scheme.outlineVariant),
              AppSpacing.gapSm,
              AppText(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ).small.muted,
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
      final base = DefaultTextStyle.of(context).style
          .copyWith(fontFamily: AppFont.sans);
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

      // One title line and at most two lines of description: the longest
      // description decides whether every card takes the second line.
      var lines = 1;
      for (final category in groups.whereType<_SettingsCategory>()) {
        for (final tile in category.children) {
          final single = textHeight(
            'X',
            const TextStyle(
              fontSize: AppTextSize.small,
              height: AppTextSize.smallHeight,
            ),
          );
          final full = textHeight(
            tile.subtitle,
            const TextStyle(
              fontSize: AppTextSize.small,
              height: AppTextSize.smallHeight,
            ),
          );
          if (full > single * 1.5) lines = 2;
        }
      }
      final titleLine = math.max(
        scaler.scale(AppTextSize.body) * AppTextSize.bodyHeight,
        20.0,
      );
      final smallLine =
          scaler.scale(AppTextSize.small) * AppTextSize.smallHeight;
      // Title, status, the divider with its gaps, then the description.
      final height =
          AppSpacing.lg * 2 +
          titleLine +
          AppSpacing.xxs +
          smallLine +
          AppSpacing.sm * 2 +
          1 +
          smallLine * lines +
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
