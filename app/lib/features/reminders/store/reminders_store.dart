import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/reminder.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';

part 'reminders_store.g.dart';

// ignore: library_private_types_in_public_api
class RemindersStore = _RemindersStore with _$RemindersStore;

/// The signed-in user's reminders on vault entries. Personal, not workspace
/// data: the collection rules admit the owning user alone, and the server
/// fills in the workspace from the entry.
abstract class _RemindersStore with Store {
  final ApiClient _api;

  _RemindersStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.remindersCollection}/records';

  final ObservableList<Reminder> reminders = ObservableList<Reminder>();

  @observable
  bool isLoading = false;

  @observable
  bool isSaving = false;

  @observable
  AppErrorMessage? error;

  /// The reminders on one entry: waiting ones first, soonest first.
  List<Reminder> forRecord(String recordId) {
    final list = reminders.where((r) => r.record == recordId).toList();
    int rank(Reminder r) => r.hasFired ? 1 : 0;
    list.sort((a, b) {
      final byFired = rank(a).compareTo(rank(b));
      if (byFired != 0) return byFired;
      final ad = a.dueAt, bd = b.dueAt;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return (a.created ?? '').compareTo(b.created ?? '');
    });
    return list;
  }

  @action
  Future<void> load() async {
    isLoading = true;
    error = null;
    try {
      final data = await _api.get(
        _basePath,
        queryParams: {'perPage': '500', 'sort': '-created'},
      );
      final items = (data['items'] as List<dynamic>?) ?? const [];
      reminders
        ..clear()
        ..addAll(
          items.map((e) => Reminder.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      error = AppErrorMessage.fromException(e);
    } finally {
      isLoading = false;
    }
  }

  /// Saves a new reminder. [dueAt] is for a date reminder; [watch] for a
  /// change reminder, and defaults to [record] itself on the server.
  @action
  Future<bool> create({
    required String user,
    required String record,
    required String kind,
    DateTime? dueAt,
    String? watch,
    String note = '',
  }) async {
    isSaving = true;
    error = null;
    try {
      final data = await _api.post(
        _basePath,
        body: {
          'user': user,
          'record': record,
          'kind': kind,
          if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
          if (watch != null && watch.isNotEmpty) 'watch': watch,
          'note': note.trim(),
        },
      );
      reminders.insert(0, Reminder.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Arms a fired reminder again: it fires the next time its condition holds.
  @action
  Future<bool> rearm(String id) => _replace(id, {'firedAt': ''});

  @action
  Future<bool> delete(String id) async {
    error = null;
    try {
      await _api.delete('$_basePath/$id');
      reminders.removeWhere((r) => r.id == id);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  Future<bool> _replace(String id, Map<String, dynamic> body) async {
    error = null;
    try {
      final data = await _api.patch('$_basePath/$id', body: body);
      final updated = Reminder.fromJson(data as Map<String, dynamic>);
      runInAction(() {
        final idx = reminders.indexWhere((r) => r.id == id);
        if (idx != -1) reminders[idx] = updated;
      });
      return true;
    } catch (e) {
      runInAction(() => error = AppErrorMessage.fromException(e));
      return false;
    }
  }
}
