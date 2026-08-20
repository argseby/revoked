import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';

/// Radio-style picker over the signed-in user's cryptographic identities.
///
/// Used wherever a flow needs the user to choose which identity signs an
/// action — creating a verified share, unlocking a handshake-gated link. It
/// self-loads identities from the store and shows each one's short fingerprint
/// and (when present) the domain it was issued under. Deliberately no
/// "verified" mark: whether that domain's DNS really pins the issuing root is
/// a live check the picker does not run, so it must not claim the answer.
class IdentityPicker extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// Adds a "No signing identity" option (e.g. an unsigned share). When false,
  /// only real identities are selectable.
  final bool allowNone;

  /// When set, identities whose `domainAtIssue` differs are dimmed and
  /// unselectable — used for `from_root`-scoped flows.
  final String? requireDomain;

  const IdentityPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.allowNone = false,
    this.requireDomain,
  });

  @override
  State<IdentityPicker> createState() => _IdentityPickerState();
}

class _IdentityPickerState extends State<IdentityPicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = Stores.identities;
      if (store.identities.isEmpty) store.loadIdentities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final ids = Stores.identities.identities;
        if (ids.isEmpty) {
          return const Text(
            'No cryptographic identities yet — create one in Account to sign '
            'and verify.',
          ).muted.small;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in ids)
              _tile(
                scheme,
                selected: id.id == widget.selectedId,
                enabled:
                    widget.requireDomain == null ||
                    id.domainAtIssue == widget.requireDomain,
                title: id.name,
                subtitle: id.domainAtIssue.isNotEmpty
                    ? '${id.shortFingerprint} · issued by ${id.domainAtIssue}'
                    : id.shortFingerprint,
                onTap: () => widget.onChanged(id.id),
              ),
            if (widget.allowNone)
              _tile(
                scheme,
                selected: widget.selectedId == null,
                enabled: true,
                title: 'No signing identity',
                subtitle: 'Share without a verifiable origin',
                onTap: () => widget.onChanged(null),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(
    ColorScheme scheme, {
    required bool selected,
    required bool enabled,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: InkWell(
          borderRadius: AppRadius.allMd,
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.35)
                  : null,
              borderRadius: AppRadius.allMd,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title).small,
                      AppSpacing.gapXxs,
                      Text(subtitle).muted.small,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
