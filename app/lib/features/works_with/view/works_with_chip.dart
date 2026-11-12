import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/models/works_with.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/features/works_with/view/works_with_service_page.dart';

/// The mark a listed service carries in the list and on its page.
class WorksWithMark extends StatelessWidget {
  final WorksWithService service;

  const WorksWithMark(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (service.unavailable) {
      return AppBadge(
        icon: AppIcons.exclamationTriangle,
        label: 'Unavailable',
        accent: scheme.warning,
      );
    }
    if (!service.verified) {
      return const AppBadge(
        icon: AppIcons.info,
        label: 'Unverified',
        variant: AppBadgeVariant.outline,
      );
    }
    return AppBadge(
      icon: AppIcons.shieldCheck,
      label: 'Listed',
      accent: scheme.success,
    );
  }
}

/// Beside a tool's address on a proposal, connect or sign-in screen: that the
/// address is listed in Works with Revoked. Shows nothing for a tool that is
/// not listed, since most tools are not and that is no warning sign.
///
/// The address is the one fact the tool cannot choose, so the match is by
/// address alone and happens on this device; the tool learns nothing.
class WorksWithChip extends StatelessWidget {
  final String origin;

  const WorksWithChip({super.key, required this.origin});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final service = Stores.worksWith.forOrigin(origin);
        if (service == null) return const SizedBox.shrink();
        return Tooltip(
          message: service.verified
              ? 'Listed in Works with Revoked'
              : 'Listed in Works with Revoked, not yet confirmed on its website',
          child: Semantics(
            button: true,
            label: 'Works with Revoked: ${service.name}',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: AppRadius.allMd,
                onTap: () => showWorksWithServiceSheet(context, service),
                child: WorksWithMark(service),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Said above the switches when a listed tool asks for more than its
/// reviewed entry declares. The extra switches start off; the person still
/// decides.
class WorksWithMismatchAlert extends StatelessWidget {
  final WorksWithService service;

  /// What the tool asks for beyond its entry, as permission labels or
  /// record keys.
  final List<String> extra;

  /// Record keys rather than permissions.
  final bool keys;

  const WorksWithMismatchAlert({
    super.key,
    required this.service,
    required this.extra,
    this.keys = false,
  });

  @override
  Widget build(BuildContext context) {
    final names = keys
        ? extra.join(', ')
        : extra
              .map(
                (k) => ServicePermission(
                  key: k,
                  reason: const LocalizedText(),
                ).label,
              )
              .join(', ');
    return AppAlert(
      tone: AppAlertTone.warning,
      leading: const Icon(AppIcons.exclamationTriangle),
      title: const Text('Not covered by the listing'),
      content: Text(
        keys
            ? '${service.name} is listed in Works with Revoked without '
                  'these records: $names. They start unticked and can still '
                  'be included.'
            : '${service.name} is listed in Works with Revoked without: '
                  '$names. ${extra.length == 1 ? 'This switch starts' : 'These switches start'} '
                  'off and can still be turned on.',
      ),
    );
  }
}
