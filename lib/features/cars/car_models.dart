import '../../core/utils/json.dart';
import '../customers/customer_models.dart';

/// Row of the `Cars` table. `GET /cars` includes `customer` (with
/// `customerTitle`), `brand`, `model`, `province` and `repairs` (ids only);
/// cars nested in a customer only include brand, model and province.
class Car {
  const Car({
    required this.id,
    this.customerId,
    this.brandId,
    this.brandName,
    this.modelId,
    this.modelName,
    this.carTitle,
    this.carNumber,
    this.provinceId,
    this.provinceName,
    this.vin,
    this.ec,
    this.customer,
    this.repairIds = const [],
  });

  factory Car.fromJson(Map<String, dynamic> j) {
    final customer = asMap(j['customer']);
    final ids = asMapList(j['repairs'])
        .map((r) => asInt(r['RepairID']))
        .whereType<int>()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return Car(
      id: asInt(j['CarID']) ?? 0,
      customerId: asInt(j['CustomerID']),
      brandId: asInt(j['BrandID']),
      brandName: asString(asMap(j['brand'])?['Brand']),
      modelId: asInt(j['ModelID']),
      modelName: asString(asMap(j['model'])?['Model']),
      carTitle: asString(j['CarTitle']),
      carNumber: asString(j['CarNumber']),
      provinceId: asInt(j['ProvinceID']),
      provinceName: asString(asMap(j['province'])?['name_th']),
      vin: asString(j['VIN']),
      ec: asString(j['EC']),
      customer: customer == null ? null : Customer.fromJson(customer),
      repairIds: ids,
    );
  }

  final int id;
  final int? customerId;
  final int? brandId;
  final String? brandName;
  final int? modelId;
  final String? modelName;
  final String? carTitle;
  final String? carNumber;
  final int? provinceId;
  final String? provinceName;
  final String? vin;
  final String? ec;
  final Customer? customer;

  /// Repair job ids, newest first.
  final List<int> repairIds;

  /// "8กณ 8935"
  String get plate {
    final p = '${carTitle ?? ''} ${carNumber ?? ''}'.trim();
    return p.isEmpty ? 'รถ #$id' : p;
  }

  /// "8กณ 8935 กรุงเทพมหานคร"
  String get plateWithProvince =>
      provinceName == null ? plate : '$plate $provinceName';

  /// "Honda City"
  String get brandModel {
    final s = '${brandName ?? ''} ${modelName ?? ''}'.trim();
    return s.isEmpty ? '-' : s;
  }

  /// Body for `POST /cars` and `PUT /cars/:id`.
  Map<String, dynamic> toJson() => {
        'CustomerID': customerId,
        'BrandID': brandId,
        'ModelID': modelId,
        'CarTitle': carTitle,
        'CarNumber': carNumber,
        'ProvinceID': provinceId,
        'VIN': vin,
        'EC': ec,
      };

  /// Search by plate, plate province, brand / model, owner and VIN / engine no.
  bool matches(String q) {
    final s = q.toLowerCase().replaceAll(' ', '');
    bool has(String? v) =>
        (v ?? '').toLowerCase().replaceAll(' ', '').contains(s);
    return has(plate) ||
        has(provinceName) ||
        has(brandModel) ||
        has(customer?.fullName) ||
        has(customer?.tel) ||
        has(vin) ||
        has(ec);
  }
}
