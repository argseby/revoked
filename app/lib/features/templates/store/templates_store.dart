import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'templates_store.g.dart';

/// Request templates for the active workspace.
// ignore: library_private_types_in_public_api
class TemplatesStore = _TemplatesStore with _$TemplatesStore;

abstract class _TemplatesStore with Store {
  final ApiClient _api;

  _TemplatesStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.templatesCollection}/records';

  final ObservableList<Template> templates = ObservableList<Template>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  /// The exact API request [createTemplate] issues — shared with the preview.
  ApiRequestSpec createTemplateSpec({
    required String name,
    required Map<String, dynamic> schema,
    required String workspaceId,
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: _basePath,
      body: {'name': name, 'schema': schema, 'workspace': workspaceId},
    );
  }

  /// The exact API request [updateTemplate] issues — shared with the preview.
  ApiRequestSpec updateTemplateSpec(
    String id, {
    required String name,
    required Map<String, dynamic> schema,
  }) {
    return ApiRequestSpec(
      method: 'PATCH',
      path: '$_basePath/$id',
      body: {'name': name, 'schema': schema},
    );
  }

  /// The exact API request [deleteTemplate] issues — shared with the preview.
  ApiRequestSpec deleteTemplateSpec(String id) {
    return ApiRequestSpec(method: 'DELETE', path: '$_basePath/$id');
  }

  @action
  Future<void> loadTemplates(String workspaceId) async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.get(
        _basePath,
        queryParams: {
          'page': '1',
          'perPage': '50',
          'filter': 'workspace = "$workspaceId"',
          'sort': '-created',
        },
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      templates
        ..clear()
        ..addAll(
          items.map((e) => Template.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> createTemplate({
    required String name,
    required Map<String, dynamic> schema,
    required String workspaceId,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final spec = createTemplateSpec(
        name: name,
        schema: schema,
        workspaceId: workspaceId,
      );
      final data = await _api.post(spec.path, body: spec.body);
      templates.insert(0, Template.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> updateTemplate(
    String id, {
    required String name,
    required Map<String, dynamic> schema,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final spec = updateTemplateSpec(id, name: name, schema: schema);
      final data = await _api.patch(spec.path, body: spec.body);
      final updated = Template.fromJson(data as Map<String, dynamic>);
      final idx = templates.indexWhere((t) => t.id == id);
      if (idx != -1) templates[idx] = updated;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> deleteTemplate(String id) async {
    isLoading = true;
    errorMessage = null;
    try {
      await _api.delete(deleteTemplateSpec(id).path);
      templates.removeWhere((t) => t.id == id);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  void clearError() => errorMessage = null;
}
