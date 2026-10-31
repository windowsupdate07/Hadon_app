import '../../core/network/api_client.dart';
import 'vendor_models.dart';

/// `Addresses.AddressTypeID` used for vendors (seed: 1 = ลูกค้า, 2 = คู่ค้า).
const vendorAddressType = 2;

class VendorsApi {
  VendorsApi(this._api);

  final ApiClient _api;

  Future<List<Vendor>> findAll() => _api.getList('/vendors', Vendor.fromJson);

  /// `POST /vendors` creates the vendor and its address in one transaction:
  /// the controller reads `req.body.address` and adds OwnerID/AddressTypeID.
  Future<void> create(
    Map<String, dynamic> vendor,
    Map<String, dynamic>? address,
  ) => _api.post('/vendors', data: {...vendor, 'address': ?address});

  /// `PUT /vendors/:id` is a plain update of the Vendors row; the address
  /// lives in `Addresses` and is saved through `/addresses`.
  Future<void> update(
    int id,
    Map<String, dynamic> vendor, {
    int? addressId,
    Map<String, dynamic>? address,
  }) async {
    await _api.put('/vendors/$id', data: vendor);
    if (address == null) {
      return;
    }
    if (addressId != null) {
      await _api.put('/addresses/$addressId', data: address);
    } else {
      await _api.post(
        '/addresses',
        data: {
          ...address,
          'OwnerID': id,
          'AddressTypeID': vendorAddressType,
          'IsDefault': true,
        },
      );
    }
  }

  Future<void> remove(int id) => _api.delete('/vendors/$id');
}
