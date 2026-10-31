import '../../core/utils/json.dart';
import '../cars/car_models.dart';

/// `AddressTypeID` in ntp-api is the owner type, not home/work:
/// 1 = customer, 2 = vendor. Customer addresses must always use 1, otherwise
/// they disappear from `GET /customers` (which filters on AddressTypeID 1).
const customerAddressTypeId = 1;

/// Province id of Bangkok, which uses "แขวง/เขต" instead of "ต./อ.".
const _bangkokProvinceId = 10;

/// Title id meaning "not specified"; never shown in front of a name.
const _noTitleId = 99;

/// Row of the `Addresses` table with its province / district / sub-district.
class Address {
  const Address({
    required this.id,
    this.ownerId,
    this.line1,
    this.line2,
    this.provinceId,
    this.provinceName,
    this.districtId,
    this.districtName,
    this.subDistrictId,
    this.subDistrictName,
    this.zipcode,
    this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> j) {
    final province = asMap(j['province']);
    final district = asMap(j['district']);
    final subDistrict = asMap(j['subDistrict']);
    return Address(
      id: asInt(j['AddressID']) ?? 0,
      ownerId: asInt(j['OwnerID']),
      line1: asString(j['Line1']),
      line2: asString(j['Line2']),
      provinceId: asInt(j['ProvinceID']),
      provinceName: asString(province?['name_th']),
      districtId: asInt(j['DistrictID']),
      districtName: asString(district?['name_th']),
      subDistrictId: asInt(j['SubDistrictID']),
      subDistrictName: asString(subDistrict?['name_th']),
      zipcode: asString(subDistrict?['Zipcode']),
      isDefault: asBool(j['IsDefault']),
    );
  }

  final int id;
  final int? ownerId;
  final String? line1;
  final String? line2;
  final int? provinceId;
  final String? provinceName;
  final int? districtId;
  final String? districtName;
  final int? subDistrictId;
  final String? subDistrictName;
  final String? zipcode;
  final bool isDefault;

  /// Single-line Thai address, e.g. "12/3 ถ.สุขุมวิท ต.บางเมือง อ.เมือง จ.สมุทรปราการ 10270".
  String get fullText {
    final bkk = provinceId == _bangkokProvinceId;
    final parts = <String>[
      ?line1,
      ?line2,
      if (subDistrictName != null) '${bkk ? 'แขวง' : 'ต.'}$subDistrictName',
      if (districtName != null) '${bkk ? 'เขต' : 'อ.'}$districtName',
      if (provinceName != null) bkk ? provinceName! : 'จ.$provinceName',
      ?zipcode,
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }
}

/// Row of the `Customers` table. [addresses] and [cars] are only filled by
/// `GET /customers` and `GET /customers/:id`.
class Customer {
  const Customer({
    required this.id,
    this.titleId,
    this.title,
    this.name,
    this.surname,
    this.idNumber,
    this.tel,
    this.addresses = const [],
    this.cars = const [],
  });

  factory Customer.fromJson(Map<String, dynamic> j) {
    final title = asMap(j['customerTitle']);
    final addresses = asMapList(j['addresses']).map(Address.fromJson).toList()
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) {
          return a.isDefault ? -1 : 1;
        }
        return a.id.compareTo(b.id);
      });
    return Customer(
      id: asInt(j['CustomerID']) ?? 0,
      titleId: asInt(j['CustomerTitleID']),
      title: asString(title?['CustomerTitle']),
      name: asString(j['CustomerName']),
      surname: asString(j['CustomerSurname']),
      idNumber: asString(j['IDNumber']),
      tel: asString(j['CustomerTel']),
      addresses: addresses,
      cars: asMapList(j['cars']).map(Car.fromJson).toList(),
    );
  }

  final int id;
  final int? titleId;
  final String? title;
  final String? name;
  final String? surname;
  final String? idNumber;
  final String? tel;
  final List<Address> addresses;
  final List<Car> cars;

  /// "นายสมชาย ใจดี" (Thai titles are written without a space).
  String get fullName {
    final prefix = (titleId == _noTitleId) ? '' : (title ?? '');
    final n = '$prefix${name ?? ''} ${surname ?? ''}'.trim();
    return n.isEmpty ? 'ลูกค้า #$id' : n;
  }

  Address? get defaultAddress {
    for (final a in addresses) {
      if (a.isDefault) {
        return a;
      }
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  /// Body for `POST /customers` and `PUT /customers/:id`.
  Map<String, dynamic> toJson() => {
        'CustomerTitleID': titleId,
        'CustomerName': name,
        'CustomerSurname': surname,
        'IDNumber': idNumber,
        'CustomerTel': tel,
      };

  /// Search by name, surname, phone, ID number and the plates of the
  /// customer's cars (with plate province).
  bool matches(String q) {
    final s = q.toLowerCase().replaceAll(' ', '');
    bool has(String? v) =>
        (v ?? '').toLowerCase().replaceAll(' ', '').contains(s);
    return has(fullName) ||
        has(name) ||
        has(surname) ||
        has(tel?.replaceAll('-', '')) ||
        has(idNumber) ||
        cars.any((c) => has(c.plate) || has(c.provinceName));
  }
}
