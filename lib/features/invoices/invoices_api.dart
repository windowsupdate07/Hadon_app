import '../../core/network/api_client.dart';
import 'invoice_models.dart';

/// Invoice endpoints of ntp-api.
class InvoicesApi {
  InvoicesApi(this._api);

  final ApiClient _api;

  Future<List<Invoice>> findAll() => _api.getList('/invoices', Invoice.fromJson);

  Future<Invoice> findOne(String id) =>
      _api.getOne('/invoices/${Uri.encodeComponent(id)}', Invoice.fromJson);

  /// `PUT /invoices/:id` (generic crud update). The Invoices model only has
  /// `isVat` and `InvoiceStatusID` as editable fields (no Amount column).
  Future<void> update(String id, Map<String, dynamic> body) =>
      _api.put('/invoices/${Uri.encodeComponent(id)}', data: body);

  Future<void> setVat(String id, bool on) => update(id, {'isVat': on ? 1 : 0});

  Future<void> setStatus(String id, int statusId) =>
      update(id, {'InvoiceStatusID': statusId});
}
