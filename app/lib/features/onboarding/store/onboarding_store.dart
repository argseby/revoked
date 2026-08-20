import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/invite.dart';

part 'onboarding_store.g.dart';

/// Which path a new account is taking to get a workspace: create one, or join
/// one with an invite key.
enum OnboardingChoice { undecided, create, join }

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

  @observable
  OnboardingChoice choice = OnboardingChoice.undecided;

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

  /// Back to the create-or-join choice, discarding whatever was in progress.
  @action
  void restart() {
    choice = OnboardingChoice.undecided;
    preview = null;
    error = null;
  }
}
