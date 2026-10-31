import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import 'car_models.dart';

/// `/cars` endpoints of ntp-api.
class CarsApi {
  CarsApi(this._api);

  final ApiClient _api;

  /// Newest first (ordered by the server).
  Future<List<Car>> findAll() => _api.getList('/cars', Car.fromJson);

  Future<Car> findOne(int id) => _api.getOne('/cars/$id', Car.fromJson);

  Future<void> create(Map<String, dynamic> body) =>
      _api.post('/cars', data: body);

  Future<void> update(int id, Map<String, dynamic> body) =>
      _api.put('/cars/$id', data: body);

  Future<void> remove(int id) => _api.delete('/cars/$id');

  /// `POST /cars/with-customer`: `{ customer: {...}, car: {...} }` created in
  /// one transaction (no address). Returns the new CustomerID.
  Future<int?> createWithCustomer(
    Map<String, dynamic> customer,
    Map<String, dynamic> car,
  ) async {
    final res = await _api.post(
      '/cars/with-customer',
      data: {'customer': customer, 'car': car},
    );
    return res is Map ? asInt(asMap(res['data'])?['CustomerID']) : null;
  }
}
