import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json.dart';
import '../auth/employee.dart';
import '../parts/part_model.dart';
import 'repair_models.dart';

/// Endpoints of `ntp-api` used by the repairs feature.
class RepairsApi {
  RepairsApi(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- repair

  Future<List<Repair>> findAll() => _api.getList('/repair', Repair.fromJson);

  Future<Repair> findOne(int id) => _api.getOne('/repair/$id', Repair.fromJson);

  /// `crud.update(Repair)` — any Repair column may be sent.
  Future<void> updateWorkStatus(int repairId, int workStatusId) =>
      _api.put('/repair/$repairId', data: {'WorkStatusID': workStatusId});

  // ------------------------------------------------------ items / parts

  Future<List<RepairItem>> items(int repairId) =>
      _api.getList('/repairDetail/by-repair-id/$repairId', RepairItem.fromJson);

  /// `POST /repairDetail/with-part` creates the RepairDetail and its
  /// RepairParts in one transaction and deducts stock for every part.
  Future<void> createItem({
    required int repairId,
    required int repairCategoryId,
    int? presetId,
    required List<NewRepairPart> parts,
  }) {
    return _api.post(
      '/repairDetail/with-part',
      data: {
        'RepairID': repairId,
        'RepairCategoryID': repairCategoryId,
        'PresetID': presetId,
        'repairParts': [for (final p in parts) p.toJson()],
      },
    );
  }

  /// Deletes the RepairDetail and its parts; stock is returned server-side.
  Future<void> deleteItem(int repairDetailId) =>
      _api.delete('/repairDetail/delete-with-parts/$repairDetailId');

  /// `POST /repairPart` deducts `NumOfUse` from stock.
  Future<void> addPart(int repairDetailId, NewRepairPart part) => _api.post(
    '/repairPart',
    data: {'RepairDetailID': repairDetailId, ...part.toJson()},
  );

  /// Uses `PUT /repairPart/bulk/update` (not `PUT /repairPart/:id`) because
  /// only the bulk endpoint adjusts stock when `NumOfUse` changes.
  Future<void> updatePart(int repairPartId, Map<String, dynamic> fields) =>
      _api.put(
        '/repairPart/bulk/update',
        data: {
          'updates': [
            {'RepairPartID': repairPartId, ...fields},
          ],
        },
      );

  /// `DELETE /repairPart/:id` returns `NumOfUse` to stock.
  Future<void> deletePart(int repairPartId) =>
      _api.delete('/repairPart/$repairPartId');

  Future<List<Preset>> presets() => _api.getList('/preset', Preset.fromJson);

  // ------------------------------------------------------------ attendees

  Future<List<Employee>> attendees(int repairId) =>
      _api.getList('/repair/get-attendees/$repairId', Employee.fromJson);

  /// Replaces the whole attendee list.
  Future<void> setAttendees(int repairId, List<int> employeeIds) => _api.put(
    '/repair/set-attendees/$repairId',
    data: {'EmployeeIDs': employeeIds},
  );

  Future<void> removeAttendees(int repairId, List<int> employeeIds) =>
      _api.delete(
        '/repair/remove-attendees/$repairId',
        data: {'EmployeeIDs': employeeIds},
      );

  Future<List<Employee>> employees() =>
      _api.getList('/employee', Employee.fromJson);

  // --------------------------------------------------------------- images

  Future<List<CarImage>> images(int repairId) =>
      _api.getList('/imageCar/repairID/$repairId', CarImage.fromJson);

  /// Multer reads `RepairID` from `req.body` inside `destination`, so the
  /// text fields must precede the file part (Dio writes fields first).
  Future<void> uploadImage({
    required int repairId,
    required int imageCarTypeId,
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData();
    form.fields
      ..add(MapEntry('RepairID', '$repairId'))
      ..add(MapEntry('ImageCarTypeID', '$imageCarTypeId'));
    form.files.add(
      MapEntry(
        'images',
        await MultipartFile.fromFile(filePath, filename: fileName),
      ),
    );
    await _api.postMultipart('/imageCar', form);
  }

  Future<void> deleteImage(int imageCarId) =>
      _api.delete('/imageCar/$imageCarId');

  /// `GET /images/car/:repairId/:filename` (requires `x-access-token`).
  String imageUrl(CarImage image) => _api.url(
    '/images/car/${image.repairId}/${Uri.encodeComponent(image.fileName)}',
  );

  Map<String, String> get authHeaders => _api.authHeaders;

  // -------------------------------------------------------------- invoice

  /// Returns null when the repair has no invoice yet. The backend answers
  /// `{ result: false, message: 'Error retrieving Invoice ...' }` in that
  /// case (it dereferences a null row), which [ApiClient] turns into an
  /// [ApiException] without a status code.
  Future<RepairInvoice?> invoice(int repairId) async {
    try {
      final res = await _api.get('/invoices/by-repair-id/$repairId');
      final data = asMap(asMap(res)?['data']);
      if (data == null || asString(data['InvoiceID']) == null) {
        return null;
      }
      return RepairInvoice.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == null &&
          (e.message.contains('Invoice') || e.message.contains('invoice'))) {
        return null;
      }
      rethrow;
    }
  }
}

/// Body of a new RepairPart (prices are copied from the part master).
class NewRepairPart {
  const NewRepairPart({required this.part, required this.numOfUse});

  final Part part;
  final int numOfUse;

  Map<String, dynamic> toJson() => {
    'PartID': part.id,
    'NumOfUse': numOfUse,
    'PricePerUnit': part.pricePerUnit,
    'ServiceFee': part.serviceFee,
    'Discount': 0,
    'isDiscount': 1,
    'PartStatusID': 1,
  };
}
