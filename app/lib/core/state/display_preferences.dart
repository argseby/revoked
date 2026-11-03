import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display preferences that are not the theme, kept on the device.
///
/// Observable, so the app's text size and motion follow a change at once.
/// How much a screen says is not here: that is the Developer feature, kept
/// on the account so every device agrees.
abstract final class DisplayPreferences {
  static const _textScaleKey = 'text_scale';
  static const _reduceMotionKey = 'reduce_motion';

  /// The in-app text sizes offered, on top of the system's own setting.
  static const textScales = [1.0, 1.25, 1.5, 1.75, 2.0];

  static final Observable<double> _textScale = Observable(1.0);
  static final Observable<bool> _reduceMotion = Observable(false);

  /// Multiplies the system's text size. 1.0 leaves it as the system has it.
  static double get textScale => _textScale.value;

  /// Turns animation off even when the system has not asked for that. Off
  /// means "as the system says", never "animate regardless".
  static bool get reduceMotion => _reduceMotion.value;

  /// Reads what an earlier run chose. Called once at startup.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scale = prefs.getDouble(_textScaleKey);
      runInAction(() {
        _textScale.value = textScales.contains(scale) ? scale! : 1.0;
        _reduceMotion.value = prefs.getBool(_reduceMotionKey) ?? false;
      });
    } catch (_) {
      // Unreadable is the same as nothing chosen.
    }
  }

  static Future<void> setTextScale(double scale) async {
    final next = textScales.contains(scale) ? scale : 1.0;
    runInAction(() => _textScale.value = next);
    await _write((p) => p.setDouble(_textScaleKey, next));
  }

  static Future<void> setReduceMotion(bool reduce) async {
    runInAction(() => _reduceMotion.value = reduce);
    await _write((p) => p.setBool(_reduceMotionKey, reduce));
  }

  static Future<void> _write(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // Without storage it holds for this run only.
    }
  }
}
