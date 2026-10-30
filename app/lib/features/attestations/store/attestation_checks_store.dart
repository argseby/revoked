import 'dart:async';

import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'attestation_checks_store.g.dart';

/// Asking someone to show an attestation, and what they showed.
///
/// The asker's own server stands in for a service: it makes the present link,
/// receives the answer and verifies it. While a check waits, this store asks
/// the server every few seconds whether it was answered.
// ignore: library_private_types_in_public_api
class AttestationChecksStore = _AttestationChecksStore
    with _$AttestationChecksStore;

abstract class _AttestationChecksStore with Store {
  final ApiClient _api;

  _AttestationChecksStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.attestationChecksCollection}/records';

  final ObservableList<AttestationCheck> checks =
      ObservableList<AttestationCheck>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.get(_basePath, queryParams: {'sort': '-created'});
      final items = (data['items'] as List<dynamic>?) ?? [];
      checks
        ..clear()
        ..addAll(
          items.map(
            (e) => AttestationCheck.fromJson(e as Map<String, dynamic>),
          ),
        );
    } catch (e) {
      errorMessage = AppErrorMessage.fromException(e).description;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> remove(String id) async {
    try {
      await _api.delete('$_basePath/$id');
      checks.removeWhere((c) => c.id == id);
      return true;
    } catch (e) {
      errorMessage = AppErrorMessage.fromException(e).description;
      return false;
    }
  }

  // The form.

  final ObservableTextController typeController = ObservableTextController();
  final ObservableTextController issuersController = ObservableTextController();
  final ObservableTextController claimsController = ObservableTextController();

  @observable
  bool isCreating = false;

  @observable
  AppErrorMessage? createError;

  /// The check being shown to the other person, while the sheet is open.
  @observable
  AttestationCheck? pending;

  /// The query of [pending]'s present link.
  @observable
  Map<String, String>? pendingPresent;

  Timer? _poll;

  @action
  void resetForm() {
    _stopWaiting();
    typeController.clear();
    issuersController.clear();
    claimsController.clear();
    isCreating = false;
    createError = null;
    pending = null;
    pendingPresent = null;
  }

  static List<String> _split(String raw) => raw
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  /// The link the other person opens, once a check exists.
  @computed
  String? get pendingLink {
    final query = pendingPresent;
    if (query == null) return null;
    return Uri(
      scheme: 'revoked',
      host: 'present',
      queryParameters: query,
    ).toString();
  }

  /// Creates the check, then waits for its answer.
  @action
  Future<bool> create({String? identityId}) async {
    isCreating = true;
    createError = null;
    try {
      final data = await _api.post(
        '/api/attestation-checks',
        body: {
          'type': typeController.text.trim(),
          'issuers': _split(issuersController.text.toLowerCase()),
          'claims': _split(claimsController.text),
          'identityId': ?identityId,
        },
      );
      final map = data as Map<String, dynamic>;
      final present = (map['present'] as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
      pendingPresent = present;
      pending = AttestationCheck(
        id: map['id'] as String,
        type: typeController.text.trim(),
        issuers: _split(issuersController.text.toLowerCase()),
        claims: _split(claimsController.text),
        status: 'open',
        expiresAt: map['expiresAt'] as String?,
      );
      _startWaiting();
      return true;
    } catch (e) {
      createError = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isCreating = false;
    }
  }

  void _startWaiting() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  void _stopWaiting() {
    _poll?.cancel();
    _poll = null;
  }

  /// Stops asking the server; the sheet showing the check was closed.
  @action
  void closePending() {
    _stopWaiting();
    pending = null;
    pendingPresent = null;
    load();
  }

  Future<void> _refresh() async {
    final current = pending;
    if (current == null) return _stopWaiting();
    try {
      final data = await _api.get('$_basePath/${current.id}');
      final fresh = AttestationCheck.fromJson(data as Map<String, dynamic>);
      runInAction(() {
        if (pending?.id == fresh.id) pending = fresh;
      });
      if (!fresh.isWaiting(DateTime.now())) _stopWaiting();
    } catch (_) {
      // A missed poll is retried on the next tick.
    }
  }
}
