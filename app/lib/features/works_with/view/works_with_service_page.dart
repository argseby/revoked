import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/works_with.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';

/// One listed service's page, under Works with Revoked.
class WorksWithServicePage extends StatefulWidget {
  final String slug;

  const WorksWithServicePage({super.key, required this.slug});

  @override
  State<WorksWithServicePage> createState() => _WorksWithServicePageState();
}

class _WorksWithServicePageState extends State<WorksWithServicePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  void _back() => context.go(AppRoutes.worksWith);

  Widget _title(BuildContext context) =>
      AppBarTitle(title: 'Works with Revoked', onBack: _back);

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final service = Stores.worksWith.bySlug(widget.slug);
        if (service == null) {
          return AppEmptyState(
            icon: AppIcons.worksWith,
            title: 'Service not listed',
            subtitle: 'It may have been removed from Works with Revoked.',
            action: AppButton(
              icon: AppIcons.arrowLeft,
              label: 'Back to the list',
              style: AppButtonStyle.accent,
              onTap: _back,
            ),
          );
        }
        return AppDetailPage(
          header: WorksWithServiceHeader(service),
          sections: worksWithServiceSections(context, service),
          aside: worksWithServiceAside(context, service),
        );
      },
    );
  }
}

/// The same page in a sheet, opened from a proposal screen without leaving
/// the proposal.
Future<void> showWorksWithServiceSheet(
  BuildContext context,
  WorksWithService service,
) => showAppSheet<void>(
  context: context,
  dismissible: true,
  builder: (_) => AppPageBody(
    children: [
      WorksWithServiceHeader(service),
      ...worksWithServiceSections(context, service),
      ...worksWithServiceAside(context, service),
    ],
  ),
);

class WorksWithServiceHeader extends StatelessWidget {
  final WorksWithService service;

  const WorksWithServiceHeader(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    final open = service.website.isNotEmpty
        ? service.website
        : '${service.origin}/';
    return AppDetailHeader(
      badges: [
        WorksWithMark(service),
        if (service.builtByRevoked) const AppBadge(label: 'Built by Revoked'),
        if (service.pricingLabel.isNotEmpty)
          AppBadge(label: service.pricingLabel),
      ],
      title: service.name,
      subtitle: service.host,
      subtitleMono: true,
      primaryAction: AppButton(
        icon: AppIcons.boxArrowUpRight,
        label: 'Open service',
        onTap: () => _open(context, open),
      ),
    );
  }
}

/// What the service does and what it can reach, from its reviewed entry.
List<Widget> worksWithServiceSections(
  BuildContext context,
  WorksWithService service,
) {
  const quiet = SizedBox.shrink();
  return [
    Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppText(service.description.text),
    ),
    if (!service.verified)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: AppText(
          'Not confirmed by ${service.host}. The listing was reviewed, but '
          'the service has not confirmed it on its own website.',
        ).small.muted,
      ),
    AppListGroup(
      title: 'What it can see',
      trailing: quiet,
      footer: const Text(
        'The address above identifies the service. Proposals from it are '
        'checked against this listing on this device.',
      ),
      children: [
        AppDetailRow(
          icon: AppIcons.worksWith,
          label: service.name,
          value: service.stores.text.isEmpty
              ? 'Not stated'
              : service.stores.text,
        ),
        const AppDetailRow(
          icon: AppIcons.server,
          label: 'Your server',
          value: 'Everything, as with all data it holds',
        ),
        if (service.does.contains(ServiceKind.share))
          const AppDetailRow(
            icon: AppIcons.link,
            label: 'Whoever opens a link',
            value: 'What the link shows, while it is active',
          ),
      ],
    ),
    if (service.permissions.isNotEmpty)
      AppListGroup(
        title: 'May ask for',
        trailing: quiet,
        footer: const Text(
          'When it asks for anything not listed here, the connect screen '
          'says so and leaves that switch off.',
        ),
        children: [
          for (final p in service.permissions)
            AppDetailRow(
              icon: p.key == 'read_vault' ? AppIcons.eye : AppIcons.plug,
              label: p.label,
              value: p.reason.text,
              badge: p.sensitive ? const AppBadge(label: 'Sensitive') : null,
            ),
        ],
      ),
    if (service.shareKeys.isNotEmpty || service.requestTemplates.isNotEmpty)
      AppListGroup(
        title: 'Proposes',
        trailing: quiet,
        children: [
          for (final t in service.shareTemplates)
            AppDetailRow(icon: AppIcons.share, label: 'Share', value: t),
          if (service.shareKeys.isNotEmpty)
            AppDetailRow(
              icon: AppIcons.key,
              label: 'Records',
              value: service.shareKeys.join(', '),
              valueMono: true,
            ),
          for (final t in service.requestTemplates)
            AppDetailRow(icon: AppIcons.inboxFill, label: 'Request', value: t),
        ],
      ),
  ];
}

/// Who runs it, its links, and how to report it.
List<Widget> worksWithServiceAside(
  BuildContext context,
  WorksWithService service,
) {
  const quiet = SizedBox.shrink();
  return [
    AppListGroup(
      title: 'Details',
      trailing: quiet,
      children: [
        if (service.operatorName.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.personWorkspace,
            label: 'Operator',
            value: service.operatorName,
          ),
        AppDetailRow(
          icon: AppIcons.worksWith,
          label: 'Does',
          value: service.does.map((k) => k.label).join(', '),
        ),
        AppDetailRow(
          icon: AppIcons.server,
          label: 'Runs on',
          value: [
            service.worksWithAnyServer
                ? 'Any Revoked server'
                : service.servers.map((s) => Uri.parse(s).host).join(', '),
            if (service.selfHostable) 'self-hostable',
          ].join(' · '),
        ),
        if (service.languages.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.globe,
            label: 'Languages',
            value: service.languages.map(_language).join(', '),
          ),
        if (service.reviewed.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.calendar,
            label: 'Reviewed',
            value: service.reviewed,
          ),
      ],
    ),
    AppListGroup(
      title: 'Links',
      trailing: quiet,
      children: [
        if (service.privacyPolicy.isNotEmpty)
          _linkRow(
            context,
            AppIcons.lock,
            'Privacy policy',
            service.privacyPolicy,
          ),
        if (service.imprint.isNotEmpty)
          _linkRow(context, AppIcons.info, 'Imprint', service.imprint),
        if (service.source.isNotEmpty)
          _linkRow(context, AppIcons.code, 'Source code', service.source),
        if (service.security.isNotEmpty)
          _linkRow(
            context,
            AppIcons.shieldCheck,
            'Security contact',
            service.security,
          ),
        _linkRow(
          context,
          AppIcons.flag,
          'Report a problem',
          Uri.parse(AppConfig.worksWithIssueUrl)
              .replace(
                queryParameters: {
                  'title': 'Works with Revoked: ${service.slug}',
                  'body':
                      'Service: ${service.name} (${service.origin})\n\n'
                      'What is wrong:\n',
                },
              )
              .toString(),
        ),
      ],
    ),
  ];
}

Widget _linkRow(BuildContext context, IconData icon, String label, String url) {
  final shown = url.startsWith('mailto:')
      ? url.substring('mailto:'.length)
      : (Uri.tryParse(url)?.host ?? url);
  return AppDetailRow(
    icon: icon,
    label: label,
    value: shown,
    onTap: () => _open(context, url),
  );
}

String _language(String code) => switch (code) {
  'en' => 'English',
  'de' => 'Deutsch',
  _ => code,
};

Future<void> _open(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    AppToast.error(context, 'No app on this device can open this');
  }
}
