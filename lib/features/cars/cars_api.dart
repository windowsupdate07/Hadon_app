import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import 'car_models.dart';

/// `/cars` endpoints (plus `/repair/by-car`) of the NTP backend.
class CarsApi {
  CarsApi(this._api);

  final ApiClient _api;

  /// Newest first (ordered by the server).
  Future<List<Car>> findAll() => _api.getList('/cars', Car.fromJson);

  Future<Car> findOne(int id) => _api.getOne('/cars/$id', Car.fromJson);

  /// `GET /cars/by-customer/:id`: same includes as [findAll] (owner, brand,
  /// model, province, repair ids). Sorted newest first here; the server does
  /// not order.
  Future<List<Car>> findByCustomer(int customerId) async {
    final list =
        await _api.getList('/cars/by-customer/$customerId', Car.fromJson);
    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  /// `POST /cars` (crud.create). Returns the new CarID.
  Future<int?> create(Map<String, dynamic> body) async {
    final res = await _api.post('/cars', data: body);
    return res is Map ? asInt(asMap(res['data'])?['CarID']) : null;
  }

  /// `PUT /cars/:id` (crud.update, partial bodies are fine).
  Future<void> update(int id, Map<String, dynamic> body) =>
      _api.put('/cars/$id', data: body);

  /// Soft delete (the table is paranoid).
  Future<void> remove(int id) => _api.delete('/cars/$id');

  /// `POST /cars/with-customer`: `{ customer: {..., address?}, car: {...} }`
  /// created in one transaction. When [address] is given the server also
  /// creates it (AddressTypeID 1, IsDefault defaults to true).
  /// Returns the new CustomerID.
  Future<int?> createWithCustomer(
    Map<String, dynamic> customer,
    Map<String, dynamic> car, {
    Map<String, dynamic>? address,
  }) async {
    final res = await _api.post(
      '/cars/with-customer',
      data: {
        'customer': {
          ...customer,
          if (address != null) 'address': {...address, 'IsDefault': true},
        },
        'car': car,
      },
    );
    return res is Map ? asInt(asMap(res['data'])?['CustomerID']) : null;
  }

  /// `POST /cars/check-existence`. The server matches the customer by
  /// name + surname or IDNumber, and the car by CarNumber + ProvinceID plus
  /// any of CarTitle / BrandID / ModelID that are sent.
  Future<CarExistence> checkExistence({
    Map<String, dynamic>? customer,
    Map<String, dynamic>? car,
  }) async {
    final res = await _api.post(
      '/cars/check-existence',
      data: {'customer': ?customer, 'car': ?car},
    );
    return res is Map
        ? CarExistence.fromJson(Map<String, dynamic>.from(res))
        : const CarExistence();
  }

  /// `GET /repair/by-car/:id`, newest first, cancelled jobs hidden (as on
  /// the web).
  Future<List<CarRepairRecord>> repairHistory(int carId) async {
    final list =
        await _api.getList('/repair/by-car/$carId', CarRepairRecord.fromJson);
    return list.where((r) => r.workStatusId != WorkStatus.cancel).toList();
  }
}
