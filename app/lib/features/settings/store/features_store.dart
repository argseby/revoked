import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';

part 'features_store.g.dart';

/// Which parts of the app this account sees.
///
/// A screen shows a feature only where two things agree: the person chose it
/// ([isOn], stored on the account) and the workspace lets them use it
/// ([isPermitted], from their member record). The first is a preference; the
/// second is the server's boundary, enforced there whatever is chosen here.
// ignore: library_private_types_in_public_api
class FeaturesStore = _FeaturesStore with _$FeaturesStore;

abstract class _FeaturesStore with Store {
  final ApiClient _api;
  final User? Function() _user;
  final void Function(User user) _userChanged;
  final List<WorkspaceMemberDetail> Function() _members;

  /// [user] is the signed-in account and [members] the active workspace's
  /// roster, both read live so a change in either shows at once.
  _FeaturesStore(
    this._api, {
    required User? Function() user,
    required void Function(User user) userChanged,
    required List<WorkspaceMemberDetail> Function() members,
  }) : _user = user,
       _userChanged = userChanged,
       _members = members;

  final ObservableList<FeatureInfo> catalogue = ObservableList<FeatureInfo>();
  final ObservableList<FeaturePreset> presets = ObservableList<FeaturePreset>();

  final LoadState loadState = LoadState();

  @observable
  bool isSaving = false;

  @observable
  AppErrorMessage? error;

  /// What the account chose, or null while it never has.
  @computed
  Set<String>? get chosen => _user()?.features?.toSet();

  /// Whether the account has made a choice at all. Onboarding and an invite's
  /// starting set only apply while it has not.
  @computed
  bool get hasChosen => chosen != null;

  /// What the catalogue says a fresh account sees, falling back to the keys'
  /// own defaults until it has loaded.
  @computed
  Set<String> get defaults => catalogue.isEmpty
      ? {
          for (final f in Feature.values)
            if (f.defaultOn) f.key,
        }
      : {
          for (final f in catalogue)
            if (f.defaultOn) f.key,
        };

  /// The keys on for this account: chosen, or the defaults.
  @computed
  Set<String> get on => chosen ?? defaults;

  /// The signed-in person's own member record in the active workspace, once
  /// the roster has loaded.
  @computed
  WorkspaceMemberDetail? get self {
    for (final m in _members()) {
      if (m.isSelf) return m;
    }
    return null;
  }

  bool isOn(Feature feature) => on.contains(feature.key);

  /// Whether the workspace lets this person use the feature. True until the
  /// catalogue and the roster have both loaded: hiding on a guess would take
  /// a tab away while the answer is on its way, and the server refuses
  /// anyway.
  bool isPermitted(Feature feature) {
    final member = self;
    if (member == null) return true;
    final permission = infoFor(feature)?.permission ?? '';
    if (permission.isEmpty) return true;
    return member.permissionKeys.contains(permission);
  }

  /// Chosen and permitted: the one question every screen asks.
  bool visible(Feature feature) => isOn(feature) && isPermitted(feature);

  FeatureInfo? infoFor(Feature feature) {
    for (final f in catalogue) {
      if (f.key == feature.key) return f;
    }
    return null;
  }

  /// The reader-facing name, from the catalogue when it has loaded.
  String labelFor(Feature feature) =>
      infoFor(feature)?.label ?? feature.fallbackLabel;

  /// The catalogue in display order, as [Feature]s the app knows.
  @computed
  List<Feature> get ordered => [
    for (final info in catalogue) ?info.feature,
    if (catalogue.isEmpty) ...Feature.values,
  ];

  Future<void> loadIfDue() async {
    if (loadState.isDue) await load();
  }

  /// Fetches the catalogue and presets. Cheap and server-wide, so it is asked
  /// for wherever a feature is picked or named.
  @action
  Future<void> load() async {
    final ticket = loadState.begin();
    try {
      final data = await _api.get('/api/features') as Map<String, dynamic>;
      if (!loadState.isCurrent(ticket)) return;
      final features = (data['features'] as List<dynamic>?) ?? const [];
      final presetList = (data['presets'] as List<dynamic>?) ?? const [];
      catalogue
        ..clear()
        ..addAll(
          features.map((e) => FeatureInfo.fromJson(e as Map<String, dynamic>)),
        );
      presets
        ..clear()
        ..addAll(
          presetList.map(
            (e) => FeaturePreset.fromJson(e as Map<String, dynamic>),
          ),
        );
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      loadState.fail(ticket, describeError(e));
    }
  }

  /// Stores [keys] as the account's set. The server answers with what it
  /// kept, which replaces the account's copy here at once.
  @action
  Future<bool> save(Iterable<String> keys) async {
    isSaving = true;
    error = null;
    try {
      final data =
          await _api.put(
                '/api/account/features',
                body: {'features': keys.toList()},
              )
              as Map<String, dynamic>;
      final stored = ((data['features'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList();
      final user = _user();
      if (user != null) _userChanged(user.withFeatures(stored));
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Turns one feature on, keeping the rest as they are.
  Future<bool> turnOn(Feature feature) => save({...on, feature.key});

  /// Turns one feature off, keeping the rest as they are.
  Future<bool> turnOff(Feature feature) =>
      save(on.where((k) => k != feature.key));
}
