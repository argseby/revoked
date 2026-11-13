import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/widgets/copy_actions.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_share_sheet.dart';
import 'package:revoked_app/features/attestations/view/verdict_badge.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';

/// A collection tab keeps its heading and action in every load state, with
/// shared quick filters/search above the populated list.
class _TabList extends StatelessWidget {
  final String intro;
  final String title;
  final String listTitle;
  final Widget action;
  final LoadState state;
  final VoidCallback onRetry;
  final Widget empty;
  final AppListToolbar toolbar;
  final bool hasAny;
  final List<Widget> children;

  const _TabList({
    required this.intro,
    required this.title,
    required this.listTitle,
    required this.action,
    required this.state,
    required this.onRetry,
    required this.empty,
    required this.toolbar,
    required this.hasAny,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final header = AppCollectionHeader(
      title: title,
      description: intro,
      action: action,
    );
    return AppLoadFade(
      loading: () => !hasAny && state.isFirstLoad,
      skeleton: AppPageBody(
        children: [
          header,
          AppListSkeleton(
            embedded: true,
            rows: const [
              AppSkeletonRow(
                'Membership',
                'From a club',
                icon: AppIcons.shieldCheck,
                badge: 'Verified',
              ),
              AppSkeletonRow(
                'Employment',
                'From a company',
                icon: AppIcons.shieldCheck,
                badge: 'Verified',
              ),
            ],
          ),
        ],
      ),
      builder: (_) {
        final failure = state.error;
        if (!hasAny) {
          return AppPageBody(
            children: [
              header,
              if (failure != null)
                AppLoadError(
                  title: 'The list could not be loaded',
                  message: failure,
                  onRetry: onRetry,
                )
              else
                empty,
            ],
          );
        }
        return AppListPage(
          toolbar: toolbar,
          inlineToolbar: true,
          banners: [if (failure != null) AppRefreshFailed(onRetry: onRetry)],
          filters: header,
          emptyMessage: children.isEmpty
              ? 'Nothing matches the search or filters.'
              : null,
          groups: [AppListGroup(title: listTitle, children: children)],
        );
      },
    );
  }
}

/// One tab's search, Filter and sort: a [TableStore] for the query and the
/// order, and the statuses its Filter lets through.
class _TabTools<T> {
  final TableStore<T> table;
  final Local<Set<String>> statuses = Local(const {});
  final String key;
  final String hint;
  final String Function(T) statusOf;
  final Map<String, String> statusLabels;

  _TabTools({
    required this.key,
    required this.hint,
    required List<T> Function() items,
    required Map<String, Comparable Function(T)> fields,
    required List<String> searchFields,
    required this.statusOf,
    required this.statusLabels,
  }) : table = TableStore<T>(
         getSourceItems: items,
         fieldGetters: fields,
         defaultSort: 'created_desc',
         searchFields: searchFields,
       );

  /// What the search lets through, in the chosen order.
  List<T> get searched => table.filteredItems;

  /// What the search and the Filter let through.
  List<T> shown(List<T> searched) {
    final picked = statuses.value;
    if (picked.isEmpty) return searched;
    return [
      for (final item in searched)
        if (picked.contains(statusOf(item))) item,
    ];
  }

  AppListToolbar toolbar(List<T> searched) => AppListToolbar(
    key: ValueKey(key),
    totalCount: searched.length,
    query: table.query,
    onQueryChanged: table.setQuery,
    searchHint: hint,
    onClearFilters: () => statuses.value = const {},
    sections: () => [
      if (statusLabels.isNotEmpty)
        AppChecklistSection(
          title: 'Status',
          selected: statuses.value,
          onToggle: (id, on) => statuses.value = on
              ? {...statuses.value, id}
              : ({...statuses.value}..remove(id)),
          items: [
            for (final MapEntry(:key, :value) in statusLabels.entries)
              AppChecklistItem(
                id: key,
                label: value,
                count: searched.where((i) => statusOf(i) == key).length,
              ),
          ],
        ),
    ],
    sort: () => table.sortBy,
    onSort: table.setSort,
    defaultSort: table.defaultSort,
    sortOptions: const [
      AppSortOption('created_desc', 'Newest first'),
      AppSortOption('created_asc', 'Oldest first'),
      AppSortOption('name_asc', 'Name A–Z'),
    ],
  );
}

/// The credentials this person holds, each with what it states.
class HeldAttestations extends StatefulWidget {
  const HeldAttestations({super.key});

  @override
  State<HeldAttestations> createState() => _HeldAttestationsState();
}

class _HeldAttestationsState extends State<HeldAttestations> {
  late final _tools = _TabTools<Credential>(
    key: 'held-toolbar',
    hint: 'Search held attestations',
    items: () => Stores.credentials.credentials.toList(),
    fields: {
      'name': (c) => c.type,
      'issuer': (c) => c.issuer,
      'created': (c) => c.created ?? '',
    },
    searchFields: const ['name', 'issuer'],
    statusOf: (c) => switch (Stores.credentials.verdicts[c.id]) {
      null => 'unchecked',
      final v when v.isVerified => 'verified',
      _ => 'unusable',
    },
    statusLabels: const {
      'verified': 'Verified',
      'unusable': 'Revoked or expired',
      'unchecked': 'Not checked yet',
    },
  );

  String _identityName(Credential c) =>
      Stores.identities.byId(c.identity)?.name ?? 'an identity';

  @override
  Widget build(BuildContext context) {
    final store = Stores.credentials;
    return Observer(
      builder: (_) {
        final searched = _tools.searched;
        return _TabList(
          title: 'Attestations about you',
          listTitle: 'Your attestations',
          action: AppButton(
            icon: AppIcons.plus,
            label: 'New attestation request',
            onTap: () => openAskAttestationSheet(context),
          ),
          toolbar: _tools.toolbar(searched),
          hasAny: store.credentials.isNotEmpty,
          intro: 'Share and collect domain-level claims with others.',
          state: store.loadState,
          onRetry: store.load,
          empty: AppEmptyState(
            icon: AppIcons.attestation,
            title: 'No attestations held',
            subtitle:
                'Facts confirmed by a club, an employer or a verification '
                'service. Only selected details are ever shown.',
            example: const AppEmptyExample(
              title: 'membership',
              detail: 'From chess-club.org · member_since: 2021',
              badge: 'Verified',
            ),
            steps: const [
              AppEmptyStep(
                'Request',
                'A link from New → Attestation about you',
              ),
              AppEmptyStep('Acceptance', 'Bound to one identity'),
              AppEmptyStep('Presentation', 'Selected details only'),
            ],
          ),
          children: [
            for (final c in _tools.shown(searched))
              AppListRow(
                icon: AppIcons.shieldCheck,
                title: c.type.isEmpty ? 'Attestation' : c.type,
                subtitleWidget: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From ${c.issuer} · held by ${_identityName(c)}')
                        .muted
                        .small,
                    if (c.disclosures.isNotEmpty)
                      Text(
                        [for (final d in c.disclosures) d.name].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ).small,
                  ],
                ),
                trailing: verdictBadge(context, store.verdicts[c.id]),
                contextActions: () => [
                  AppSheetAction(
                    icon: AppIcons.link,
                    label: 'Share link',
                    enabled: store.verdicts[c.id]?.isUnusable != true,
                    onTap: () => openAttestationShareSheet(context, c),
                  ),
                  ...copyIdActions(context, id: c.id),
                  AppSheetAction(
                    icon: AppIcons.trash,
                    label: 'Remove attestation',
                    destructive: true,
                    onTap: () => _CredentialSheet(
                      credential: c,
                      identityName: _identityName(c),
                    )._remove(context, closeAfterRemove: false),
                  ),
                ],
                onTap: () {
                  store.loadShares(c.id);
                  showAppSheet(
                    context: context,
                    dismissible: true,
                    builder: (_) => _CredentialSheet(
                      credential: c,
                      identityName: _identityName(c),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// Everything one credential says, and the way to remove it.
class _CredentialSheet extends StatelessWidget {
  final Credential credential;
  final String identityName;

  const _CredentialSheet({
    required this.credential,
    required this.identityName,
  });

  Future<void> _remove(
    BuildContext context, {
    bool closeAfterRemove = true,
  }) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Remove this attestation?',
      message:
          'It is removed from this list. ${credential.issuer} has not revoked '
          'it and can offer it again.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.credentials.remove(credential.id);
    if (!context.mounted) return;
    if (ok) {
      if (closeAfterRemove) Navigator.of(context).pop();
      AppToast.success(context, 'Attestation removed');
    } else {
      AppToast.error(
        context,
        'The attestation could not be removed',
        subtitle: Stores.credentials.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final verdict = Stores.credentials.verdicts[credential.id];
        final claims = credential.disclosures;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(credential.type).header,
                AppSpacing.gapXxs,
                Text('Confirmed by ${credential.issuer}').muted.small,
                AppSpacing.gapMd,
                AppListCard(
                  children: [
                    AppDetailRow(
                      icon: AppIcons.shieldCheck,
                      label: 'Status',
                      value: verdict == null ? 'Checking…' : '',
                      badge: verdictBadge(context, verdict),
                    ),
                    AppDetailRow(
                      icon: AppIcons.personBoundingBox,
                      label: 'For',
                      value: identityName,
                    ),
                    AppDetailRow(
                      icon: AppIcons.calendar,
                      label: 'Issued',
                      value: dayText(credential.issuedAt),
                    ),
                    AppDetailRow(
                      icon: AppIcons.clock,
                      label: 'Valid until',
                      value: credential.expiresAt == null
                          ? 'Until revoked'
                          : dayText(credential.expiresAt),
                    ),
                  ],
                ),
                if (verdict != null && verdict.reason.isNotEmpty) ...[
                  AppSpacing.gapSm,
                  Text(verdict.reason).muted.small,
                ],
                AppSpacing.gapMd,
                const Text('Details'),
                AppSpacing.gapSm,
                AppListCard(
                  children: [
                    if (claims.isEmpty)
                      const AppDetailRow(
                        icon: AppIcons.info,
                        label: 'No details beyond the kind.',
                      )
                    else
                      for (final d in claims)
                        AppDetailRow(label: d.name, value: claimText(d.value)),
                  ],
                ),
                AppSpacing.gapMd,
                const Text('Links'),
                AppSpacing.gapSm,
                const Text(
                  'A link shows this attestation, with the details picked, to '
                  'whoever opens it, in the app or a browser. It proves what '
                  'the issuer attests. It does not prove that whoever passes '
                  'the link on is the holder: for that, the other person '
                  'makes a check under New → See someone\'s attestation.',
                ).muted.small,
                AppSpacing.gapSm,
                AttestationShareList(credential: credential),
                AppSpacing.gapSm,
                AppButton(
                  icon: AppIcons.link,
                  label: 'Share link',
                  style: AppButtonStyle.accent,
                  onTap: verdict == null || !verdict.isUnusable
                      ? () => openAttestationShareSheet(context, credential)
                      : null,
                ),
                AppSpacing.gapLg,
                AppButton(
                  icon: AppIcons.trash,
                  label: 'Remove attestation',
                  style: AppButtonStyle.destructive,
                  onTap: () => _remove(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The attestations this workspace issued.
class IssuedAttestations extends StatefulWidget {
  const IssuedAttestations({super.key});

  @override
  State<IssuedAttestations> createState() => _IssuedAttestationsState();
}

class _IssuedAttestationsState extends State<IssuedAttestations> {
  late final _tools = _TabTools<Attestation>(
    key: 'issued-toolbar',
    hint: 'Search issued attestations',
    items: () => Stores.attestations.attestations.toList(),
    fields: {
      'name': (a) => a.title,
      'subject': (a) => a.subject,
      'type': (a) => a.type,
      'created': (a) => a.created ?? '',
    },
    searchFields: const ['name', 'subject', 'type'],
    statusOf: (a) => a.isRevoked
        ? 'revoked'
        : a.isOffered
        ? 'offered'
        : 'issued',
    statusLabels: const {
      'issued': 'Issued',
      'offered': 'Offered',
      'revoked': 'Revoked',
    },
  );

  Future<void> _revoke(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: a.isOffered ? 'Withdraw this offer?' : 'Revoke ${a.title}?',
      message: a.isOffered
          ? 'The link stops working. The offer has not been accepted.'
          : 'Anyone who checks it sees the revocation within minutes.\n\nThis '
                'cannot be undone. A new attestation can be issued instead.',
      confirmLabel: a.isOffered ? 'Withdraw' : 'Revoke',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.attestations.revoke(a.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(
        context,
        a.isOffered ? 'Offer withdrawn' : 'Attestation revoked',
      );
    } else {
      AppToast.error(
        context,
        'The attestation could not be revoked',
        subtitle: Stores.attestations.error?.description,
      );
    }
  }

  Future<void> _delete(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${a.title}?',
      message: a.isActive
          ? 'It is removed from this list and revoked, so it can no longer be '
                'used.'
          : 'It is removed from this list.',
      confirmLabel: 'Delete',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.attestations.remove(a.id);
    if (!context.mounted || ok) return;
    AppToast.error(
      context,
      'The attestation could not be deleted',
      subtitle: Stores.attestations.error?.description,
    );
  }

  void _options(BuildContext context, Attestation a) {
    showAppOptionsSheet(
      context: context,
      title: a.title,
      subtitle: [
        a.type,
        for (final e in a.claims.entries) '${e.key}: ${claimText(e.value)}',
      ].join(' · '),
      actions: _actions(context, a),
    );
  }

  List<AppSheetAction> _actions(BuildContext context, Attestation a) => [
    if (!a.isRevoked)
      AppSheetAction(
        icon: AppIcons.shieldSlash,
        label: a.isOffered ? 'Withdraw offer' : 'Revoke',
        destructive: true,
        onTap: () => _revoke(context, a),
      ),
    if (a.owner.isNotEmpty && a.owner == Stores.auth.userId)
      AppSheetAction(
        icon: AppIcons.personWorkspace,
        label: 'Visibility',
        onTap: () => openAccessSheet(
          context,
          area: AccessArea.attestations,
          id: a.id,
          name: a.title,
          audienceKind: a.audienceKind,
          editing: a.editing,
          save: (kind, editing, groups) => Stores.attestations.setAudience(
            a.id,
            kind: kind,
            editing: editing,
            groups: groups,
          ),
          saveError: () => Stores.attestations.error?.description,
        ),
      ),
    ...copyIdActions(context, id: a.id),
    AppSheetAction(
      icon: AppIcons.trash,
      label: 'Delete',
      destructive: true,
      onTap: () => _delete(context, a),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestations;
    return Observer(
      builder: (_) {
        final off = store.issuingAllowed == false;
        final searched = _tools.searched;
        return _TabList(
          title: 'Attestations you issue',
          listTitle: 'Issued attestations',
          action: AppButton(
            icon: AppIcons.plus,
            label: 'New attestation',
            onTap: off ? null : () => showAttestationCreateSheet(context),
          ),
          toolbar: _tools.toolbar(searched),
          hasAny: !off && store.attestations.isNotEmpty,
          intro: 'Confirm a membership, role or fact in this workspace’s name.',
          state: store.loadState,
          onRetry: store.load,
          empty: off
              ? const AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'This server does not issue attestations',
                  subtitle:
                      'Issuing has been turned off by the operator. '
                      'Attestations from other issuers can still be held and '
                      'shown.',
                )
              : AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'No attestations issued',
                  subtitle:
                      'A membership, a role or another fact about someone, '
                      'confirmed in the domain’s name. The recipient holds it '
                      'and can show it anywhere.',
                  example: const AppEmptyExample(
                    title: 'Membership 2026 — Ada',
                    detail: 'membership · member_since: 2021',
                    badge: 'Issued',
                  ),
                  steps: const [
                    AppEmptyStep(
                      'Details',
                      'A kind and its details, such as member_since',
                    ),
                    AppEmptyStep('Offer', 'A code or a link, shown once'),
                    AppEmptyStep(
                      'Revocation',
                      'Visible to every check within minutes',
                    ),
                  ],
                ),
          children: [
            if (!off)
              for (final a in _tools.shown(searched))
                AppListRow(
                  icon: a.isRevoked
                      ? AppIcons.shieldSlash
                      : a.isOffered
                      ? AppIcons.send
                      : AppIcons.attestation,
                  title: a.title,
                  subtitle: issuedAttestationSubtitle(a),
                  trailing: issuedAttestationBadge(a),
                  onTap: () => _options(context, a),
                  contextActions: () => _actions(context, a),
                ),
          ],
        );
      },
    );
  }
}

/// The people this person asked to show an attestation, and what they
/// showed.
class CheckedAttestations extends StatefulWidget {
  const CheckedAttestations({super.key});

  @override
  State<CheckedAttestations> createState() => _CheckedAttestationsState();
}

class _CheckedAttestationsState extends State<CheckedAttestations> {
  late final _tools = _TabTools<AttestationCheck>(
    key: 'checked-toolbar',
    hint: 'Search checks',
    items: () => Stores.attestationChecks.checks.toList(),
    fields: {
      'name': (c) => c.title,
      'shown': (c) => c.isAnswered ? c.result!.shownBy : '',
      'created': (c) => c.created ?? '',
    },
    searchFields: const ['name', 'shown'],
    statusOf: (c) => c.isAnswered
        ? 'answered'
        : c.isWaiting(DateTime.now())
        ? 'waiting'
        : 'unanswered',
    statusLabels: const {
      'answered': 'Answered',
      'waiting': 'Waiting',
      'unanswered': 'Not answered',
    },
  );

  void _open(BuildContext context, AttestationCheck c) {
    showAppSheet(
      context: context,
      dismissible: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxs,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.title).header,
            AppSpacing.gapXxs,
            Text(
              c.isAnswered
                  ? 'Verified on arrival. Reflects the state at that time.'
                  : 'This check was not answered.',
            ).muted.small,
            if (c.isAnswered) ...[AppSpacing.gapLg, CheckResultView(check: c)],
            AppSpacing.gapLg,
            AppButton(
              icon: AppIcons.trash,
              label: 'Delete check',
              style: AppButtonStyle.destructive,
              onTap: () async {
                final ok = await Stores.attestationChecks.remove(c.id);
                if (!sheetContext.mounted) return;
                if (ok) Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestationChecks;
    return Observer(
      builder: (_) {
        final searched = _tools.searched;
        return _TabList(
          title: 'Attestation checks',
          listTitle: 'Checks and answers',
          action: AppButton(
            icon: AppIcons.plus,
            label: 'New check',
            onTap: () => openAttestationCheckSheet(context),
          ),
          toolbar: _tools.toolbar(searched),
          hasAny: store.checks.isNotEmpty,
          intro: 'Ask someone to show an attestation and review the verified answer.',
          state: store.loadState,
          onRetry: store.load,
          empty: AppEmptyState(
            icon: AppIcons.shieldCheck,
            title: 'No checks',
            subtitle:
                'A check asks someone to show an attestation from a club or an '
                'employer. The answer is verified on arrival.',
            example: const AppEmptyExample(
              title: 'membership',
              detail: 'Shown by 3fa2c1… · member_since: 2021',
              badge: 'Verified',
            ),
            steps: const [
              AppEmptyStep(
                'Request',
                'A code from New → See someone\'s attestation',
              ),
              AppEmptyStep(
                'Selection',
                'Made by the holder on their own device',
              ),
              AppEmptyStep(
                'Verified answer',
                'Issuer, current validity and proof of ownership',
              ),
            ],
          ),
          children: [
            for (final c in _tools.shown(searched))
              AppListRow(
                icon: c.isAnswered ? AppIcons.shieldCheck : AppIcons.clock,
                title: c.title,
                subtitle: checkSubtitle(c),
                trailing: checkBadge(context, c),
                onTap: () => _open(context, c),
              ),
          ],
        );
      },
    );
  }
}

/// An issued attestation's one line in a list.
String issuedAttestationSubtitle(Attestation a) {
  if (a.isRevoked) {
    return a.subject.isEmpty
        ? 'Withdrawn before acceptance'
        : 'Revoked · ${a.subject}';
  }
  if (a.isOffered) {
    return 'Offered · open until ${dayText(a.offerExpiresAt)}';
  }
  return 'Held by ${a.subject}';
}

Widget? issuedAttestationBadge(Attestation a) {
  if (a.isRevoked) {
    return const AppBadge(icon: AppIcons.shieldSlash, label: 'Revoked');
  }
  if (a.isOffered) {
    return const AppBadge(
      icon: AppIcons.hourglass,
      label: 'Offered',
      variant: AppBadgeVariant.outline,
    );
  }
  return const AppBadge(icon: AppIcons.shieldCheck, label: 'Issued');
}

/// A check's one line in a list.
String checkSubtitle(AttestationCheck c) {
  if (c.isAnswered) {
    return 'Shown by ${c.result!.shownBy} · ${momentText(c.answeredAt)}';
  }
  if (c.isWaiting(DateTime.now())) {
    return 'Waiting for an answer until ${momentText(c.expiresAt)}';
  }
  return 'Not answered · ${momentText(c.created)}';
}

Widget? checkBadge(BuildContext context, AttestationCheck c) {
  if (c.isAnswered) return verdictBadge(context, c.result!.verdict);
  if (c.isWaiting(DateTime.now())) {
    return const AppBadge(
      icon: AppIcons.hourglass,
      label: 'Waiting',
      variant: AppBadgeVariant.outline,
    );
  }
  return const AppBadge(
    icon: AppIcons.clock,
    label: 'Not answered',
    variant: AppBadgeVariant.outline,
  );
}
