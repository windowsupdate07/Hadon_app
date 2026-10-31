import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../quotations/totals.dart';
import 'invoice_models.dart';

/// Invoice endpoints (honda-ntp-antigravity/backend/routes/invoices.routes.js).
class InvoicesApi {
  InvoicesApi(this._api);

  final ApiClient _api;

  Future<List<Invoice>> findAll() =>
      _api.getList('/invoices', Invoice.fromJson);

  Future<Invoice> findOne(String id) =>
      _api.getOne('/invoices/${Uri.encodeComponent(id)}', Invoice.fromJson);

  /// `GET /invoices/by-quotation-id/:id` -> `{ result, data: Invoice[] }`
  /// (deposit invoices first). Includes cancelled ones.
  Future<List<Invoice>> byQuotation(String quotationId) async {
    final res = await _api.get(
      '/invoices/by-quotation-id/${Uri.encodeComponent(quotationId)}',
    );
    final list = res is Map ? asMapList(res['data']) : asMapList(res);
    return list.map(Invoice.fromJson).toList();
  }

  /// `GET /cash-pledge/by-quotation-id/:id` -> `CashPledge[]` amounts.
  Future<List<double>> cashPledges(String quotationId) async {
    final res = await _api.get(
      '/cash-pledge/by-quotation-id/${Uri.encodeComponent(quotationId)}',
    );
    return asMapList(res).map((p) => asDouble(p['PledgeAmount'])).toList();
  }

  /// `PUT /invoices/:id` {isVat, VatType} — web `switchVat`.
  Future<void> setVat(String id, {required bool isVat, required int vatType}) =>
      _api.put(
        '/invoices/${Uri.encodeComponent(id)}',
        data: {'isVat': isVat ? 1 : 0, 'VatType': vatType},
      );

  /// `PUT /invoices/:id` {InvoiceStatusID, Amount} — web
  /// `changeInvoiceStatus`: confirm (2), paid (3) and cancel (99) store the
  /// net total, back to draft (1) resets Amount to 0. The server logs the
  /// change; cancelling a deposit invoice also deletes the quotation's
  /// cash pledges.
  Future<void> changeStatus(String id, int statusId, {double? netTotal}) {
    final body = <String, dynamic>{'InvoiceStatusID': statusId};
    if (statusId == InvoiceStatus.pendingConfirm) {
      body['Amount'] = 0;
    } else if (netTotal != null) {
      body['Amount'] = roundMoney(netTotal);
    }
    return _api.put('/invoices/${Uri.encodeComponent(id)}', data: body);
  }

  /// `POST /receipts` {InvoiceID, RepairID, Amount} — the web creates the
  /// (PAID) receipt right after setting an invoice to paid. RepairID is
  /// null for deposit invoices.
  Future<String?> createReceipt({
    required String invoiceId,
    int? repairId,
    required double amount,
  }) async {
    final res = await _api.post(
      '/receipts',
      data: {
        'InvoiceID': invoiceId,
        'RepairID': repairId,
        'Amount': roundMoney(amount),
      },
    );
    return res is Map ? asString(asMap(res['data'])?['BillingID']) : null;
  }
}
