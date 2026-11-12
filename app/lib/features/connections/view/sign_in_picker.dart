import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_consent_layout.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';

/// Something a service could be given.
class SignInChoice {
  final String id;

  /// The vault entry behind it; null for an identity.
  final String? recordId;

  /// Empty when it isn't shown, as with a hidden entry or a file.
  final String value;
  final String title;
  final String key;

  /// Whether the service gets this now, from an earlier sign-in.
  final bool shared;

  /// Whether the entry was made at an earlier sign-in at this service.
  final bool madeFor;

  const SignInChoice({
    required this.id,
    required this.value,
    required this.title,
    this.recordId,
    this.key = '',
    this.shared = false,
    this.madeFor = false,
  });

  String get primary => value.isEmpty ? title : value;
  String get secondary => value.isEmpty ? key : title;
}

/// One folder in the vault browser.
class SignInFolder {
  final String id;
  final String name;
  final List<SignInChoice> choices;

  const SignInFolder(this.id, this.name, this.choices);
}

/// What the vault browser shows.
class SignInBrowseData {
  final List<SignInChoice> choices;
  final List<SignInSection> sections;
  final String selected;
  final bool busy;

  const SignInBrowseData({
    required this.choices,
    required this.sections,
    required this.selected,
    required this.busy,
  });
}

/// Files [choices] the way the vault does. An entry in two sections shows in
/// both, as it does there.
List<SignInFolder> signInFolders(
  List<SignInChoice> choices,
  List<SignInSection> sections,
) {
  final filed = <String>{};
  final folders = <SignInFolder>[];
  final identities = [
    for (final c in choices)
      if (c.recordId == null) c,
  ];
  if (identities.isNotEmpty) {
    folders.add(SignInFolder('identities', 'Identities', identities));
  }
  for (final s in sections) {
    final inside = [
      for (final c in choices)
        if (s.records.contains(c.recordId)) c,
    ];
    if (inside.isEmpty) continue;
    filed.addAll(inside.map((c) => c.id));
    folders.add(
      SignInFolder(s.id, s.isSignIn ? 'Sign-in · ${s.name}' : s.name, inside),
    );
  }
  final loose = [
    for (final c in choices)
      if (c.recordId != null && !filed.contains(c.id)) c,
  ];
  if (loose.isNotEmpty) {
    folders.add(SignInFolder('loose', 'Not in a section', loose));
  }
  return folders;
}

/// The few choices worth showing up front: what's picked, then what's under
/// the key asked for, then what shares a word with it. With [allFit] every
/// choice already answers the question, as every name option reads as a name.
List<SignInChoice> signInShortlist(
  List<SignInChoice> choices,
  String askedKey,
  String selected, {
  int size = 3,
  bool allFit = false,
}) {
  final words = askedKey.split('_').where((w) => w.length > 2).toSet();
  int rank(SignInChoice c) {
    if (c.id == selected) return 0;
    if (c.key == askedKey) return 1;
    if (c.recordId == null) return 2;
    if (allFit) return 3;
    final name = '${c.key} ${c.title}'.toLowerCase();
    return words.any(name.contains) ? 3 : 4;
  }

  final ranked = [
    for (final c in choices)
      if (rank(c) < 4) c,
  ]..sort((a, b) => rank(a) - rank(b));
  return ranked.take(size).toList();
}

/// Answers one thing a service asks for. The preview says what it will get, so
/// nobody has to work that out from a form; the likeliest answers are one tap
/// away, and the rest of the vault is a folder further.
class SignInPicker extends StatelessWidget {
  /// In [selected]: type a new value. Can't be an entry's id, which is longer.
  static const newValue = 'new';

  final String heading;
  final String preview;
  final String nothing;
  final String newHint;
  final String askedKey;
  final String selected;
  final String? lastPick;
  final bool allFit;
  final List<SignInChoice> choices;
  final ObservableTextController draft;
  final String? workspace;
  final bool busy;
  final String? note;

  /// Marks a question the service asks for the first time, on a return.
  final bool isNew;

  /// The most characters a new value may have; the field stops there and
  /// counts down as it gets close.
  final int? maxLength;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSwitchWorkspace;
  final SignInBrowseData Function() browse;

  const SignInPicker({
    super.key,
    required this.heading,
    required this.preview,
    required this.nothing,
    required this.newHint,
    required this.askedKey,
    required this.selected,
    required this.choices,
    required this.draft,
    required this.busy,
    required this.onChanged,
    required this.onSwitchWorkspace,
    required this.browse,
    this.lastPick,
    this.allFit = false,
    this.workspace,
    this.note,
    this.maxLength,
    this.isNew = false,
  });

  SignInChoice? get _picked {
    for (final c in choices) {
      if (c.id == selected) return c;
    }
    return null;
  }

  void _toggle(bool on, List<SignInChoice> shortlist) {
    if (!on) return onChanged('');
    final last = lastPick;
    final known = choices.any((c) => c.id == last) || last == newValue;
    onChanged(
      last != null && known
          ? last
          : shortlist.isNotEmpty
          ? shortlist.first.id
          : newValue,
    );
  }

  Future<void> _openBrowser(BuildContext context) {
    Stores.signInApproval.browseQuery.clear();
    return showAppSheet<void>(
      context: context,
      dismissible: true,
      builder: (_) => SignInVaultBrowser(
        heading: heading,
        data: browse,
        onPicked: onChanged,
        onCreate: (text) {
          draft.text = text;
          onChanged(newValue);
        },
        onSwitchWorkspace: onSwitchWorkspace,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortlist = signInShortlist(
      choices,
      askedKey,
      selected,
      allFit: allFit,
    );
    final picked = _picked;
    final hasMore = choices.any((c) => !shortlist.contains(c));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        isNew
            ? Row(
                children: [
                  Flexible(child: Text(heading)),
                  AppSpacing.gapSm,
                  const AppBadge(label: 'New'),
                ],
              )
            : Text(heading),
        AppSpacing.gapSm,
        _Preview(
          label: selected.isEmpty ? null : preview,
          value: selected == newValue
              ? draft.text.trim()
              : selected.isEmpty
              ? nothing
              : picked?.primary ?? '',
          placeholder: newHint,
          detail: [
            if (selected == newValue) 'New value',
            if (picked != null && picked.value.isNotEmpty) picked.title,
            if (picked != null && picked.shared) 'Already shared · unchanged',
            if (selected.isEmpty) 'Sign-in works without it',
            if (selected.isNotEmpty && workspace != null) workspace!,
          ].join(' · '),
          on: selected.isNotEmpty,
          onToggle: busy ? null : (on) => _toggle(on, shortlist),
        ),
        AppConsentDetails(
          title: 'Choose or add an entry',
          children: [
            for (final c in shortlist) ...[
              SignInChoiceRow(
                choice: c,
                selected: c.id == selected,
                onTap: busy ? null : () => onChanged(c.id),
              ),
              AppSpacing.gapSm,
            ],
            Focus(
              onFocusChange: (focused) {
                if (focused && selected != newValue) onChanged(newValue);
              },
              child: AppTextField(
                controller: draft,
                hint: newHint,
                enabled: !busy,
                leading: const Icon(AppIcons.plus),
                inputFormatters: [
                  if (maxLength != null)
                    LengthLimitingTextInputFormatter(maxLength),
                ],
                onChanged: (_) {
                  if (selected != newValue) onChanged(newValue);
                },
              ),
            ),
            if (maxLength case final max?)
              Observer(
                builder: (context) {
                  final length = draft.text.characters.length;
                  if (length < max * 0.8) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      length >= max
                          ? 'At most $max characters.'
                          : '${max - length} characters left',
                    ).small.muted,
                  );
                },
              ),
            if (hasMore) ...[
              AppSpacing.gapSm,
              _Row(
                leading: const Icon(AppIcons.folder),
                primary: 'Browse vault',
                secondary: '${choices.length} available',
                trailing: const Icon(AppIcons.chevronRight),
                onTap: busy ? null : () => _openBrowser(context),
              ),
            ],
          ],
        ),
        if (note != null) ...[AppSpacing.gapSm, Text(note!).small.muted],
      ],
    );
  }
}

/// What the service will get, with the switch that decides whether it does.
class _Preview extends StatelessWidget {
  final String? label;
  final String value;
  final String placeholder;
  final String detail;
  final bool on;
  final ValueChanged<bool>? onToggle;

  const _Preview({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.detail,
    required this.on,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: on
            ? scheme.primary.withValues(alpha: 0.06)
            : scheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(label!).small.muted,
                  AppSpacing.gapXxs,
                ],
                value.isEmpty
                    ? Text(placeholder).header.muted
                    : Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ).header,
                if (detail.isNotEmpty) ...[
                  AppSpacing.gapXxs,
                  Text(detail).small.muted,
                ],
              ],
            ),
          ),
          AppSpacing.gapSm,
          Semantics(
            label: 'Share this',
            child: AppSwitch(value: on, onChanged: onToggle),
          ),
        ],
      ),
    );
  }
}

/// A choice to tap, with what's chosen marked.
class SignInChoiceRow extends StatelessWidget {
  final SignInChoice choice;
  final bool selected;
  final String? where;
  final VoidCallback? onTap;

  const SignInChoiceRow({
    super.key,
    required this.choice,
    required this.selected,
    required this.onTap,
    this.where,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: _Row(
        primary: choice.primary,
        secondary: [
          choice.secondary,
          ?where,
        ].where((s) => s.isNotEmpty).join(' · '),
        tertiary: choice.madeFor ? 'Made at your last sign-in' : null,
        selected: selected,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (choice.shared) ...[
              const AppBadge(label: 'Shared now'),
              AppSpacing.gapSm,
            ],
            Icon(
              selected ? AppIcons.checkCircle : AppIcons.circle,
              color: selected ? scheme.primary : scheme.outline,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget? leading;
  final String primary;
  final String secondary;

  /// A further line, for where an entry came from.
  final String? tertiary;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  const _Row({
    required this.primary,
    required this.secondary,
    required this.onTap,
    this.leading,
    this.tertiary,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allMd,
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
            borderRadius: AppRadius.allMd,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, AppSpacing.gapMd],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (secondary.isNotEmpty)
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small.muted,
                    if (tertiary case final line?)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small.muted,
                  ],
                ),
              ),
              if (trailing != null) ...[AppSpacing.gapMd, trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// The whole vault, a folder at a time, because a hundred entries in one list
/// is no choice at all. Searching looks through every folder.
class SignInVaultBrowser extends StatefulWidget {
  /// How many entries a folder or a search shows before asking.
  static const preview = 8;

  final String heading;
  final SignInBrowseData Function() data;
  final ValueChanged<String> onPicked;
  final ValueChanged<String> onCreate;
  final ValueChanged<String> onSwitchWorkspace;

  const SignInVaultBrowser({
    super.key,
    required this.heading,
    required this.data,
    required this.onPicked,
    required this.onCreate,
    required this.onSwitchWorkspace,
  });

  @override
  State<SignInVaultBrowser> createState() => _SignInVaultBrowserState();
}

class _SignInVaultBrowserState extends State<SignInVaultBrowser> {
  final _folder = Local<String?>(null);
  final _showAll = Local<bool>(false);

  void _pick(String id) {
    widget.onPicked(id);
    Navigator.of(context).pop();
  }

  Widget _rows(
    List<SignInChoice> choices,
    String selected,
    bool busy,
    String? Function(SignInChoice) where,
  ) {
    final shown = _showAll.value
        ? choices
        : choices.take(SignInVaultBrowser.preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in shown) ...[
          SignInChoiceRow(
            choice: c,
            selected: c.id == selected,
            where: where(c),
            onTap: busy ? null : () => _pick(c.id),
          ),
          AppSpacing.gapSm,
        ],
        if (shown.length < choices.length)
          AppButton(
            label: 'Show all ${choices.length}',
            icon: AppIcons.chevronDown,
            style: AppButtonStyle.accent,
            onTap: () => _showAll.value = true,
          ),
      ],
    );
  }

  Widget _results(
    SignInBrowseData d,
    List<SignInFolder> folders,
    String query,
  ) {
    final needle = query.toLowerCase();
    final found = [
      for (final c in d.choices)
        if ('${c.value} ${c.title} ${c.key}'.toLowerCase().contains(needle)) c,
    ];
    String? where(SignInChoice c) {
      for (final f in folders) {
        if (f.choices.contains(c)) return f.name;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows(found, d.selected, d.busy, where),
        if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('No matches in this workspace.').small.muted,
          ),
        _Row(
          leading: const Icon(AppIcons.plus),
          primary: 'Create “$query”',
          secondary: 'Saved as a new value',
          onTap: d.busy
              ? null
              : () {
                  widget.onCreate(query);
                  Navigator.of(context).pop();
                },
        ),
      ],
    );
  }

  Widget _list(SignInBrowseData d) {
    if (d.busy) {
      return const AppListSkeleton(embedded: true);
    }
    final folders = signInFolders(d.choices, d.sections);
    final query = Stores.signInApproval.browseQuery.text.trim();
    if (query.isNotEmpty) return _results(d, folders, query);

    SignInFolder? open;
    for (final f in folders) {
      if (f.id == _folder.value) open = f;
    }
    if (open != null) {
      return _rows(open.choices, d.selected, d.busy, (_) => null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in folders) ...[
          _Row(
            leading: const Icon(AppIcons.folder),
            primary: f.name,
            secondary: f.choices.length == 1
                ? '1 entry'
                : '${f.choices.length} entries',
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () {
              _showAll.value = false;
              _folder.value = f.id;
            },
          ),
          AppSpacing.gapSm,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final d = widget.data();
        SignInFolder? open;
        for (final f in signInFolders(d.choices, d.sections)) {
          if (f.id == _folder.value) open = f;
        }
        final inFolder = open != null;
        return Padding(
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
              Row(
                children: [
                  if (inFolder) ...[
                    AppButton(
                      icon: AppIcons.arrowLeft,
                      tooltip: 'Back to vault',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: () {
                        _showAll.value = false;
                        _folder.value = null;
                      },
                    ),
                    AppSpacing.gapSm,
                  ],
                  Expanded(
                    child: Text(
                      open?.name ?? widget.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).header,
                  ),
                  AppSpacing.gapSm,
                  WorkspaceChip(
                    onSwitch: (id) {
                      _folder.value = null;
                      _showAll.value = false;
                      Stores.signInApproval.browseQuery.clear();
                      widget.onSwitchWorkspace(id);
                    },
                  ),
                ],
              ),
              AppSpacing.gapMd,
              AppTextField(
                controller: Stores.signInApproval.browseQuery,
                hint: 'Search vault',
                leading: const Icon(AppIcons.search),
                onChanged: (_) => _showAll.value = false,
              ),
              AppSpacing.gapMd,
              Flexible(child: SingleChildScrollView(child: _list(d))),
            ],
          ),
        );
      },
    );
  }
}
