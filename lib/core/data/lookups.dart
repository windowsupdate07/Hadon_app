import '../network/api_client.dart';
import '../utils/json.dart';

/// Generic id/label pair for dropdowns.
class Option {
  const Option(this.id, this.label, [this.raw = const {}]);

  final int id;
  final String label;
  final Map<String, dynamic> raw;

  @override
  bool operator ==(Object other) => other is Option && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => label;
}

/// Cached reference data (provinces, brands, titles ...). Cascading lists
/// (districts, sub-districts, car models) are cached per parent id.
class Lookups {
  Lookups(this._api);

  final ApiClient _api;
  final Map<String, Future<List<Option>>> _cache = {};

  Future<List<Option>> _load(
    String path,
    String idKey,
    String Function(Map<String, dynamic>) label,
  ) {
    return _cache.putIfAbsent(path, () async {
      try {
        final list = await _api.getList(
          path,
          (j) => Option(asInt(j[idKey]) ?? 0, label(j), j),
        );
        list.sort((a, b) => a.label.compareTo(b.label));
        return list;
      } catch (_) {
        // Do not keep failed requests cached.
        _cache.remove(path);
        rethrow;
      }
    });
  }

  Future<List<Option>> provinces() =>
      _load('/province', 'ProvinceID', (j) => '${j['name_th'] ?? ''}');

  Future<List<Option>> districts(int provinceId) => _load(
        '/district/province/$provinceId',
        'DistrictID',
        (j) => '${j['name_th'] ?? ''}',
      );

  /// `raw['Zipcode']` holds the postal code.
  Future<List<Option>> subDistricts(int districtId) => _load(
        '/subDistrict/district/$districtId',
        'SubDistrictID',
        (j) => '${j['name_th'] ?? ''}',
      );

  Future<List<Option>> brands() =>
      _load('/brands', 'BrandID', (j) => '${j['Brand'] ?? ''}');

  Future<List<Option>> carModels(int brandId) =>
      _load('/carModel/brand/$brandId', 'ModelID', (j) => '${j['Model'] ?? ''}');

  Future<List<Option>> customerTitles() => _load(
        '/customerTitle',
        'CustomerTitleID',
        (j) => '${j['CustomerTitle'] ?? ''}',
      );

  Future<List<Option>> addressTypes() =>
      _load('/addressType', 'AddressTypeID', (j) => '${j['AddressType'] ?? ''}');

  Future<List<Option>> units() =>
      _load('/unit', 'UnitID', (j) => '${j['Unit'] ?? ''}');

  Future<List<Option>> repairCategories() => _load(
        '/repairCategory',
        'RepairCategoryID',
        (j) => '${j['RepairCategory'] ?? ''}',
      );

  Future<List<Option>> partCategories() => _load(
        '/partCategory',
        'PartCategoryID',
        (j) => '${j['PartCategoryName'] ?? ''}',
      );

  Future<List<Option>> positions() =>
      _load('/position', 'PositionID', (j) => '${j['PositionTitle'] ?? ''}');

  Future<List<Option>> roles() =>
      _load('/role', 'RoleID', (j) => '${j['RoleName'] ?? ''}');

  Future<List<Option>> employeeStatuses() => _load(
        '/employeeStatus',
        'EmployeeStatusID',
        (j) => '${j['EmployeeStatusTitle'] ?? ''}',
      );

  Future<List<Option>> vendorTypes() =>
      _load('/vendorType', 'VendorTypeID', (j) => '${j['VendorType'] ?? ''}');

  Future<List<Option>> imageCarTypes() => _load(
        '/imageCarType',
        'ImageCarTypeID',
        (j) => '${j['ImageCarType'] ?? ''}',
      );

  Future<List<Option>> discountTypes() => _load(
        '/discounttype',
        'DiscountTypeID',
        (j) => '${j['DiscountType'] ?? ''}',
      );

  void clear() => _cache.clear();
}
