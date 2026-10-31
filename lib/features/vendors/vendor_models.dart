import 'package:flutter/material.dart';

import '../../core/utils/json.dart';

/// `Vendors.RatingColor` values used by the web (Vuetify colour names).
enum VendorRating {
  green('green', 'สีเขียว', Colors.green),
  warning('warning', 'สีเหลือง', Colors.amber),
  error('error', 'สีแดง', Colors.red);

  const VendorRating(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  /// Unknown / null values fall back to green (the column default).
  static VendorRating parse(String? v) {
    for (final r in values) {
      if (r.value == v) {
        return r;
      }
    }
    return green;
  }
}

/// Vendor address (`Addresses` row with AddressTypeID = 2, OwnerID = VendorID).
class VendorAddress {
  const VendorAddress({
    required this.id,
    this.line1,
    this.line2,
    this.provinceId,
    this.districtId,
    this.subDistrictId,
    this.provinceName,
    this.districtName,
    this.subDistrictName,
    this.zipcode,
    this.isDefault = false,
  });

  factory VendorAddress.fromJson(Map<String, dynamic> j) {
    final province = asMap(j['province'] ?? j['Province']);
    final district = asMap(j['district'] ?? j['District']);
    final sub = asMap(j['subDistrict'] ?? j['SubDistrict']);
    return VendorAddress(
      id: asInt(j['AddressID']) ?? 0,
      line1: asString(j['Line1']),
      line2: asString(j['Line2']),
      provinceId: asInt(j['ProvinceID']),
      districtId: asInt(j['DistrictID']),
      subDistrictId: asInt(j['SubDistrictID']),
      provinceName: asString(province?['name_th']),
      districtName: asString(district?['name_th']),
      subDistrictName: asString(sub?['name_th']),
      zipcode: asString(sub?['Zipcode']),
      isDefault: asBool(j['IsDefault']),
    );
  }

  final int id;
  final String? line1;
  final String? line2;
  final int? provinceId;
  final int? districtId;
  final int? subDistrictId;
  final String? provinceName;
  final String? districtName;
  final String? subDistrictName;
  final String? zipcode;
  final bool isDefault;

  /// One-line Thai address, e.g. "12/3 ถ.สุขุมวิท ต.บางนา อ.บางนา จ.กรุงเทพฯ 10260".
  String get fullText {
    final parts = <String>[
      ?line1,
      ?line2,
      if (subDistrictName != null) 'ต.$subDistrictName',
      if (districtName != null) 'อ.$districtName',
      if (provinceName != null) 'จ.$provinceName',
      ?zipcode,
    ];
    return parts.join(' ');
  }
}

/// `Vendors` row as returned by `GET /vendors` and `GET /vendors/:id`
/// (with `vendorType` and `addresses` [AddressTypeID 2] includes).
class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    this.typeId,
    this.typeName,
    this.idNumber,
    this.tel,
    this.rating = VendorRating.green,
    this.addresses = const [],
  });

  factory Vendor.fromJson(Map<String, dynamic> j) {
    final type = asMap(j['vendorType'] ?? j['VendorType']);
    return Vendor(
      id: asInt(j['VendorID']) ?? 0,
      name: asString(j['VendorName']) ?? '',
      typeId: asInt(j['VendorTypeID']),
      typeName: asString(type?['VendorType']),
      idNumber: asString(j['IDNumber']),
      tel: asString(j['VendorTel']),
      rating: VendorRating.parse(asString(j['RatingColor'])),
      addresses: asMapList(
        j['addresses'] ?? j['Addresses'],
      ).map(VendorAddress.fromJson).toList(),
    );
  }

  final int id;
  final String name;
  final int? typeId;
  final String? typeName;
  final String? idNumber;
  final String? tel;
  final VendorRating rating;
  final List<VendorAddress> addresses;

  /// Default address, else the first one.
  VendorAddress? get address {
    if (addresses.isEmpty) {
      return null;
    }
    for (final a in addresses) {
      if (a.isDefault) {
        return a;
      }
    }
    return addresses.first;
  }

  bool matches(String q) {
    final s = q.toLowerCase();
    return name.toLowerCase().contains(s) ||
        (tel ?? '').contains(s) ||
        (idNumber ?? '').contains(s) ||
        (typeName ?? '').toLowerCase().contains(s);
  }
}
