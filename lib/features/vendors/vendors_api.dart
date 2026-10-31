import '../../core/network/api_client.dart';
import 'vendor_models.dart';

/// `Addresses.AddressTypeID` used for vendors (seed: 1 = ลูกค้า, 2 = คู่ค้า).
const vendorAddressType = 2;

/// `/vendors` and the vendor side of `/addresses`.
class VendorsApi {
  VendorsApi(this._api);

  final ApiClient _api;

  Future<List<Vendor>> findAll() => _api.getList('/vendors', Vendor.fromJson);

  Future<Vendor> findOne(int id) =>
      _api.getOne('/vendors/$id', Vendor.fromJson);

  /// `POST /vendors` (createWithAddress) creates the vendor and one address
  /// in a transaction; the controller adds OwnerID and AddressTypeID 2 to
  /// `req.body.address`. It always inserts an address row, so [address] is
  /// required (the web form requires it as well).
  Future<void> create(
    Map<String, dynamic> vendor,
    Map<String, dynamic> address,
  ) => _api.post(
    '/vendors',
    data: {
      ...vendor,
      'address': {...address, 'IsDefault': true},
    },
  );

  /// `PUT /vendors/:id` (crud.update) — vendor columns only.
  Future<void> update(int id, Map<String, dynamic> vendor) =>
      _api.put('/vendors/$id', data: vendor);

  /// `DELETE /vendors/:id` (crud.remove, soft delete).
  Future<void> remove(int id) => _api.delete('/vendors/$id');

  /// `POST /addresses`. The server first clears IsDefault on all of the
  /// vendor's addresses, so the new address always becomes the default.
  Future<void> addAddress(int vendorId, Map<String, dynamic> address) =>
      _api.post(
        '/addresses',
        data: {
          ...address,
          'OwnerID': vendorId,
          'AddressTypeID': vendorAddressType,
          'IsDefault': true,
        },
      );

  /// `PUT /addresses/:id` (crud.update).
  Future<void> updateAddress(int addressId, Map<String, dynamic> address) =>
      _api.put('/addresses/$addressId', data: address);

  /// `DELETE /addresses/:id` (crud.remove, soft delete).
  Future<void> removeAddress(int addressId) =>
      _api.delete('/addresses/$addressId');

  /// `PUT /addresses/change-default-address/:id`.
  Future<void> setDefaultAddress(int addressId) =>
      _api.put('/addresses/change-default-address/$addressId');
}
