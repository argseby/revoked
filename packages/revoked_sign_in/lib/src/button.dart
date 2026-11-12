import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'client.dart';
import 'mark.dart';
import 'panel.dart';
import 'pressable.dart';
import 'strings.dart';
import 'style.dart';

/// Opens a `revoked://` link. Returns false when nothing on this device
/// answers it.
typedef RevokedAppOpener = Future<bool> Function(Uri link);

Future<bool> _launch(Uri link) async {
  try {
    return await launchUrl(link, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}

/// The official "Continue with Revoked" button.
///
/// Pressing it calls the service's [start] route, then shows the panel with
/// the request as a QR code, a way to open the Revoked app on this device,
/// and the check code, and asks the [wait] route every two seconds until the
/// person decides. On a phone app, the Revoked app is opened right away and
/// the panel waits behind it.
///
/// [onSignedIn] receives the `wait` route's whole answer. On the web the
/// service starts its session there with a cookie, as with the web component.
/// Elsewhere the widget sends `"client": "app"` with each `wait`, and the
/// service hands the app its session in the answer (see docs/api/sign-in.md).
class RevokedSignInButton extends StatefulWidget {
  const RevokedSignInButton({
    super.key,
    required this.start,
    required this.wait,
    required this.onSignedIn,
    this.label = RevokedLabel.continueWith,
    this.theme = RevokedTheme.black,
    this.shape = RevokedShape.rounded,
    this.size = RevokedSize.medium,
    this.expand = false,
    this.locale,
    this.onProblem,
    this.httpClient,
    this.openApp,
  });

  /// The service's route that prepares a sign-in. Absolute outside the web.
  final Uri start;

  /// The service's route asked until the sign-in is finished.
  final Uri wait;

  final ValueChanged<Map<String, dynamic>> onSignedIn;

  final RevokedLabel label;
  final RevokedTheme theme;
  final RevokedShape shape;
  final RevokedSize size;

  /// Fill the available width, for login columns.
  final bool expand;

  /// English or German. Without it, the app's locale.
  final Locale? locale;

  /// Told when a sign-in ends without signing in. The button already shows
  /// the reason; this is for logging.
  final ValueChanged<RevokedSignInProblem>? onProblem;

  /// For tests, or to share the app's client.
  final http.Client? httpClient;

  /// Replaces how `revoked://` links are opened, e.g. in tests.
  final RevokedAppOpener? openApp;

  @override
  State<RevokedSignInButton> createState() => _RevokedSignInButtonState();
}

class _Session {
  _Session(this.route, this.state);
  final RawDialogRoute<void> route;
  final ValueNotifier<PanelState> state;
  String? waitKey;
  Timer? timer;
  bool asking = false;
  AppLifecycleListener? lifecycle;

  void stop() {
    timer?.cancel();
    timer = null;
  }
}

class _RevokedSignInButtonState extends State<RevokedSignInButton> {
  late RevokedSignInClient _client = _makeClient();
  final FocusNode _focus = FocusNode(debugLabel: 'RevokedSignInButton');
  bool _busy = false;
  RevokedSignInProblem? _problem;
  _Session? _session;

  static const _askEvery = Duration(seconds: 2);

  /// Opening the app on its own makes sense where the app most likely is:
  /// a phone app. A web page cannot know, so there the panel leads.
  bool get _phone => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  bool get _openAppAtOnce => _phone && !kIsWeb;

  RevokedSignInClient _makeClient() =>
      RevokedSignInClient(start: widget.start, wait: widget.wait, httpClient: widget.httpClient, asApp: !kIsWeb);

  @override
  void didUpdateWidget(RevokedSignInButton old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start || old.wait != widget.wait || old.httpClient != widget.httpClient) {
      _client.close();
      _client = _makeClient();
    }
  }

  @override
  void dispose() {
    // The button left the screen with the panel still open, e.g. because the
    // page changed: stop asking, and take the panel away after this frame.
    final session = _session;
    if (session != null) {
      _session = null;
      session.stop();
      session.lifecycle?.dispose();
      final route = session.route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    _client.close();
    _focus.dispose();
    super.dispose();
  }

  RevokedStrings get _strings => RevokedStrings.forLocale(widget.locale ?? Localizations.maybeLocaleOf(context));

  void _announce(String message) {
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
  }

  Future<bool> _open(Uri link) => (widget.openApp ?? _launch)(link);

  Future<void> _press() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    _announce(_strings.opening);
    try {
      final start = await _client.begin();
      if (!mounted) return;
      _show(start);
    } catch (err) {
      debugPrint('revoked_sign_in: $err');
      if (!mounted) return;
      final session = _session;
      if (session != null) {
        session.state.value = const PanelEnded(RevokedSignInProblem.failed);
      } else {
        setState(() => _problem = RevokedSignInProblem.failed);
      }
      widget.onProblem?.call(RevokedSignInProblem.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(RevokedSignInStart start) {
    final session = _session ?? _openPanel();
    session.waitKey = start.wait;
    session.state.value = PanelWaiting(start);
    session.stop();
    session.timer = Timer.periodic(_askEvery, (_) => _ask());
    if (_openAppAtOnce) _open(start.appLink);
  }

  _Session _openPanel() {
    final strings = _strings;
    final title = strings.label(widget.label);
    final textStyle = DefaultTextStyle.of(context).style;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final state = ValueNotifier<PanelState>(const PanelEnded(RevokedSignInProblem.failed));
    late final _Session session;
    final route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: strings.close,
      barrierColor: const Color(0x99000000),
      transitionDuration: still ? Duration.zero : const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) => RevokedSignInPanel(
        state: state,
        strings: strings,
        title: title,
        phone: _phone,
        textStyle: textStyle,
        onOpenHere: _open,
        onStartAgain: () {
          state.value = PanelEnded((state.value as PanelEnded).problem, restarting: true);
          _press();
        },
        onClose: () => _closePanel(session),
      ),
    );
    session = _Session(route, state);
    // A phone app sleeps while Revoked is open, so ask the moment it is back.
    session.lifecycle = AppLifecycleListener(onResume: _ask);
    _session = session;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() => _closed(session));
    return session;
  }

  void _closePanel(_Session session) {
    final route = session.route;
    if (route.isCurrent) {
      route.navigator?.pop();
    } else if (route.isActive) {
      route.navigator?.removeRoute(route);
    }
    _closed(session);
  }

  void _closed(_Session session) {
    if (_session != session) return;
    session.stop();
    session.lifecycle?.dispose();
    _session = null;
    // Back where the person was.
    if (mounted) _focus.requestFocus();
  }

  Future<void> _ask() async {
    final session = _session;
    final key = session?.waitKey;
    if (session == null || key == null || session.timer == null || session.asking) return;
    session.asking = true;
    try {
      final answer = await _client.ask(key);
      if (_session != session || session.timer == null || !mounted) return;
      switch (answer) {
        case RevokedWaitPending():
          break;
        case RevokedWaitExpired():
          session.stop();
          session.state.value = const PanelEnded(RevokedSignInProblem.expired);
          widget.onProblem?.call(RevokedSignInProblem.expired);
        case RevokedWaitRefused(:final error):
          session.stop();
          _closePanel(session);
          final problem = error == 'access_denied' ? RevokedSignInProblem.declined : RevokedSignInProblem.failed;
          setState(() => _problem = problem);
          widget.onProblem?.call(problem);
        case RevokedWaitSignedIn(:final body):
          session.stop();
          _closePanel(session);
          widget.onSignedIn(body);
      }
    } finally {
      session.asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    final spec = RevokedSizeSpec.of(widget.size);
    final base = DefaultTextStyle.of(context).style;
    final highContrast = MediaQuery.highContrastOf(context);
    final palette = RevokedPalette.resolve(
      widget.theme,
      brightness: MediaQuery.platformBrightnessOf(context),
      text: base.color ?? const Color(0xFF191C20),
      highContrast: highContrast,
    );
    final icon = widget.label == RevokedLabel.iconOnly;
    final label = strings.label(widget.label);
    final scaler = MediaQuery.textScalerOf(context);
    final markSize = scaler.scale(icon ? spec.iconMarkSize : spec.markSize);
    final radius = widget.shape == RevokedShape.pill ? 999.0 : spec.radius;
    // Android asks for 48-point touch areas; the drawing stays at its size
    // and the area around it reacts too, as Material buttons do.
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.fuchsia => const Size(48, 48),
      _ => Size.zero,
    };

    Widget button = Pressable(
      focusNode: _focus,
      semanticLabel: icon ? label : null,
      minTapSize: touch,
      onPressed: _press,
      builder: (context, s) {
        final background = s.pressed ? palette.pressed : (s.hovered ? palette.hover : palette.background);
        final mark = RevokedMark(size: markSize, color: palette.foreground, pulsing: _busy);
        return FocusRing(
          visible: s.focused,
          radius: radius,
          highContrast: highContrast,
          child: Container(
            constraints: BoxConstraints(minHeight: spec.minHeight, minWidth: spec.minHeight),
            width: icon ? spec.minHeight : null,
            padding: EdgeInsets.symmetric(horizontal: icon ? 0 : spec.paddingX, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              border: Border.all(color: palette.edge),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: icon
                ? Center(child: mark)
                : Row(
                    mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: spec.gap,
                    children: [
                      mark,
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: base.copyWith(
                            fontSize: spec.fontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: spec.fontSize * 0.005,
                            color: palette.foreground,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );

    if (widget.expand && !icon) button = SizedBox(width: double.infinity, child: button);

    final problem = _problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        button,
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ProblemLine(
              text: switch (problem) {
                RevokedSignInProblem.declined => strings.declined,
                RevokedSignInProblem.expired => strings.expired,
                RevokedSignInProblem.failed => strings.failed,
              },
              color: palette.error,
              style: base,
            ),
          ),
      ],
    );
  }
}

/// The reason in words, under the button, with an icon: never colour alone.
class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.text, required this.color, required this.style});

  final String text;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.textScalerOf(context).scale(14);
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Padding(
              padding: EdgeInsets.only(top: size * 0.2),
              child: ExcludeSemantics(
                child: CustomPaint(size: Size.square(size), painter: _WarnPainter(color)),
              ),
            ),
            Flexible(
              child: Text(
                text,
                style: style.copyWith(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  color: color,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarnPainter extends CustomPainter {
  _WarnPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()..color = color;
    final mark = Paint()..blendMode = BlendMode.clear;
    // The exclamation mark is cut out of the circle.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(Offset(s / 2, s / 2), s * 7 / 16, fill);
    canvas.drawRect(Rect.fromLTWH(s * 0.453, s * 0.28, s * 0.094, s * 0.31), mark);
    canvas.drawRect(Rect.fromLTWH(s * 0.453, s * 0.67, s * 0.094, s * 0.094), mark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WarnPainter old) => old.color != color;
}
