import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/identity_status_assertion.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/value_kind.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_value_row.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/file_view_sheet.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/requirement_list.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/bookmarks/view/bookmark_groups_sheet.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PublicShareScreen extends StatefulWidget {
  final String shareSlug;
  final String? origin;

  const PublicShareScreen({super.key, required this.shareSlug, this.origin});

  @override
  State<PublicShareScreen> createState() => _PublicShareScreenState();
}

class _PublicShareScreenState extends State<PublicShareScreen> {
  SharesStore get _store => Stores.shares;

  bool get _requiresHandshake =>
      _store.shareProbe?['requireHandshake'] as bool? ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.origin != null) {
      Stores.domainVerification.prewarm(
        Uri.tryParse('https://${widget.origin!}')?.host ?? '',
      );
    }
    _store.resetShareView();
    _probeLink();
    if (Stores.auth.isAuthenticated) Stores.bookmarks.load();
  }

  bool get _isForeign => !Stores.api.isOwnOrigin(widget.origin);

  /// Stored the way a deep link names the server: empty for this one.
  String get _bookmarkOrigin => _isForeign ? widget.origin! : '';

  Future<void> _toggleBookmark() async {
    final bookmarks = Stores.bookmarks;
    final existing = bookmarks.find(
      origin: _bookmarkOrigin,
      slug: widget.shareSlug,
    );
    if (existing != null) {
      await showBookmarkGroupsSheet(
        context,
        bookmarkId: existing.id,
        offerRemove: true,
      );
      return;
    }
    final ok = await bookmarks.add(
      user: Stores.auth.userId,
      origin: _bookmarkOrigin,
      slug: widget.shareSlug,
      label: _store.shareProbe?['label'] as String? ?? '',
    );
    if (!mounted) return;
    if (ok) {
      AppToast.success(
        context,
        'Saved to Share → Bookmarks',
        subtitle: 'Tap Bookmarked to add it to a group.',
      );
    } else {
      AppToast.error(
        context,
        'Could not bookmark this share',
        subtitle: bookmarks.error?.description,
      );
    }
  }

  Widget _bookmarkButton() {
    final bookmarks = Stores.bookmarks;
    final saved =
        bookmarks.find(origin: _bookmarkOrigin, slug: widget.shareSlug) != null;
    return AppButton(
      icon: saved ? AppIcons.bookmarkFill : AppIcons.bookmark,
      label: saved ? 'Bookmarked' : 'Bookmark',
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      busy: bookmarks.isSaving,
      onTap: _toggleBookmark,
    );
  }

  String _handshakeKey() => 'handshake_link_${widget.shareSlug}';

  Future<String?> _loadStoredHandshake() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_handshakeKey());
  }

  Future<void> _persistHandshake(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handshakeKey(), token);
  }

  List<RequirementItem> _gateRequirements() {
    final requiresPassword =
        _store.shareProbe?['requiresPassword'] as bool? ?? false;
    final hasIdentities = Stores.identities.identities.isNotEmpty;

    return [
      if (requiresPassword)
        RequirementItem(
          icon: AppIcons.lock,
          title: 'Password Required',
          status: _store.sharePassword.text.isNotEmpty
              ? RequirementStatus.ready
              : RequirementStatus.pending,
          description: _store.sharePassword.text.isNotEmpty
              ? 'Password entered.'
              : 'Enter the password provided by the sender.',
        ),
      if (_requiresHandshake)
        RequirementItem(
          icon: AppIcons.personBoundingBox,
          title: 'Identity Verification',
          status: _isForeign
              ? RequirementStatus.blocked
              : _store.shareIdentityId != null
              ? RequirementStatus.ready
              : hasIdentities
              ? RequirementStatus.pending
              : RequirementStatus.blocked,
          description: _isForeign
              ? 'Cross-server identity verification is not supported yet.'
              : _store.shareIdentityId != null
              ? 'Identity selected.'
              : hasIdentities
              ? 'Select an identity to verify ownership.'
              : 'No identity found on this server.',
        ),
    ];
  }

  List<TrustCheck> _shareTrustChecks() {
    final sharer = _store.shareProbe?['sharer'];
    final fp = sharer is Map ? (sharer['fingerprint'] as String? ?? '') : '';
    final signed = fp.isNotEmpty;

    if (!signed) {
      return const [
        TrustCheck(
          label: 'Sender identity',
          value: 'Unsigned',
          state: TrustCheckState.failed,
          detail: 'No identity is attached to verify the creator.',
        ),
      ];
    }

    final verdict = _store.shareTrustVerdict;
    final checking = _store.isVerifyingShareTrust && verdict == null;
    final domain = verdict?.domain ?? '';

    final TrustCheckState state;
    if (checking) {
      state = TrustCheckState.checking;
    } else if (verdict?.state == TrustState.verified) {
      state = TrustCheckState.verified;
    } else if (verdict?.state == TrustState.spoofed) {
      state = TrustCheckState.spoofed;
    } else if (verdict?.state == TrustState.revoked) {
      state = TrustCheckState.revoked;
    } else {
      state = TrustCheckState.failed;
    }

    final shortFp = fp.length > 16 ? '${fp.substring(0, 8)}…' : fp;
    final name = sharer['name'] as String? ?? '';
    return [
      TrustCheck(
        label: 'Server domain',
        value: domain.isEmpty ? 'No domain declared' : domain,
        state: state,
        detail: checking ? null : verdict?.reason,
      ),
      TrustCheck(
        label: 'Sender identity',
        value: name.isEmpty ? shortFp : '$name · $shortFp',
        state: state,
        detail: state == TrustCheckState.verified
            ? 'Signed by the key published in DNS.'
            : null,
      ),
      if (widget.origin != null)
        TrustCheck(
          label: 'Link origin',
          value: widget.origin!,
          state: checking
              ? TrustCheckState.checking
              : Uri.tryParse('https://${widget.origin!}')?.host == domain
              ? state
              : TrustCheckState.failed,
          detail: Uri.tryParse('https://${widget.origin!}')?.host == domain
              ? null
              : 'The link points at a different server than the sender '
                    'claims to be.',
        ),
    ];
  }

  Future<void> _verifyShareTrust() async {
    final probe = _store.shareProbe;
    final sharer = probe?['sharer'];
    if (sharer is! Map || sharer['fingerprint'] == null) {
      _store.finishShareTrust(null);
      return;
    }
    final serverBlock = probe?['server'];
    final domain = serverBlock is Map
        ? (serverBlock['domain'] as String? ?? '')
        : '';

    final cached = Stores.domainVerification.cachedVerdict(
      claimedDomain: domain,
      identityFingerprint: sharer['fingerprint'] as String? ?? '',
    );
    _store.startShareTrust();
    if (cached != null) _store.seedShareTrust(cached);
    try {
      final verdict = await Stores.domainVerification.verify(
        claimedDomain: domain,
        identityFingerprint: sharer['fingerprint'] as String? ?? '',
        parentSignatureHex: sharer['parentSignature'] as String? ?? '',
        statusAssertion: IdentityStatusAssertion.fromJson(
          sharer['statusAssertion'],
        ),
      );
      _store.finishShareTrust(verdict);
    } catch (e) {
      _store.finishShareTrust(
        TrustVerdict.unverified(
          domain: domain,
          reason: 'Domain verification could not complete.',
        ),
      );
    }
  }

  Future<void> _probeLink() async {
    runInAction(() {
      _store.isLoadingShare = true;
      _store.shareTerminalError = null;
    });

    try {
      _store.shareProbe = await Stores.shares.getPublicLinkProbe(
        widget.shareSlug,
        origin: widget.origin,
      );
      unawaited(_verifyShareTrust());

      final requiresPassword =
          _store.shareProbe!['requiresPassword'] as bool? ?? false;
      final requireHandshake =
          _store.shareProbe!['requireHandshake'] as bool? ?? false;

      if (!requiresPassword && !requireHandshake) {
        await _unlock();
        return;
      }
      if (requireHandshake && !_isForeign) {
        await Stores.identities.loadIdentities();
        _store.shareIdentityId ??= Stores.identities.primaryIdentity?.id;
      }
      runInAction(() => _store.isLoadingShare = false);
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      runInAction(() {
        _store.shareTerminalError = msg;
        _store.isLoadingShare = false;
      });
    } catch (e) {
      runInAction(() {
        _store.shareTerminalError = AppErrorMessage.fromException(e);
        _store.isLoadingShare = false;
      });
    }
  }

  Future<void> _unlock() async {
    runInAction(() {
      _store.isUnlockingShare = true;
      _store.sharePasswordHint = null;
    });

    try {
      final handshake = await _loadStoredHandshake();
      SignedChallenge? challenge;
      final requireHandshake =
          _store.shareProbe?['requireHandshake'] as bool? ?? false;
      if (requireHandshake &&
          handshake == null &&
          _store.shareIdentityId != null &&
          _store.shareIdentityId!.isNotEmpty) {
        challenge = await Stores.handshake.prepare(
          scope: HandshakeService.scopeLink,
          slug: widget.shareSlug,
          identityId: _store.shareIdentityId!,
        );
      }

      final response = await Stores.shares.submitPublicLink(
        widget.shareSlug,
        password: _store.sharePassword.text.isEmpty
            ? null
            : _store.sharePassword.text,
        handshakeToken: handshake,
        identityId: _store.shareIdentityId,
        challengeNonce: challenge?.nonce,
        challengeSignature: challenge?.signature,
      );

      final newHandshake = response.headers['x-handshake-token'];
      if (newHandshake != null && newHandshake.isNotEmpty) {
        await _persistHandshake(newHandshake);
      }

      runInAction(() {
        _store.shareData = response.body as Map<String, dynamic>;
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    } on ApiException catch (e) {
      final msg = AppErrorMessage.fromException(e);
      runInAction(() {
        if (msg.isTerminal) {
          _store.shareTerminalError = msg;
        } else {
          _store.sharePasswordHint = msg.description;
        }
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    } catch (e) {
      runInAction(() {
        _store.sharePasswordHint = e.toString();
        _store.isUnlockingShare = false;
        _store.isLoadingShare = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _store.shareProbe?['label'] as String? ?? '';
    final gated =
        !_store.isLoadingShare &&
        _store.shareTerminalError == null &&
        _store.shareData == null &&
        _store.shareProbe != null;

    final data = _store.shareData;
    final stamped = (data?['watermark'] as String? ?? '').isNotEmpty;
    final protected =
        (_store.shareProbe?['requiresPassword'] as bool? ?? false) ||
        _requiresHandshake;
    return AppFlowScaffold(
      title: label.isEmpty ? 'Shared link' : label,
      subtitle: data != null
          ? ['Shared link', 'read-only', if (stamped) 'watermarked'].join(' · ')
          : gated && protected
          ? 'Protected link · unlock to see what was shared'
          : 'Shared link',
      closeLabel: 'Close',
      onClose: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.vault);
        }
      },
      actions: [
        // A dead link is not worth keeping, and a bookmark lives on an
        // account.
        if (Stores.auth.isAuthenticated &&
            _store.shareProbe != null &&
            _store.shareTerminalError == null)
          _bookmarkButton(),
      ],
      bottomBar: gated
          ? AppActionBar(
              children: [
                AppButton(
                  label: 'Unlock',
                  icon: AppIcons.lock,
                  busy: _store.isUnlockingShare,
                  onTap:
                      (_requiresHandshake &&
                          (_isForeign || _store.shareIdentityId == null))
                      ? null
                      : _unlock,
                ),
              ],
            )
          : null,
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_store.isLoadingShare) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSpinner(large: true),
            AppSpacing.gapMd,
            const Text('Opening the shared link…').muted,
          ],
        ),
      );
    }

    if (_store.shareTerminalError != null) {
      final msg = _store.shareTerminalError!;
      return AppStatusMessage(
        icon: AppIcons.exclamationOctagon,
        accent: theme.colorScheme.error,
        title: msg.title,
        message: msg.description,
        actions: [
          AppButton(
            icon: AppIcons.arrowClockwise,
            label: 'Try again',
            style: AppButtonStyle.accent,
            onTap: _probeLink,
          ),
        ],
      );
    }

    if (_store.shareData != null) {
      return _buildContent(theme, _store.shareData!);
    }

    if (_store.shareProbe != null) {
      final requiresPassword =
          _store.shareProbe!['requiresPassword'] as bool? ?? false;
      return _buildPasswordGate(theme, requiresPassword);
    }

    return const SizedBox.shrink();
  }

  /// A titled block that holds one widget of its own — a panel or a form
  /// field — rather than rows.
  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListHeader(title: title),
          child,
        ],
      ),
    );
  }

  Widget _buildPasswordGate(ThemeData theme, bool requiresPassword) {
    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        _section('Sender', TrustPanel(checks: _shareTrustChecks())),
        _section(
          'To open this link',
          RequirementList(items: _gateRequirements()),
        ),
        if (requiresPassword)
          _section(
            'Password',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _store.sharePassword,
                  obscureText: true,
                  hint: 'Enter the password the sender gave you',
                  onSubmitted: (_) => _unlock(),
                ),
                if (_store.sharePasswordHint != null) ...[
                  AppSpacing.gapXs,
                  AppErrorText(_store.sharePasswordHint!),
                ],
              ],
            ),
          ),
        if (_requiresHandshake && _isForeign)
          const AppAlert(
            destructive: true,
            content: Text(
              'This link lives on another server. Verifying your identity '
              'across servers isn’t supported yet.',
            ),
          )
        else if (_requiresHandshake)
          _section(
            'Your identity',
            IdentityPicker(
              selectedId: _store.shareIdentityId,
              onChanged: (v) => runInAction(() => _store.shareIdentityId = v),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, Map<String, dynamic> data) {
    final rawSections = (data['sections'] as List<dynamic>?) ?? [];
    final rawRecords = (data['records'] as List<dynamic>?) ?? [];

    final records = rawRecords.whereType<Map<String, dynamic>>().toList();
    final sections = rawSections.whereType<Map<String, dynamic>>().toList();

    // A section arrives as the ids of its records; the records themselves come
    // once, in the top-level list, and only those the share still grants.
    final byId = {
      for (final r in records)
        if (r['id'] case final String id) id: r,
    };
    List<String> memberIds(Map<String, dynamic> section) =>
        (section['records'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    final inSections = {for (final s in sections) ...memberIds(s)};
    final loose = records.where((r) => !inSections.contains(r['id'])).toList();
    // Set for a stamped share: its files come back stamped, and the same line
    // is laid over the values so a screenshot of plain text carries it too.
    final stamp = data['watermark'] as String? ?? '';

    Widget row(Map<String, dynamic> r) => _SharedRecordRow(
      record: r,
      slug: widget.shareSlug,
      origin: widget.origin,
    );

    final groups = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in sections)
          AppListGroup(
            title: s['name'] as String? ?? 'Section',
            noun: 'items',
            children: [
              for (final id in memberIds(s))
                if (byId[id] != null) row(byId[id]!),
              if (memberIds(s).every((id) => byId[id] == null))
                const AppDetailRow(
                  icon: AppIcons.info,
                  label: 'This section is empty',
                ),
            ],
          ),
        if (loose.isNotEmpty)
          AppListGroup(
            title: sections.isEmpty ? 'Shared with you' : 'Other information',
            noun: 'items',
            children: [for (final r in loose) row(r)],
          ),
        if (records.isEmpty && sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.gigantic),
            child: Center(
              child: const Text(
                'This link doesn’t contain any information yet.',
              ).muted,
            ),
          ),
      ],
    );
    final content = stamp.isEmpty
        ? groups
        : Stack(
            children: [
              groups,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _StampPainter(
                        line: stamp,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    final sender = _section('Sender', TrustPanel(checks: _shareTrustChecks()));
    // Side by side on a wide window: the shared values, and who sent them.
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: content),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 2, child: sender),
            ],
          )
        else ...[
          sender,
          content,
        ],
      ],
    );
  }
}

/// Tiles the share's stamp line diagonally across everything it shows, the
/// way the server stamps a file: one in a corner crops away in seconds.
class _StampPainter extends CustomPainter {
  final String line;
  final Color color;

  const _StampPainter({required this.line, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(
        text: line,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final stepX = text.width + 48;
    const stepY = 64.0;
    // Half the diagonal reaches every corner whatever the angle.
    final reach =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 6);
    var row = 0;
    for (var y = -reach; y < reach; y += stepY, row++) {
      final shift = row.isOdd ? stepX / 2 : 0.0;
      for (var x = -reach - shift; x < reach; x += stepX) {
        text.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.line != line || old.color != color;
}

/// What a stamped copy is, read from its bytes: the server re-encodes what it
/// stamps, so the copy is not always the type the record was stored as.
({String mime, String ext})? _stampedType(Uint8List bytes) {
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) {
    return (mime: 'image/png', ext: '.png');
  }
  if (startsWith(const [0xFF, 0xD8, 0xFF])) {
    return (mime: 'image/jpeg', ext: '.jpg');
  }
  if (startsWith(const [0x25, 0x50, 0x44, 0x46])) {
    return (mime: 'application/pdf', ext: '.pdf');
  }
  return null;
}

/// One shared value: its kind, the value, and what can be done with it. A
/// file offers View and Download; a hidden value stays masked until shown.
class _SharedRecordRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final String slug;
  final String? origin;

  const _SharedRecordRow({
    required this.record,
    required this.slug,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _buildRow(context));
  }

  /// Fetches the file once per open share; View and Download both use it.
  Future<Uint8List?> _fileBytes(BuildContext context) async {
    final recordId = record['id'] as String? ?? '';
    final token = record['downloadToken'] as String? ?? '';
    if (recordId.isEmpty || token.isEmpty) {
      AppToast.error(
        context,
        'File unavailable',
        subtitle: 'Open the link again to request a new download.',
      );
      return null;
    }

    final bytes = await Stores.shares.downloadSharedFile(
      origin: origin,
      slug: slug,
      recordId: recordId,
      token: token,
    );
    if (bytes == null && context.mounted) {
      // A stamped share refuses a file it cannot stamp; say that, not that
      // the token ran out.
      final failure = Stores.shares.sharedFileFailure;
      AppToast.error(
        context,
        failure?.title ?? 'Couldn’t load the file',
        subtitle:
            failure?.description ??
            'The download may have expired or already been used.',
      );
    }
    return bytes;
  }

  /// The name and type to show and save [bytes] under. A stamped copy is
  /// named after what it is, not after the original it was made from.
  ({String filename, String? mime}) _fileIdentity(Uint8List bytes) {
    final filename = record['filename'] as String? ?? 'file';
    final mime = record['mime'] as String?;
    final stamped =
        (Stores.shares.shareData?['watermark'] as String? ?? '').isNotEmpty;
    final type = stamped ? _stampedType(bytes) : null;
    if (type == null) return (filename: filename, mime: mime);
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    return (filename: '$stem${type.ext}', mime: type.mime);
  }

  Future<void> _viewFile(BuildContext context) async {
    final bytes = await _fileBytes(context);
    if (bytes == null || !context.mounted) return;
    final file = _fileIdentity(bytes);
    await viewFile(
      context,
      bytes: bytes,
      filename: file.filename,
      mime: file.mime,
    );
  }

  Future<void> _downloadFile(BuildContext context) async {
    final bytes = await _fileBytes(context);
    if (bytes == null || !context.mounted) return;
    final file = _fileIdentity(bytes);

    final ok = await saveFileToDevice(
      bytes: bytes,
      filename: file.filename,
      mime: file.mime,
    );
    if (ok && context.mounted) AppToast.success(context, 'File saved');
  }

  Widget _buildRow(BuildContext context) {
    final label = record['label'] as String? ?? 'Record';
    final key = record['key'] as String? ?? '';
    final value = record['value'] as String? ?? '';
    final type = record['type'] as String? ?? 'text';
    final format = record['format'] as String? ?? 'default';
    final filename = record['filename'] as String? ?? 'file';
    final size = (record['size'] as num?)?.toInt() ?? 0;
    final mime = (record['mime'] as String? ?? '').split(';').first;

    final hidden = format == 'hidden';
    final obscured = hidden && !Stores.shares.revealedShareValues.contains(key);
    final kind = valueKindOf(
      type: type,
      value: value,
      key: key,
      label: label,
      mime: mime,
      filename: filename,
    );

    if (type != 'file') {
      return AppValueRow(
        label: label,
        value: value,
        kind: kind,
        masked: hidden ? obscured : null,
        onToggleMask: hidden ? () => Stores.shares.toggleShareValue(key) : null,
      );
    }

    final recordId = record['id'] as String? ?? '';
    final busy = Stores.shares.downloadingShareRecordIds.contains(recordId);
    return AppValueRow(
      label: label,
      value: filename,
      kind: kind,
      display: '$filename · ${formatBytes(size)}',
      masked: hidden ? obscured : null,
      actions: [
        if (hidden)
          AppButton(
            icon: obscured ? AppIcons.eye : AppIcons.eyeSlash,
            tooltip: obscured ? 'Show file name' : 'Hide file name',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () => Stores.shares.toggleShareValue(key),
          ),
        AppButton(
          icon: AppIcons.eye,
          label: 'View',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          busy: busy,
          onTap: busy ? null : () => _viewFile(context),
        ),
        AppButton(
          icon: AppIcons.download,
          tooltip: 'Download',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: busy ? null : () => _downloadFile(context),
        ),
      ],
    );
  }
}
