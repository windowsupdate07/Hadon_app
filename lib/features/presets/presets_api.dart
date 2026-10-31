import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json.dart';
import 'preset_models.dart';

class PresetsApi {
  PresetsApi(this._api);

  final ApiClient _api;

  /// Newest first (controller orders by PresetID DESC).
  Future<List<Preset>> findAll() => _api.getList('/preset', Preset.fromJson);

  Future<Preset> findOne(int id) => _api.getOne('/preset/$id', Preset.fromJson);

  /// Returns the new PresetID (crud.create responds `{ result, data }`).
  Future<int?> create(String name, int status) async {
    final res = await _api.post(
      '/preset',
      data: {'Preset': name, 'Status': status},
    );
    final data = res is Map ? asMap(res['data']) : null;
    return asInt(data?['PresetID']);
  }

  Future<void> update(int id, String name, int status) =>
      _api.put('/preset/$id', data: {'Preset': name, 'Status': status});

  /// `DELETE /preset/:id` soft-deletes the preset and the
  /// Ref_Model_Category_Parts rows using it. Backend quirk: the preset is
  /// destroyed outside the transaction, and when no ref rows exist the
  /// endpoint answers `result:false "Cannot delete Preset and Ref!."` even
  /// though the preset is already gone. We therefore verify by reloading.
  ///
  /// The endpoint does not touch PresetDetails, so the preset's detail rows
  /// are removed afterwards (best effort).
  Future<void> remove(Preset preset) async {
    try {
      await _api.delete('/preset/${preset.id}');
    } on ApiException catch (e) {
      if (e.isUnauthorized || !await _isGone(preset.id)) {
        rethrow;
      }
    }
    for (final d in preset.details) {
      try {
        await removeDetail(d.id);
      } catch (_) {
        // Orphan detail rows are harmless; ignore.
      }
    }
  }

  Future<bool> _isGone(int id) async {
    try {
      await findOne(id);
      return false;
    } on ApiException catch (e) {
      return e.message.startsWith('Cannot find');
    }
  }

  Future<void> addDetail(int presetId, int partId, int numOfUse) => _api.post(
    '/presetDetails',
    data: {'PresetID': presetId, 'PartID': partId, 'NumOfUse': numOfUse},
  );

  Future<void> updateDetail(int detailId, int numOfUse) =>
      _api.put('/presetDetails/$detailId', data: {'NumOfUse': numOfUse});

  Future<void> removeDetail(int detailId) =>
      _api.delete('/presetDetails/$detailId');
}
