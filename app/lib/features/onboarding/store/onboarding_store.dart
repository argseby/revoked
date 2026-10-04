import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/invite.dart';

part 'onboarding_store.g.dart';

/// Which path a new account is taking to get a workspace: create one, or join
/// one with an invite key. Creating is where it starts - most people arrive
/// without an invite, and one who has a link is shown it by its own route.
enum OnboardingChoice { create, join }

/// What a new workspace is called unless the person names it otherwise.
const defaultWorkspaceName = 'Personal';

/// `max.mustermann+post@example.com` -> `Max Mustermann`. Empty when the
/// address has nothing before the @ to go on.
String nameFromEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return '';
  final local = email.substring(0, at).split('+').first;
  return local
      .split(RegExp(r'[._\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// First-run state. A singleton like every other store, so a half-typed name
/// or a pasted key survives a rebuild.
// ignore: library_private_types_in_public_api
class OnboardingStore = _OnboardingStore with _$OnboardingStore;

abstract class _OnboardingStore with Store {
  final ObservableTextController nameController = ObservableTextController();
  final ObservableTextController keyController = ObservableTextController();

  /// The display name on the signing identity provisioned with the workspace.
  final ObservableTextController identityNameController =
      ObservableTextController();

  /// The address the fields were last filled in for, so a rebuild keeps what
  /// the person typed over the suggestion.
  String? _prefilledFor;

  @observable
  OnboardingChoice choice = OnboardingChoice.create;

  @observable
  bool isBusy = false;

  @observable
  String? error;

  /// What the pasted key grants, shown before it is accepted.
  @observable
  InvitePreview? preview;

  @observable
  bool isPreviewing = false;

  @action
  void choose(OnboardingChoice value) => choice = value;

  @action
  void fail(String message) => error = message;

  @action
  void startBusy() {
    isBusy = true;
    error = null;
  }

  @action
  void stopBusy([String? message]) {
    isBusy = false;
    error = message;
  }

  @action
  void startPreview() {
    isPreviewing = true;
    error = null;
  }

  @action
  void finishPreview({InvitePreview? result, String? message}) {
    isPreviewing = false;
    preview = result;
    error = message;
  }

  @action
  void clearPreview() {
    preview = null;
    error = null;
  }

  /// Back to creating a workspace, discarding whatever was in progress.
  @action
  void restart() {
    choice = OnboardingChoice.create;
    preview = null;
    error = null;
  }

  /// Suggests both names, so creating a workspace is one tap for someone
  /// happy with them: [defaultWorkspaceName], and a name read from the part
  /// of [email] before the @. Both stay editable - the second is what
  /// everyone shared with sees, which is why it is shown, not just used.
  void prefill(String email) {
    if (_prefilledFor == email) return;
    _prefilledFor = email;
    nameController.text = defaultWorkspaceName;
    identityNameController.text = nameFromEmail(email);
  }

  /// Done: nothing typed here carries over to the next account.
  void finish() {
    stopBusy();
    restart();
    _prefilledFor = null;
    nameController.clear();
    identityNameController.clear();
    keyController.clear();
  }
}
