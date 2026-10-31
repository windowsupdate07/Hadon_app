import '../../core/utils/json.dart';
import '../customers/customer_models.dart';

/// Row of the `Cars` table.
///
/// `GET /cars`, `GET /cars/:id` and `GET /cars/by-customer/:id` include
/// `customer` (with `customerTitle`), `brand`, `model`, `province` and
/// `repairs` (ids only). Cars nested in a customer (`GET /customers[/:id]`)
/// only include brand, model and province.
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
    this.color,
    this.customer,
    this.repairIds = const [],
    this.repairsKnown = false,
  });

  factory Car.fromJson(Map<String, dynamic> j) {
    final customer = asMap(j['customer']);
    final ids =
        asMapList(
            j['repairs'],
          ).map((r) => asInt(r['RepairID'])).whereType<int>().toList()
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
      color: asString(j['Color']),
      customer: customer == null ? null : Customer.fromJson(customer),
      repairIds: ids,
      repairsKnown: j['repairs'] is List,
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

  /// `Cars.Color` (free text, e.g. "ขาว").
  final String? color;
  final Customer? customer;

  /// Repair job ids, newest first.
  final List<int> repairIds;

  /// Whether the payload included `repairs` (false for cars nested in a
  /// customer), i.e. whether [repairIds] can be trusted.
  final bool repairsKnown;

  bool get hasRepairs => repairIds.isNotEmpty;

  /// The web locks brand / model once a car has repair jobs (repairs copy
  /// BrandID / ModelID). Unknown repair state is treated as locked.
  bool get brandModelLocked => !repairsKnown || hasRepairs;

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

  /// "Honda City · สีขาว"
  String get brandModelColor =>
      color == null ? brandModel : '$brandModel · สี$color';

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
    'Color': color,
  };

  /// Search like the web table: id, plate, plate province, brand / model,
  /// colour, owner and VIN / engine no.
  bool matches(String q) {
    final s = q.toLowerCase().replaceAll(' ', '');
    bool has(String? v) =>
        (v ?? '').toLowerCase().replaceAll(' ', '').contains(s);
    return has('$id') ||
        has(plate) ||
        has(provinceName) ||
        has(brandModel) ||
        has(color) ||
        has(customer?.fullName) ||
        has(customer?.tel) ||
        has(vin) ||
        has(ec);
  }
}

/// Result of `POST /cars/check-existence`.
class CarExistence {
  const CarExistence({this.existingCustomer, this.existingCar});

  factory CarExistence.fromJson(Map<String, dynamic> j) {
    final customer = asMap(j['existingCustomer']);
    final car = asMap(j['existingCar']);
    return CarExistence(
      existingCustomer: customer == null ? null : Customer.fromJson(customer),
      existingCar: car == null ? null : Car.fromJson(car),
    );
  }

  /// Customer matching name + surname, or ID number (no title / addresses).
  final Customer? existingCustomer;

  /// Car matching the plate (+ province); `customer` is included without
  /// its title.
  final Car? existingCar;
}

/// One job of `GET /repair/by-car/:id` (the web's "ประวัติการซ่อม").
class CarRepairRecord {
  const CarRepairRecord({
    required this.id,
    this.repairDate,
    this.createdAt,
    this.workStatusId,
    this.workStatusLabel,
    this.presets = const [],
    this.mileage,
    this.paidAmount = 0,
  });

  factory CarRepairRecord.fromJson(Map<String, dynamic> j) {
    final quotation = asMap(j['quotation']);
    var paid = 0.0;
    for (final inv in asMapList(quotation?['invoices'])) {
      for (final r in asMapList(inv['receipts'])) {
        paid += asDouble(r['Amount']);
      }
    }
    return CarRepairRecord(
      id: asInt(j['RepairID']) ?? 0,
      repairDate: asDate(j['RepairDate']),
      createdAt: asDate(j['createdAt']),
      workStatusId: asInt(j['WorkStatusID']),
      workStatusLabel: asString(asMap(j['workStatus'])?['WorkStatus_th']),
      presets: asMapList(j['repairDetails'])
          .map((d) => asString(asMap(d['preset'])?['Preset']))
          .whereType<String>()
          .toList(),
      mileage: quotation?['Mileage'] == null
          ? null
          : asDouble(quotation!['Mileage']),
      paidAmount: paid,
    );
  }

  final int id;
  final DateTime? repairDate;
  final DateTime? createdAt;
  final int? workStatusId;

  /// Thai label from the server (`workStatus.WorkStatus_th`).
  final String? workStatusLabel;

  /// Preset names of the repair details.
  final List<String> presets;

  /// Mileage from the quotation, in km.
  final double? mileage;

  /// Sum of confirmed receipts (`RecieptStatusID` 1) of the job's invoices.
  final double paidAmount;

  DateTime? get date => createdAt ?? repairDate;
}
