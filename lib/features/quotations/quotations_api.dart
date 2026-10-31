import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json.dart';
import 'quotation_models.dart';

/// Result of approving a quotation (`POST /invoices/create-with-repair`).
class ApproveResult {
  const ApproveResult({this.invoiceId, this.repairId});

  final String? invoiceId;
  final int? repairId;
}

/// Endpoints of ntp-api used by the quotation screens.
class QuotationsApi {
  QuotationsApi(this._api);

  final ApiClient _api;

  // ---- Quotation ----

  Future<List<Quotation>> findAll() =>
      _api.getList('/quotation', Quotation.fromJson);

  Future<Quotation> findOne(String id) =>
      _api.getOne('/quotation/${Uri.encodeComponent(id)}', Quotation.fromJson);

  /// `POST /quotation` {BrandID, ModelID, Comment}. The server generates
  /// `QT-YYYYMMDD-NNN`, sets QuotationDate = now and EmployeeID from the
  /// token. Returns the new QuotationID.
  Future<String> create({
    required int brandId,
    required int modelId,
    String? comment,
  }) async {
    final res = await _api.post(
      '/quotation',
      data: {
        'BrandID': brandId,
        'ModelID': modelId,
        'Comment': comment ?? '',
      },
    );
    final data = res is Map ? asMap(res['data']) : null;
    final id = asString(data?['QuotationID']);
    if (id == null) {
      throw const ApiException('ไม่พบเลขที่ใบเสนอราคาที่สร้าง');
    }
    return id;
  }

  /// `PUT /quotation/:id` (generic crud update) — used for Comment / isVat.
  Future<void> update(String id, Map<String, dynamic> body) =>
      _api.put('/quotation/${Uri.encodeComponent(id)}', data: body);

  Future<void> remove(String id) =>
      _api.delete('/quotation/${Uri.encodeComponent(id)}');

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

  Future<void> addCashPledge({
    required String quotationId,
    required String title,
    required double amount,
  }) {
    return _api.post(
      '/cash-pledge',
      data: {
        'QuotationID': quotationId,
        'PledgeTitle': title,
        'PledgeAmount': amount,
      },
    );
  }

  Future<void> deleteCashPledge(int id) => _api.delete('/cash-pledge/$id');

  // ---- Approve ----

  Future<List<CarOption>> carsByModel(int modelId) =>
      _api.getList('/cars/by-model/$modelId', CarOption.fromJson);

  Future<List<CarOption>> allCars() => _api.getList('/cars', CarOption.fromJson);

  /// `POST /invoices/create-with-repair`: creates a Repair (copying the
  /// quotation items/parts into RepairDetail/RepairPart, deducting stock) and
  /// an Invoice. Response: `{ result, createInvoice, createRepair }`.
  Future<ApproveResult> approve({
    required String quotationId,
    required int brandId,
    required int modelId,
    required int carId,
    required int customerId,
    required int employeeId,
  }) async {
    final res = await _api.post(
      '/invoices/create-with-repair',
      data: {
        'QuotationID': quotationId,
        'BrandID': brandId,
        'ModelID': modelId,
        'CarID': carId,
        'CustomerID': customerId,
        // Ignored by the server (it uses the token's employee), sent for
        // completeness.
        'EmployeeID': employeeId,
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

  /// Full invoice JSON for [repairId] (includes car + customer), or null.
  Future<Map<String, dynamic>?> invoiceByRepair(int repairId) async {
    try {
      final res = await _api.get('/invoices/by-repair-id/$repairId');
      return res is Map ? asMap(res['data']) : null;
    } on ApiException {
      return null;
    }
  }
}
