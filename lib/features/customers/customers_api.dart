import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import 'customer_models.dart';

/// `/customers` and `/addresses` endpoints of ntp-api.
class CustomersApi {
  CustomersApi(this._api);

  final ApiClient _api;

  /// Includes `customerTitle`, customer `addresses` and `cars`.
  Future<List<Customer>> findAll() async {
    final list = await _api.getList('/customers', Customer.fromJson);
    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  Future<Customer> findOne(int id) =>
      _api.getOne('/customers/$id', Customer.fromJson);

  /// `POST /customers` (createWithAddress): the customer columns plus an
  /// `address` object, created in one transaction with AddressTypeID 1.
  /// Returns the new CustomerID.
  Future<int?> create(
    Map<String, dynamic> customer,
    Map<String, dynamic> address,
  ) async {
    final res = await _api.post(
      '/customers',
      data: {
        ...customer,
        'address': {
          ...address,
          'AddressTypeID': customerAddressTypeId,
          'IsDefault': true,
        },
      },
    );
    return res is Map ? asInt(asMap(res['createCustomer'])?['CustomerID']) : null;
  }

  Future<void> update(int id, Map<String, dynamic> body) =>
      _api.put('/customers/$id', data: body);

  /// Soft delete (the table is paranoid); the customer's cars are kept.
  Future<void> remove(int id) => _api.delete('/customers/$id');

  /// `POST /addresses`. The server first clears IsDefault on all of the
  /// owner's addresses, so the new address always becomes the default.
  Future<void> addAddress(int customerId, Map<String, dynamic> address) =>
      _api.post(
        '/addresses',
        data: {
          ...address,
          'OwnerID': customerId,
          'AddressTypeID': customerAddressTypeId,
          'IsDefault': true,
        },
      );

  Future<void> updateAddress(int addressId, Map<String, dynamic> address) =>
      _api.put('/addresses/$addressId', data: address);

  Future<void> removeAddress(int addressId) =>
      _api.delete('/addresses/$addressId');

  Future<void> setDefaultAddress(int addressId) =>
      _api.put('/addresses/change-default-address/$addressId');
}
