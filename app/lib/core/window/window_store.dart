import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobx/mobx.dart';

part 'window_store.g.dart';

/// The desktop window, when the app draws its own title bar.
///
/// The Linux runner hands over a window with nothing in the title bar slot, so
/// the app's top bar *is* the title bar: it has to drag the window and carry
/// the minimize/maximize/close buttons. Platforms that keep their own
/// decorations leave [ownsTitleBar] false and nothing extra is drawn.
// ignore: library_private_types_in_public_api
class WindowStore = _WindowStore with _$WindowStore;

abstract class _WindowStore with Store {
  static const MethodChannel _channel = MethodChannel('revoked/window');

  /// How far the pointer travels inside the bar before the press counts as
  /// dragging the window rather than pressing what sits under it.
  static const double _dragSlop = 4;

  static const Duration _doubleClick = Duration(milliseconds: 400);

  @observable
  bool ownsTitleBar = false;

  @observable
  bool isMaximized = false;

  Offset? _dragOrigin;
  Offset? _lastPressAt;
  DateTime? _lastPressWhen;
  bool _dragging = false;

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isLinux) return;
    _channel.setMethodCallHandler(_onPlatformCall);
    final owns = await _invoke<bool>('ownsTitleBar') ?? false;
    final maximized = await _invoke<bool>('isMaximized') ?? false;
    runInAction(() {
      ownsTitleBar = owns;
      isMaximized = maximized;
    });
  }

  /// The pointer went down in the drag area. A second press in the same spot
  /// inside the double-click window is what a title bar treats as maximize.
  void pressed(Offset position) {
    final previousAt = _lastPressAt;
    final previousWhen = _lastPressWhen;
    final now = DateTime.now();

    _dragOrigin = position;
    _dragging = false;
    _lastPressAt = position;
    _lastPressWhen = now;

    if (previousAt == null || previousWhen == null) return;
    if (now.difference(previousWhen) > _doubleClick) return;
    if ((position - previousAt).distance > _dragSlop) return;

    _lastPressWhen = null;
    toggleMaximize();
  }

  void moved(Offset position) {
    final origin = _dragOrigin;
    if (_dragging || origin == null) return;
    if ((position - origin).distance < _dragSlop) return;
    _dragging = true;
    _invoke<void>('startDrag');
  }

  void released() {
    _dragOrigin = null;
    _dragging = false;
  }

  void minimize() => _invoke<void>('minimize');

  void toggleMaximize() => _invoke<void>('toggleMaximize');

  void close() => _invoke<void>('close');

  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method != 'maximizedChanged') return;
    runInAction(() => isMaximized = call.arguments as bool? ?? false);
  }

  /// A window the platform still decorates has no handler on the other end,
  /// and a window that is already closing answers with an error. Neither is
  /// worth an exception on a button press.
  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
