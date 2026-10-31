import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json.dart';
import '../auth/employee.dart';
import '../parts/part_model.dart';
import 'repair_models.dart';

/// Endpoints of the NTP backend (honda-ntp-antigravity) used by the repairs
/// feature.
class RepairsApi {
  RepairsApi(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- repair

  Future<List<Repair>> findAll() => _api.getList('/repair', Repair.fromJson);

  Future<Repair> findOne(int id) => _api.getOne('/repair/$id', Repair.fromJson);

  /// `PUT /repair/:id`. The backend logs the change and, when moving to
  /// REPAIRING (5), sets `AllocatedNum = NumOfUse` on every part.
  Future<void> updateWorkStatus(int repairId, int workStatusId) =>
      _api.put('/repair/$repairId', data: {'WorkStatusID': workStatusId});

  /// [appointment] is required when [receiveType] is
  /// [ReceiveType.appointment]. Sent as local time without zone
  /// (`yyyy-MM-ddTHH:mm:00`), exactly like the web.
  Future<void> updateReceiveType(
    int repairId,
    int receiveType,
    DateTime? appointment,
  ) {
    String? date;
    if (receiveType == ReceiveType.appointment && appointment != null) {
      String two(int n) => n.toString().padLeft(2, '0');
      final d = appointment;
      date =
          '${d.year}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:00';
    }
    return _api.put(
      '/repair/$repairId',
      data: {'ReceiveType': receiveType, 'ReceiveAppointmentDate': date},
    );
  }

  /// `POST /repair/cancel/:id` returns every part to stock, sets
  /// WorkStatusID = 99 and cancels the repair's invoices (status 99).
  Future<void> cancel(int repairId, String reason) =>
      _api.post('/repair/cancel/$repairId', data: {'reason': reason});

  /// `GET /repair/logs/:id` → `{ result, data: RepairLog[] }`, newest first.
  Future<List<RepairLog>> logs(int repairId) async {
    final res = await _api.get('/repair/logs/$repairId');
    final data = res is Map ? res['data'] : res;
    return asMapList(data).map(RepairLog.fromJson).toList();
  }

  // ------------------------------------------------------ items / parts

  Future<List<RepairItem>> items(int repairId) =>
      _api.getList('/repairDetail/by-repair-id/$repairId', RepairItem.fromJson);

  /// `POST /repairDetail/with-part` creates the RepairDetail and its
  /// RepairParts in one transaction and deducts stock for every part.
  ///
  /// That route has no JWT middleware, so the log's EmployeeID falls back to
  /// `req.body.EmployeeID`; [employeeId] is sent for the timeline.
  Future<void> createItem({
    required int repairId,
    required int repairCategoryId,
    required int presetId,
    required List<NewRepairPart> parts,
    int? employeeId,
  }) {
    return _guard(
      () => _api.post(
        '/repairDetail/with-part',
        data: {
          'RepairID': repairId,
          'RepairCategoryID': repairCategoryId,
          'PresetID': presetId,
          'EmployeeID': ?employeeId,
          'repairParts': [for (final p in parts) p.toJson()],
        },
      ),
    );
  }

  /// Deletes the RepairDetail and its parts; stock is returned server-side.
  Future<void> deleteItem(int repairDetailId) => _guard(
    () => _api.delete('/repairDetail/delete-with-parts/$repairDetailId'),
  );

  /// `POST /repairPart` deducts `NumOfUse` from stock.
  Future<void> addPart(int repairDetailId, NewRepairPart part) => _guard(
    () => _api.post(
      '/repairPart',
      data: {'RepairDetailID': repairDetailId, ...part.toJson()},
    ),
  );

  /// Uses `PUT /repairPart/bulk/update` (not `PUT /repairPart/:id`) because
  /// only the bulk endpoint adjusts stock when `NumOfUse` changes.
  ///
  /// The backend stores the `updates` array verbatim as the timeline entry,
  /// so `PartID` and `part` (ignored by Sequelize on update) are included to
  /// keep it readable, the same way the web sends whole rows.
  Future<void> updatePartQuantity(RepairPartLine line, int numOfUse) => _guard(
    () => _api.put(
      '/repairPart/bulk/update',
      data: {
        'updates': [
          {
            'RepairPartID': line.id,
            'PartID': line.partId,
            'NumOfUse': numOfUse,
            'part': {
              'PartName_th': line.partName,
              'PartNumber': line.partNumber,
            },
          },
        ],
      },
    ),
  );

  /// `DELETE /repairPart/:id` returns `NumOfUse` to stock.
  Future<void> deletePart(int repairPartId) =>
      _guard(() => _api.delete('/repairPart/$repairPartId'));

  /// Current stock of a part (`GET /parts/:id` → `PartAmount`). The repair
  /// detail endpoint excludes `PartAmount`.
  Future<Part> part(int partId) => _api.getOne('/parts/$partId', Part.fromJson);

  Future<List<Preset>> presets() => _api.getList('/preset', Preset.fromJson);

  // ------------------------------------------------------------ attendees

  Future<List<Employee>> attendees(int repairId) =>
      _api.getList('/repair/get-attendees/$repairId', Employee.fromJson);

  /// Replaces the whole attendee list (logged on the timeline).
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

  /// Car photos are stored per quotation.
  Future<List<CarImage>> images(String quotationId) => _api.getList(
    '/imageCar/quotationID/${Uri.encodeComponent(quotationId)}',
    CarImage.fromJson,
  );

  /// Multer reads `QuotationID` from `req.body` inside `destination` (the
  /// folder is derived from it), so the text fields must precede the file
  /// part (Dio writes fields first).
  Future<void> uploadImage({
    required String quotationId,
    required int imageCarTypeId,
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData();
    form.fields
      ..add(MapEntry('QuotationID', quotationId))
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

  /// `GET /images/car/:quotationId/:filename` (requires `x-access-token`).
  String imageUrl(CarImage image) => _api.url(
    '/images/car/${Uri.encodeComponent(image.quotationId)}/'
    '${Uri.encodeComponent(image.fileName)}',
  );

  Map<String, String> get authHeaders => _api.authHeaders;

  // ------------------------------------------------------ invoice/receipts

  /// Returns null when the repair has no invoice yet. The backend answers
  /// `{ result: false, message: 'Error retrieving Invoice with repairId=..' }`
  /// in that case (it dereferences a null row), which [ApiClient] turns into
  /// an [ApiException] without a status code.
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

  /// `RecieptStatusID` of every receipt of the repair
  /// (`GET /receipts/by-repair-id/:id` → `{ result, data: [] }`).
  Future<List<int?>> receiptStatuses(int repairId) async {
    final res = await _api.get('/receipts/by-repair-id/$repairId');
    final data = res is Map ? res['data'] : res;
    return [
      for (final r in asMapList(data))
        asInt(r['RecieptStatusID']) ?? asInt(r['ReceiptStatusID']),
    ];
  }

  // -------------------------------------------------------------- helpers

  /// Translates the backend's English stock errors into Thai.
  Future<void> _guard(Future<dynamic> Function() call) async {
    try {
      await call();
    } on ApiException catch (e) {
      final m = e.message;
      if (m.contains('Not enough stock') || m.contains('Insufficient stock')) {
        throw ApiException(
          'สินค้าคงเหลือในคลังไม่เพียงพอ\n($m)',
          statusCode: e.statusCode,
        );
      }
      rethrow;
    }
  }
}

/// Body of a new RepairPart, same fields as the web: prices are copied from
/// the part master; Discount / isDiscount / PartStatusID use DB defaults
/// (0 / 1 / 1) and AllocatedNum starts at 0.
class NewRepairPart {
  const NewRepairPart({required this.part, required this.numOfUse});

  final Part part;
  final int numOfUse;

  Map<String, dynamic> toJson() => {
    'PartID': part.id,
    'NumOfUse': numOfUse,
    'PricePerUnit': part.pricePerUnit,
    'ServiceFee': part.serviceFee,
  };
}
