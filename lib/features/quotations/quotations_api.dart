import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../invoices/invoice_models.dart';
import '../invoices/invoices_api.dart';
import 'quotation_models.dart';

/// Result of sending a quotation to repair (`POST /invoices/create-with-repair`).
class ApproveResult {
  const ApproveResult({this.invoiceId, this.repairId});

  final String? invoiceId;
  final int? repairId;
}

/// Header + vehicle fields of `POST /quotation` (web DialogCreateQuotation).
class NewQuotation {
  const NewQuotation({
    required this.car,
    required this.mileage,
    this.taxDate,
    this.gasInstallation = 0,
    this.tireType = 0,
    this.comment,
  });

  final CarOption car;
  final int mileage;

  /// null = ไม่ระบุป้ายภาษี.
  final DateTime? taxDate;
  final int gasInstallation;
  final int tireType;
  final String? comment;
}

/// Vehicle fields editable on an open quotation (web EditVehicleDetailsDialog).
class VehicleDetails {
  const VehicleDetails({
    required this.mileage,
    this.taxDate,
    this.gasInstallation = 0,
    this.tireType = 0,
  });

  final int mileage;
  final DateTime? taxDate;
  final int gasInstallation;
  final int tireType;

  Map<String, dynamic> toJson() => {
    'Mileage': mileage,
    'GasInstalation': gasInstallation,
    'TireType': tireType,
    'TaxDate': taxDate == null ? null : formatApiDate(taxDate!),
  };
}

/// Endpoints used by the quotation screens
/// (honda-ntp-antigravity/backend/routes/quotation*.routes.js & co).
class QuotationsApi {
  QuotationsApi(this._api);

  final ApiClient _api;

  late final InvoicesApi invoices = InvoicesApi(_api);

  // ---- Quotation ----

  Future<List<Quotation>> findAll() =>
      _api.getList('/quotation', Quotation.fromJson);

  Future<Quotation> findOne(String id) =>
      _api.getOne('/quotation/${Uri.encodeComponent(id)}', Quotation.fromJson);

  /// `POST /quotation`. The server generates `QT-YYYYMMDD-NNN`, sets
  /// QuotationDate = now, EmployeeID from the token and AddressID to the
  /// customer's default billing address. Like the web, new quotations start
  /// with VAT on (VatType defaults to 0 = include). Returns the new ID.
  Future<String> create(NewQuotation q) async {
    final car = q.car;
    final res = await _api.post(
      '/quotation',
      data: {
        'CarID': car.id,
        'BrandID': car.brandId,
        'ModelID': car.modelId,
        'CustomerID': car.customerId,
        'Mileage': q.mileage,
        'GasInstalation': q.gasInstallation,
        'TireType': q.tireType,
        'TaxDate': q.taxDate == null ? null : formatApiDate(q.taxDate!),
        'Comment': q.comment ?? '',
        'isVat': 1,
      },
    );
    final data = res is Map ? asMap(res['data']) : null;
    final id = asString(data?['QuotationID']);
    if (id == null) {
      throw const ApiException('ไม่พบเลขที่ใบเสนอราคาที่สร้าง');
    }
    return id;
  }

  /// `PUT /quotation/:id` (generic crud update).
  Future<void> update(String id, Map<String, dynamic> body) =>
      _api.put('/quotation/${Uri.encodeComponent(id)}', data: body);

  Future<void> updateVehicle(String id, VehicleDetails v) =>
      update(id, v.toJson());

  /// Web `switchVat`: `{isVat, VatType}`.
  Future<void> setVat(String id, {required bool isVat, required int vatType}) =>
      update(id, {'isVat': isVat ? 1 : 0, 'VatType': vatType});

  Future<void> remove(String id) =>
      _api.delete('/quotation/${Uri.encodeComponent(id)}');

  /// `GET /quotation/logs/:id` -> `{ result, data: RepairLog[] }` (newest
  /// first; includes logs of repairs opened from the quotation).
  Future<List<QuotationLog>> logs(String id) async {
    final res = await _api.get('/quotation/logs/${Uri.encodeComponent(id)}');
    final list = res is Map ? asMapList(res['data']) : asMapList(res);
    return list.map(QuotationLog.fromJson).toList();
  }

  /// `POST /quotation/copy` {sourceQuotationId, targetQuotationId?,
  /// selectedDetailIds}. Without a target the server creates a new
  /// quotation with the same header, car, customer and photos. Returns
  /// `newQuotationId`.
  Future<String> copy({
    required String sourceQuotationId,
    String? targetQuotationId,
    required List<int> detailIds,
  }) async {
    final res = await _api.post(
      '/quotation/copy',
      data: {
        'sourceQuotationId': sourceQuotationId,
        'targetQuotationId': ?targetQuotationId,
        'selectedDetailIds': detailIds,
      },
    );
    final id = res is Map ? asString(res['newQuotationId']) : null;
    if (id == null) {
      throw const ApiException('ไม่พบเลขที่ใบเสนอราคาที่คัดลอก');
    }
    return id;
  }

  // ---- Items ----

  Future<List<QuotationDetail>> details(String quotationId) => _api.getList(
    '/quotation-detail/by-quotation-id/${Uri.encodeComponent(quotationId)}',
    QuotationDetail.fromJson,
  );

  /// `POST /quotation-detail/create-with-parts`. The server requires
  /// QuotationID, RepairCategoryID and PresetID; `quotationParts` items are
  /// bulk-created with the new QuotationDetailID. No stock is consumed.
  Future<void> createDetailWithParts({
    required String quotationId,
    required int repairCategoryId,
    required int presetId,
    required List<DraftPart> parts,
  }) {
    return _api.post(
      '/quotation-detail/create-with-parts',
      data: {
        'QuotationID': quotationId,
        'RepairCategoryID': repairCategoryId,
        'PresetID': presetId,
        'quotationParts': parts.map((p) => p.toJson()).toList(),
      },
    );
  }

  /// `DELETE /quotation-detail/delete-with-parts/:id`.
  Future<void> deleteDetail(int detailId) =>
      _api.delete('/quotation-detail/delete-with-parts/$detailId');

  /// `PUT /quotation-part/:id` {NumOfUse, PricePerUnit, ServiceFee}.
  Future<void> updatePart(int partLineId, Map<String, dynamic> body) =>
      _api.put('/quotation-part/$partLineId', data: body);

  Future<void> deletePart(int partLineId) =>
      _api.delete('/quotation-part/$partLineId');

  // ---- Presets ----

  /// All model/category/preset links (with preset parts). Filtered client
  /// side because there is no endpoint returning ungrouped refs per model.
  Future<List<PresetRef>> presetRefs() =>
      _api.getList('/refModelCategoryParts', PresetRef.fromJson);

  /// All presets with their parts (`GET /preset`).
  Future<List<PresetOption>> presets() =>
      _api.getList('/preset', PresetOption.fromJson);

  // ---- Cash pledge ----

  Future<List<CashPledge>> cashPledges(String quotationId) => _api.getList(
    '/cash-pledge/by-quotation-id/${Uri.encodeComponent(quotationId)}',
    CashPledge.fromJson,
  );

  /// `POST /cash-pledge` {QuotationID, PledgeTitle, PledgeAmount}. The
  /// server also creates a deposit invoice (IsDeposit 1, status 2 รอชำระเงิน,
  /// Amount = PledgeAmount, VAT copied from the quotation) and returns its
  /// `invoiceID`.
  Future<String?> addCashPledge({
    required String quotationId,
    required double amount,
    String title = 'เงินมัดจำ',
  }) async {
    final res = await _api.post(
      '/cash-pledge',
      data: {
        'QuotationID': quotationId,
        'PledgeTitle': title,
        'PledgeAmount': amount,
      },
    );
    return res is Map ? asString(res['invoiceID']) : null;
  }

  /// `DELETE /cash-pledge/:id` — only used for legacy pledges that have no
  /// deposit invoice; otherwise the pledge is removed by cancelling its
  /// deposit invoice (the server deletes the pledges then).
  Future<void> deleteCashPledge(int id) => _api.delete('/cash-pledge/$id');

  // ---- Linked documents ----

  Future<List<Invoice>> invoicesOf(String quotationId) =>
      invoices.byQuotation(quotationId);

  /// `GET /receipts/by-quotation-id/:id` -> `{ result, data: Receipt[] }`.
  Future<List<QuotationReceipt>> receiptsOf(String quotationId) async {
    final res = await _api.get(
      '/receipts/by-quotation-id/${Uri.encodeComponent(quotationId)}',
    );
    final list = res is Map ? asMapList(res['data']) : asMapList(res);
    return list.map(QuotationReceipt.fromJson).toList();
  }

  // ---- Car photos ----

  Future<List<QuotationImage>> images(String quotationId) => _api.getList(
    '/imageCar/quotationID/${Uri.encodeComponent(quotationId)}',
    QuotationImage.fromJson,
  );

  /// `POST /imageCar` multipart: `QuotationID` (must precede the files —
  /// multer picks the folder from it), `images` (files) and one
  /// `ImageCarTypeID` per file.
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

  /// `GET /images/car/:quotationId/:filename` (requires `x-access-token`,
  /// see [authHeaders]).
  String imageUrl(QuotationImage image) => _api.url(
    '/images/car/${Uri.encodeComponent(image.quotationId)}/'
    '${Uri.encodeComponent(image.fileName)}',
  );

  Map<String, String> get authHeaders => _api.authHeaders;

  // ---- Send to repair ----

  Future<List<CarOption>> carsByModel(int modelId) =>
      _api.getList('/cars/by-model/$modelId', CarOption.fromJson);

  Future<List<CarOption>> allCars() =>
      _api.getList('/cars', CarOption.fromJson);

  /// `POST /invoices/create-with-repair` {QuotationID, BrandID, ModelID,
  /// CarID, CustomerID, ReceiveType, ReceiveAppointmentDate}: creates a
  /// Repair (copying the quotation items into RepairDetail/RepairPart and
  /// deducting stock) and a draft repair Invoice with the quotation's VAT
  /// settings. Response: `{ result, createInvoice, createRepair }`.
  ///
  /// [receiveType] 1 = ลูกค้ารอรับ, 2 = ลูกค้านัดรับ ([appointment] required).
  Future<ApproveResult> approve({
    required String quotationId,
    required int brandId,
    required int modelId,
    required int carId,
    required int customerId,
    int receiveType = 1,
    DateTime? appointment,
  }) async {
    final res = await _api.post(
      '/invoices/create-with-repair',
      data: {
        'QuotationID': quotationId,
        'BrandID': brandId,
        'ModelID': modelId,
        'CarID': carId,
        'CustomerID': customerId,
        'ReceiveType': receiveType,
        // Web sends the local "yyyy-MM-ddTHH:mm" from its date/time pickers.
        'ReceiveAppointmentDate': receiveType == 2 && appointment != null
            ? '${formatApiDate(appointment)}T'
                  '${appointment.hour.toString().padLeft(2, '0')}:'
                  '${appointment.minute.toString().padLeft(2, '0')}'
            : null,
      },
    );
    final map = res is Map ? res : const {};
    final invoice = asMap(map['createInvoice']);
    final repair = asMap(map['createRepair']);
    return ApproveResult(
      invoiceId: asString(invoice?['InvoiceID']),
      repairId: asInt(repair?['RepairID'] ?? invoice?['RepairID']),
    );
  }
}
