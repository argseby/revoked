import 'package:flutter/services.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

part 'link_search_store.g.dart';

/// What reading the clipboard did. Split three ways so the two paste entry
/// points (opening the drawer, the global Ctrl+V) each toast exactly once:
/// whichever adopts first reports [adopted]; the other sees [alreadyPresent]
/// and stays quiet.
enum ClipboardAdoption { none, alreadyPresent, adopted }

/// The "open a link" drawer: the address being typed, and the result of
/// verifying it. A singleton, so a pasted link survives the drawer closing.
// ignore: library_private_types_in_public_api
class LinkSearchStore = _LinkSearchStore with _$LinkSearchStore;

abstract class _LinkSearchStore with Store {
  _LinkSearchStore() {
    controller.addListener(_normalize);
    controller.addListener(_invalidateVerdict);
    controller.addListener(_forgetClipboardOnEdit);
  }

  final ObservableTextController controller = ObservableTextController();

  /// The field holds just the path, because the drawer renders `revoked://`
  /// as a fixed prefix; a pasted full link would otherwise read as a doubled
  /// scheme. Owned here rather than by the drawer, which comes and goes.
  void _normalize() {
    final current = controller.text;
    final stripped = stripScheme(current);
    if (stripped == current) return;
    controller.value = TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: stripped.length),
    );
  }

  /// A verdict belongs to the link it was computed for. Once the text moves on,
  /// leaving it up would let someone read "verified" against a different link.
  @action
  void _invalidateVerdict() {
    if (verdict == null && verifyError == null) return;
    if (controller.text.trim() == _verifiedInput) return;
    verdict = null;
    verifyError = null;
  }

  String _verifiedInput = '';

  @action
  void clear() {
    controller.clear();
    fromClipboard = false;
    verdict = null;
    verifyError = null;
  }

  /// True while the field holds a link adopted from the clipboard, so the
  /// drawer can say why its content just changed.
  @observable
  bool fromClipboard = false;

  String _adoptedText = '';

  /// Reads the clipboard once, at the moment the drawer opens. A valid
  /// `revoked://` link there replaces whatever the drawer still held from
  /// last time — the clipboard is almost always why the drawer was opened.
  /// Anything that is not a revoked link is left alone and unread beyond
  /// this check.
  Future<ClipboardAdoption> adoptClipboardLink() async {
    String text = '';
    try {
      text =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    } catch (_) {
      return ClipboardAdoption.none; // no clipboard access = empty
    }
    return _adoptIfLink(text);
  }

  @action
  ClipboardAdoption _adoptIfLink(String text) {
    if (text.isEmpty) return ClipboardAdoption.none;
    final uri = Uri.tryParse(text);
    if (uri == null || DeepLinks.parse(uri) == null) {
      return ClipboardAdoption.none;
    }
    final normalized = stripScheme(text);
    if (controller.text.trim() == normalized) {
      return ClipboardAdoption.alreadyPresent;
    }
    _adoptedText = normalized;
    controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    fromClipboard = true;
    return ClipboardAdoption.adopted;
  }

  /// Whether the drawer is on screen. Not observable - nothing renders
  /// it; it only stops a second Ctrl+V stacking a second drawer.
  bool isDrawerOpen = false;

  /// The notice describes where the current text came from; the moment the
  /// user edits it, it no longer does.
  @action
  void _forgetClipboardOnEdit() {
    if (fromClipboard && controller.text != _adoptedText) {
      fromClipboard = false;
    }
  }

  String stripScheme(String value) {
    var path = value;
    final prefix = '${DeepLinks.scheme}://';
    if (path.toLowerCase().startsWith(prefix)) {
      path = path.substring(prefix.length);
    }
    return path.replaceFirst(RegExp(r'^/+'), '');
  }

  @observable
  bool isVerifying = false;

  @observable
  TrustVerdict? verdict;

  @observable
  AppErrorMessage? verifyError;

  @action
  void clearResult() {
    verdict = null;
    verifyError = null;
  }

  @action
  void startVerifying() {
    isVerifying = true;
    verdict = null;
    verifyError = null;
  }

  @action
  void finishVerifying(TrustVerdict result) {
    _verifiedInput = controller.text.trim();
    verdict = result;
    isVerifying = false;
  }

  @action
  void failVerifying(Object error) {
    _verifiedInput = controller.text.trim();
    verifyError = AppErrorMessage.fromException(error);
    isVerifying = false;
  }
}
