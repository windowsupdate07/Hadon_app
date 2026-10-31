import '../../core/utils/json.dart';
import '../parts/part_model.dart';
import 'totals.dart';

// JSON keys of included objects follow Sequelize's default association
// aliases (see ntp-api/models/index.js): belongsTo -> singular model name
// (`brand`, `model`, `employee`, `car`, `province`, `part`, `unit`, `preset`,
// `repairCategory`), hasMany -> plural (`repairs`, `quotationParts`,
// `presetDetails`).

/// Car registration text: "กข 1234 กรุงเทพมหานคร".
String carPlate(Map<String, dynamic>? car) {
  if (car == null) {
    return '';
  }
  final province = asMap(car['province']);
  return [
    asString(car['CarTitle']),
    asString(car['CarNumber']),
    asString(province?['name_th']),
  ].whereType<String>().join(' ').trim();
}

/// Customer display name with title (title 99 = "ไม่ระบุ" is hidden, like
/// the invoice PDF intends).
String customerName(Map<String, dynamic>? customer) {
  if (customer == null) {
    return '';
  }
  final title = asMap(customer['customerTitle']);
  final titleId = asInt(title?['CustomerTitleID'] ?? customer['CustomerTitleID']);
  final titleText = titleId == 99 ? null : asString(title?['CustomerTitle']);
  return [
    titleText,
    asString(customer['CustomerName']),
    asString(customer['CustomerSurname']),
  ].whereType<String>().join(' ').trim();
}

/// Repair created from a quotation (`quotation.repairs[]`).
class QuotationRepair {
  const QuotationRepair({required this.id, this.carId, this.customerId, this.car});

  factory QuotationRepair.fromJson(Map<String, dynamic> j) => QuotationRepair(
        id: asInt(j['RepairID']) ?? 0,
        carId: asInt(j['CarID']),
        customerId: asInt(j['CustomerID']),
        car: asMap(j['car']),
      );

  final int id;
  final int? carId;
  final int? customerId;
  final Map<String, dynamic>? car;

  String get plate => carPlate(car);
}

/// `Quotation` row from `GET /quotation` and `GET /quotation/:id`.
class Quotation {
  const Quotation({
    required this.id,
    this.date,
    this.isVat = false,
    this.brandId,
    this.modelId,
    this.brandName,
    this.modelName,
    this.comment,
    this.employeeId,
    this.employeeName,
    this.repairs = const [],
  });

  factory Quotation.fromJson(Map<String, dynamic> j) {
    final brand = asMap(j['brand']);
    final model = asMap(j['model']);
    final emp = asMap(j['employee']);
    return Quotation(
      id: asString(j['QuotationID']) ?? '',
      date: asDate(j['QuotationDate'] ?? j['createdAt']),
      isVat: isVatOn(asInt(j['isVat'])),
      brandId: asInt(j['BrandID']),
      modelId: asInt(j['ModelID']),
      brandName: asString(brand?['Brand']),
      modelName: asString(model?['Model']),
      comment: asString(j['Comment']),
      employeeId: asInt(j['EmployeeID']),
      employeeName: emp == null
          ? null
          : '${emp['FirstName'] ?? ''} ${emp['LastName'] ?? ''}'.trim(),
      repairs: asMapList(j['repairs']).map(QuotationRepair.fromJson).toList(),
    );
  }

  final String id;
  final DateTime? date;
  final bool isVat;
  final int? brandId;
  final int? modelId;
  final String? brandName;
  final String? modelName;
  final String? comment;
  final int? employeeId;
  final String? employeeName;

  /// Repairs created from this quotation via `/invoices/create-with-repair`.
  /// Non-empty means the quotation was already approved.
  final List<QuotationRepair> repairs;

  bool get isApproved => repairs.isNotEmpty;

  String get brandModel =>
      [brandName, modelName].whereType<String>().join(' ').trim();

  bool matches(String q) {
    final s = q.toLowerCase();
    bool has(String? v) => (v ?? '').toLowerCase().contains(s);
    return has(id) ||
        has(brandModel) ||
        has(comment) ||
        has(employeeName) ||
        repairs.any((r) => has(r.plate) || has('${r.id}'));
  }
}

/// `QuotationPart` row (a part line of a quotation item).
class QuotationPart {
  const QuotationPart({
    required this.id,
    required this.partId,
    required this.quantity,
    required this.pricePerUnit,
    required this.serviceFee,
    this.part,
  });

  factory QuotationPart.fromJson(Map<String, dynamic> j) {
    final part = asMap(j['part']);
    return QuotationPart(
      id: asInt(j['QuotationPartID']) ?? 0,
      partId: asInt(j['PartID']) ?? 0,
      quantity: asInt(j['NumOfUse']) ?? 0,
      pricePerUnit: asDouble(j['PricePerUnit']),
      serviceFee: asDouble(j['ServiceFee']),
      part: part == null ? null : Part.fromJson(part),
    );
  }

  final int id;
  final int partId;
  final int quantity;
  final double pricePerUnit;
  final double serviceFee;
  final Part? part;

  String get name => part?.displayName ?? 'อะไหล่ #$partId';

  double get total => quotationLineTotal(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        serviceFee: serviceFee,
      );
}

/// `QuotationDetail` row from `GET /quotation-detail/by-quotation-id/:id`.
class QuotationDetail {
  const QuotationDetail({
    required this.id,
    this.repairCategoryId,
    this.repairCategory,
    this.presetId,
    this.presetName,
    this.parts = const [],
  });

  factory QuotationDetail.fromJson(Map<String, dynamic> j) {
    final cat = asMap(j['repairCategory']);
    final preset = asMap(j['preset']);
    return QuotationDetail(
      id: asInt(j['QuotationDetailID']) ?? 0,
      repairCategoryId: asInt(j['RepairCategoryID']),
      repairCategory: asString(cat?['RepairCategory']),
      presetId: asInt(j['PresetID']),
      presetName: asString(preset?['Preset']),
      parts: asMapList(j['quotationParts']).map(QuotationPart.fromJson).toList(),
    );
  }

  final int id;
  final int? repairCategoryId;
  final String? repairCategory;
  final int? presetId;
  final String? presetName;
  final List<QuotationPart> parts;

  double get total => parts.fold(0, (a, p) => a + p.total);
}

/// `CashPledge` row (มัดจำ).
class CashPledge {
  const CashPledge({required this.id, required this.title, required this.amount});

  factory CashPledge.fromJson(Map<String, dynamic> j) => CashPledge(
        id: asInt(j['CashPledgeID']) ?? 0,
        title: asString(j['PledgeTitle']) ?? '',
        amount: asDouble(j['PledgeAmount']),
      );

  final int id;
  final String title;
  final double amount;
}

/// A part line of a preset (`presetDetails[]`).
class PresetPart {
  const PresetPart({required this.part, required this.quantity});

  final Part part;
  final int quantity;
}

/// Preset with its default parts.
class PresetOption {
  const PresetOption({required this.id, required this.name, this.parts = const []});

  factory PresetOption.fromJson(Map<String, dynamic> j) {
    final parts = <PresetPart>[];
    for (final d in asMapList(j['presetDetails'])) {
      final part = asMap(d['part']);
      if (part == null) {
        continue;
      }
      parts.add(PresetPart(part: Part.fromJson(part), quantity: asInt(d['NumOfUse']) ?? 1));
    }
    return PresetOption(
      id: asInt(j['PresetID']) ?? 0,
      name: asString(j['Preset']) ?? '-',
      parts: parts,
    );
  }

  final int id;
  final String name;
  final List<PresetPart> parts;

  @override
  bool operator ==(Object other) => other is PresetOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Row of `GET /refModelCategoryParts`: links a car model + repair category
/// to a preset.
class PresetRef {
  const PresetRef({
    this.modelId,
    this.repairCategoryId,
    this.active = true,
    this.preset,
  });

  factory PresetRef.fromJson(Map<String, dynamic> j) {
    final preset = asMap(j['preset']);
    return PresetRef(
      modelId: asInt(j['ModelID']),
      repairCategoryId: asInt(j['RepairCategoryID']),
      active: (asInt(j['Status']) ?? 1) == 1,
      preset: preset == null ? null : PresetOption.fromJson(preset),
    );
  }

  final int? modelId;
  final int? repairCategoryId;
  final bool active;
  final PresetOption? preset;
}

/// Car with owner, from `GET /cars` or `GET /cars/by-model/:id`.
class CarOption {
  const CarOption({
    required this.id,
    this.customerId,
    this.brandId,
    this.modelId,
    this.raw = const {},
  });

  factory CarOption.fromJson(Map<String, dynamic> j) => CarOption(
        id: asInt(j['CarID']) ?? 0,
        customerId: asInt(j['CustomerID']),
        brandId: asInt(j['BrandID']),
        modelId: asInt(j['ModelID']),
        raw: j,
      );

  final int id;
  final int? customerId;
  final int? brandId;
  final int? modelId;
  final Map<String, dynamic> raw;

  String get plate => carPlate(raw);

  String get owner => customerName(asMap(raw['customer']));

  String get brandModel => [
        asString(asMap(raw['brand'])?['Brand']),
        asString(asMap(raw['model'])?['Model']),
      ].whereType<String>().join(' ');

  bool matches(String q) {
    final s = q.toLowerCase();
    return plate.toLowerCase().contains(s) ||
        owner.toLowerCase().contains(s) ||
        brandModel.toLowerCase().contains(s) ||
        (asString(raw['VIN']) ?? '').toLowerCase().contains(s);
  }
}

/// Editable part line used when building a new quotation item.
class DraftPart {
  DraftPart({
    required this.part,
    required this.quantity,
    required this.pricePerUnit,
    required this.serviceFee,
  });

  final Part part;
  int quantity;
  double pricePerUnit;
  double serviceFee;

  double get total => quotationLineTotal(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        serviceFee: serviceFee,
      );

  /// Body item for `POST /quotation-detail/create-with-parts`.
  Map<String, dynamic> toJson() => {
        'PartID': part.id,
        'NumOfUse': quantity,
        'PricePerUnit': pricePerUnit,
        'ServiceFee': serviceFee,
      };
}
