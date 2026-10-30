import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';

/// The steps of the tour, in order.
enum TourStep { record, link, open, change, revoke, done }

/// A one-minute walk through the whole idea, with real data: a record is
/// saved, a link to it is made, the link is opened the way a recipient sees
/// it, the value changes and the link shows the change, and once revoked the
/// link stops working. Everything it creates is the owner's own and can be
/// deleted at the end.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  final Local<TourStep> _step = Local(TourStep.record);
  final Local<bool> _busy = Local(false);
  final Local<String?> _error = Local(null);
  final Local<String?> _recordId = Local(null);
  final Local<Link?> _link = Local(null);

  /// Set once the new value is saved, so the step shows what comes next.
  final Local<bool> _changed = Local(false);

  final ObservableTextController _label = ObservableTextController(
    text: 'Wi-Fi password',
  );
  final ObservableTextController _value = ObservableTextController(
    text: 'correct-horse-battery-staple',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // The link is signed with the primary identity when there is one.
      Stores.identities.loadIdentities();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  Widget _title(BuildContext context) =>
      AppBarTitle(title: 'Tour', onBack: () => context.go(AppRoutes.vault));

  String get _webUrl => '${Stores.api.baseUrl}/s/${_link.value?.slug ?? ''}';

  /// Runs one step's work with the shared busy and error state, and moves on
  /// to [next] when it succeeds.
  Future<void> _run(Future<bool> Function() work, TourStep next) async {
    _busy.value = true;
    _error.value = null;
    final ok = await work();
    if (!mounted) return;
    _busy.value = false;
    if (ok) {
      _step.value = next;
    } else {
      _error.value =
          Stores.vault.errorMessage ??
          Stores.shares.errorMessage ??
          'Something went wrong. Try again.';
    }
  }

  Future<bool> _saveRecord() async {
    final vault = Stores.vault;
    final ok = await vault.createRecord(
      key: keyFromLabel(_label.text, vault.records.map((r) => r.key)),
      value: _value.text,
      label: _label.text.trim(),
      type: 'text',
      format: 'default',
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
    );
    if (ok) _recordId.value = vault.records.first.id;
    return ok;
  }

  Future<bool> _createLink() async {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final slug = List.generate(
      10,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    final shares = Stores.shares;
    final ok = await shares.createShare(
      slug: slug,
      label: 'Tour · ${_label.text.trim()}',
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: const [],
      records: [_recordId.value!],
      // Made for the tour, so it lapses by itself the next day.
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      identityId: Stores.identities.primaryIdentity?.id,
    );
    if (ok) _link.value = shares.shares.first;
    return ok;
  }

  Future<bool> _changeValue() async {
    final ok = await Stores.vault.updateRecord(_recordId.value!, {
      'value': _value.text,
    });
    if (ok) _changed.value = true;
    return ok;
  }

  Future<bool> _revoke() =>
      Stores.shares.updateShare(_link.value!.id, {'status': 'revoked'});

  Future<void> _cleanUp() async {
    _busy.value = true;
    final link = _link.value;
    final recordId = _recordId.value;
    if (link != null) await Stores.shares.deleteShare(link.id);
    if (recordId != null) await Stores.vault.deleteRecord(recordId);
    if (!mounted) return;
    _busy.value = false;
    AppToast.success(context, 'Tour data deleted');
    context.go(AppRoutes.vault);
  }

  /// The recipient's view, on top of the tour so closing it comes back here.
  void _openAsRecipient() => context.push('/s/${_link.value!.slug}');

  Future<void> _openInBrowser() async {
    final ok = await launchUrl(
      Uri.parse(_webUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) AppToast.error(context, 'Couldn\'t open $_webUrl');
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: _build);
  }

  Widget _build(BuildContext context) {
    final step = _step.value;
    return AppPageBody(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Share something, then take it back').header,
                AppSpacing.gapXs,
                const Text(
                  'You\'ll use real data in your vault. You can delete all of '
                  'it at the end.',
                ).muted,
                AppSpacing.gapXl,
                for (final s in TourStep.values)
                  if (s != TourStep.done) _stepCard(context, s, step),
                if (step == TourStep.done) _doneCard(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepCard(BuildContext context, TourStep s, TourStep current) {
    final scheme = Theme.of(context).colorScheme;
    final done = s.index < current.index;
    final active = s == current;
    final (title, summary) = _copy(s);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.allPill,
                    color: done
                        ? scheme.primary
                        : (active ? scheme.secondaryContainer : null),
                    border: done || active
                        ? null
                        : Border.all(color: scheme.outlineVariant),
                  ),
                  child: done
                      ? Icon(AppIcons.check, size: 16, color: scheme.onPrimary)
                      : Text('${s.index + 1}').small,
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: active || done
                      ? AppText(title, bold: true)
                      : Text(title).muted,
                ),
              ],
            ),
            if (active) ...[
              AppSpacing.gapMd,
              Text(summary).muted,
              AppSpacing.gapLg,
              ..._controls(context, s),
              if (_error.value != null) ...[
                AppSpacing.gapMd,
                AppAlert(
                  destructive: true,
                  leading: const Icon(AppIcons.exclamation),
                  content: Text(_error.value!),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  (String, String) _copy(TourStep s) => switch (s) {
    TourStep.record => (
      'Add something to share',
      'Start with something you\'d hand out, like a Wi-Fi password. It stays '
          'in your vault until you share it.',
    ),
    TourStep.link => (
      'Make a link',
      'Anyone with this link can see the value, and you stay in control of '
          'it. This one stops working tomorrow on its own.',
    ),
    TourStep.open => (
      'See what they see',
      'This is what the person you send the link to sees. Close it to come '
          'back here.',
    ),
    TourStep.change => (
      'Change the value',
      'Change the value in your vault. Everyone with the link sees the new '
          'one. No need to send anything again.',
    ),
    TourStep.revoke => (
      'Take it back',
      'Revoke the link and it stops working right away. The value stays in '
          'your vault.',
    ),
    TourStep.done => ('', ''),
  };

  List<Widget> _controls(BuildContext context, TourStep s) {
    final busy = _busy.value;
    switch (s) {
      case TourStep.record:
        return [
          AppTextField(controller: _label, label: 'Label'),
          AppSpacing.gapMd,
          AppTextField(controller: _value, label: 'Value', mono: true),
          AppSpacing.gapLg,
          _primary(
            icon: AppIcons.safe,
            label: 'Save to vault',
            onTap: _label.text.trim().isEmpty || _value.text.trim().isEmpty
                ? null
                : () => _run(_saveRecord, TourStep.link),
          ),
        ];
      case TourStep.link:
        return [
          _primary(
            icon: AppIcons.link,
            label: 'Create link',
            onTap: () => _run(_createLink, TourStep.open),
          ),
        ];
      case TourStep.open:
        return [
          _UrlBox(url: _webUrl),
          AppSpacing.gapMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                icon: AppIcons.eye,
                label: 'Open as recipient',
                onTap: _openAsRecipient,
              ),
              AppButton(
                icon: AppIcons.globe,
                label: 'Open in browser',
                style: AppButtonStyle.accent,
                onTap: _openInBrowser,
              ),
            ],
          ),
          AppSpacing.gapLg,
          _primary(
            icon: AppIcons.arrowRight,
            label: 'Next',
            style: AppButtonStyle.accent,
            onTap: () => _step.value = TourStep.change,
          ),
        ];
      case TourStep.change:
        if (_changed.value) {
          return [
            const Text('Saved. They now see the new value.'),
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  icon: AppIcons.eye,
                  label: 'Open as recipient',
                  onTap: _openAsRecipient,
                ),
                AppButton(
                  icon: AppIcons.arrowRight,
                  label: 'Next',
                  style: AppButtonStyle.accent,
                  onTap: () => _step.value = TourStep.revoke,
                ),
              ],
            ),
          ];
        }
        return [
          AppTextField(controller: _value, label: 'New value', mono: true),
          AppSpacing.gapLg,
          _primary(
            icon: AppIcons.check,
            label: 'Save new value',
            onTap: _value.text.trim().isEmpty || busy
                ? null
                : () => _run(_changeValue, TourStep.change),
          ),
        ];
      case TourStep.revoke:
        return [
          _primary(
            icon: AppIcons.xCircle,
            label: 'Revoke link',
            style: AppButtonStyle.destructive,
            onTap: () => _run(_revoke, TourStep.done),
          ),
        ];
      case TourStep.done:
        return const [];
    }
  }

  Widget _primary({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    AppButtonStyle style = AppButtonStyle.primary,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        icon: icon,
        label: label,
        style: style,
        busy: _busy.value,
        onTap: onTap,
      ),
    );
  }

  Widget _doneCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('That\'s it').header,
          AppSpacing.gapXs,
          const Text(
            'They only ever had a link, never your data. They always saw the '
            'latest value, and lost access the moment you revoked it. Anyone '
            'who opens the link now sees that it was revoked.',
          ).muted,
          AppSpacing.gapMd,
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              icon: AppIcons.eye,
              label: 'Open as recipient',
              style: AppButtonStyle.accent,
              onTap: _openAsRecipient,
            ),
          ),
          AppSpacing.gapLg,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                icon: AppIcons.trash,
                label: 'Delete tour data',
                style: AppButtonStyle.accent,
                busy: _busy.value,
                onTap: _cleanUp,
              ),
              AppButton(
                icon: AppIcons.safe,
                label: 'Keep it',
                onTap: () => context.go(AppRoutes.vault),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The link the tour made, readable and copyable.
class _UrlBox extends StatelessWidget {
  final String url;

  const _UrlBox({required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        children: [
          Expanded(child: Text(url).mono.small.selectable),
          AppButton(
            icon: AppIcons.copy,
            tooltip: 'Copy link',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) AppToast.success(context, 'Copied link');
            },
          ),
        ],
      ),
    );
  }
}
