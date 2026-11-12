import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// Choices get the reading column; background context gets a quieter aside.
/// Uses the space available to the page, including inside a split view.
class AppConsentLayout extends StatelessWidget {
  final List<Widget> decisions;
  final List<Widget> information;
  final Widget? requester;

  const AppConsentLayout({
    super.key,
    required this.decisions,
    required this.information,
    this.requester,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
      if (constraints.maxWidth < 880) {
        return column([
          if (requester != null) ...[requester!, AppSpacing.gapLg],
          ...decisions,
          if (information.isNotEmpty) ...[AppSpacing.gapXl, ...information],
        ]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: column(decisions)),
          AppSpacing.gapXxl,
          Expanded(
            child: column([
              if (requester != null) ...[requester!, AppSpacing.gapLg],
              ...information,
            ]),
          ),
        ],
      );
    },
  );
}

/// The address is essential context, so phones show it before the choices.
class AppConsentRequester extends StatelessWidget {
  final String address;
  final String? account;
  final Widget? badge;

  const AppConsentRequester({
    super.key,
    required this.address,
    this.account,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Requested by').small.muted,
      AppSpacing.gapXs,
      AppText(address).bold.selectable,
      if (badge != null) ...[AppSpacing.gapXs, badge!],
      if (account != null) ...[
        AppSpacing.gapXs,
        Text('Using $account').small.muted,
      ],
    ],
  );
}

/// Secondary explanations stay available without looking like another task.
class AppConsentDetails extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const AppConsentDetails({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    childrenPadding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md,
    ),
    dense: true,
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(title).small.muted,
    children: children,
  );
}
