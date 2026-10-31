import '../../core/utils/json.dart';
import '../auth/employee.dart';
import '../parts/part_model.dart';

/// Repair job (`Repair` table) as returned by `GET /repair` and
/// `GET /repair/:id` (includes car, customer, workStatus, employee and
/// attendees).
class Repair {
  const Repair({
    required this.id,
    this.workStatusId,
    this.repairDate,
    this.createdAt,
    this.quotationId,
    this.carId,
    this.customerId,
    this.brandId,
    this.modelId,
    this.carTitle,
    this.carNumber,
    this.provinceName,
    this.vin,
    this.ec,
    this.brandName,
    this.modelName,
    this.customerName,
    this.customerTel,
    this.employeeName,
    this.attendees = const [],
  });

  factory Repair.fromJson(Map<String, dynamic> j) {
    final car = asMap(j['car']);
    final customer = asMap(j['customer']);
    final title = asMap(customer?['customerTitle']);
    final employee = asMap(j['employee']);
    final customerName = [
      asString(title?['CustomerTitle']),
      asString(customer?['CustomerName']),
      asString(customer?['CustomerSurname']),
    ].whereType<String>().join(' ').trim();
    final employeeName = [
      asString(employee?['FirstName']),
      asString(employee?['LastName']),
    ].whereType<String>().join(' ').trim();

    return Repair(
      id: asInt(j['RepairID']) ?? 0,
      workStatusId: asInt(j['WorkStatusID']),
      repairDate: asDate(j['RepairDate']),
      createdAt: asDate(j['createdAt']),
      quotationId: asString(j['QuotationID']),
      carId: asInt(j['CarID']),
      customerId: asInt(j['CustomerID']),
      brandId: asInt(j['BrandID']) ?? asInt(car?['BrandID']),
      modelId: asInt(j['ModelID']) ?? asInt(car?['ModelID']),
      carTitle: asString(car?['CarTitle']),
      carNumber: asString(car?['CarNumber']),
      provinceName: asString(asMap(car?['province'])?['name_th']),
      vin: asString(car?['VIN']),
      ec: asString(car?['EC']),
      brandName: asString(asMap(car?['brand'])?['Brand']),
      modelName: asString(asMap(car?['model'])?['Model']),
      customerName: customerName.isEmpty ? null : customerName,
      customerTel: asString(customer?['CustomerTel']),
      employeeName: employeeName.isEmpty ? null : employeeName,
      attendees: asMapList(j['attendees']).map(Employee.fromJson).toList(),
    );
  }

  final int id;
  final int? workStatusId;
  final DateTime? repairDate;
  final DateTime? createdAt;
  final String? quotationId;
  final int? carId;
  final int? customerId;
  final int? brandId;
  final int? modelId;
  final String? carTitle;
  final String? carNumber;
  final String? provinceName;
  final String? vin;
  final String? ec;
  final String? brandName;
  final String? modelName;
  final String? customerName;
  final String? customerTel;
  final String? employeeName;
  final List<Employee> attendees;

  /// e.g. "กข 1234".
  String get plate {
    final s = [carTitle, carNumber].whereType<String>().join(' ').trim();
    return s.isEmpty ? '-' : s;
  }

  /// e.g. "Honda Civic".
  String get brandModel {
    final s = [brandName, modelName].whereType<String>().join(' ').trim();
    return s.isEmpty ? '-' : s;
  }

  /// Date used for sorting / display (falls back to createdAt).
  DateTime? get date => repairDate ?? createdAt;

  bool matches(String q) {
    final s = q.toLowerCase().replaceAll(' ', '');
    final plateKey = '${carTitle ?? ''}${carNumber ?? ''}'
        .toLowerCase()
        .replaceAll(' ', '');
    return plateKey.contains(s) ||
        (customerName ?? '').toLowerCase().replaceAll(' ', '').contains(s) ||
        (customerTel ?? '').contains(s) ||
        id.toString() == s ||
        '#$id' == s;
  }
}

/// Part used in a repair item (`RepairPart`, includes `part` + `partStatus`).
class RepairPartLine {
  const RepairPartLine({
    required this.id,
    required this.repairDetailId,
    this.partId,
    this.numOfUse = 0,
    this.pricePerUnit = 0,
    this.serviceFee = 0,
    this.discount = 0,
    this.isDiscount = 1,
    this.partStatusId,
    this.partName,
    this.partNumber,
    this.unitName,
  });

  factory RepairPartLine.fromJson(Map<String, dynamic> j) {
    final part = asMap(j['part']);
    return RepairPartLine(
      id: asInt(j['RepairPartID']) ?? 0,
      repairDetailId: asInt(j['RepairDetailID']) ?? 0,
      partId: asInt(j['PartID']),
      numOfUse: asInt(j['NumOfUse']) ?? 0,
      pricePerUnit: asDouble(j['PricePerUnit']),
      serviceFee: asDouble(j['ServiceFee']),
      discount: asDouble(j['Discount']),
      isDiscount: asInt(j['isDiscount']) ?? 1,
      partStatusId: asInt(j['PartStatusID']),
      partName:
          asString(part?['PartName_th']) ?? asString(part?['PartName_en']),
      partNumber: asString(part?['PartNumber']),
      unitName: asString(asMap(part?['unit'])?['Unit']),
    );
  }

  final int id;
  final int repairDetailId;
  final int? partId;
  final int numOfUse;
  final double pricePerUnit;
  final double serviceFee;

  /// Baht when [isDiscount] == 1, otherwise percent (same rule as the
  /// invoice PDF in `pdfCreateInvoice.controller.js`).
  final double discount;
  final int isDiscount;
  final int? partStatusId;
  final String? partName;
  final String? partNumber;
  final String? unitName;

  bool get discountIsBaht => isDiscount == 1;

  String get displayName =>
      partName ?? partNumber ?? 'อะไหล่ #${partId ?? '-'}';

  double get subtotal => numOfUse * pricePerUnit + serviceFee;

  double get discountAmount =>
      discountIsBaht ? discount : discount / 100 * subtotal;

  double get total => subtotal - discountAmount;
}

/// Repair item (`RepairDetail`) with its category, preset and parts.
class RepairItem {
  const RepairItem({
    required this.id,
    required this.repairId,
    this.repairCategoryId,
    this.categoryName,
    this.presetId,
    this.presetName,
    this.parts = const [],
  });

  factory RepairItem.fromJson(Map<String, dynamic> j) {
    return RepairItem(
      id: asInt(j['RepairDetailID']) ?? 0,
      repairId: asInt(j['RepairID']) ?? 0,
      repairCategoryId: asInt(j['RepairCategoryID']),
      categoryName: asString(asMap(j['repairCategory'])?['RepairCategory']),
      presetId: asInt(j['PresetID']),
      presetName: asString(asMap(j['preset'])?['Preset']),
      parts: asMapList(j['repairParts']).map(RepairPartLine.fromJson).toList(),
    );
  }

  final int id;
  final int repairId;
  final int? repairCategoryId;
  final String? categoryName;
  final int? presetId;
  final String? presetName;
  final List<RepairPartLine> parts;

  double get total => parts.fold(0, (sum, p) => sum + p.total);
}

/// Part + default quantity inside a preset (`PresetDetails`).
class PresetPart {
  const PresetPart(this.part, this.numOfUse);

  final Part part;
  final int numOfUse;
}

/// Brand/model/category a preset applies to (`Ref_Model_Category_Parts`).
class PresetRef {
  const PresetRef({this.repairCategoryId, this.brandId, this.modelId});

  final int? repairCategoryId;
  final int? brandId;
  final int? modelId;
}

/// Preset as returned by `GET /preset` (includes presetDetails.part and
/// ref_model_category_parts).
class Preset {
  const Preset({
    required this.id,
    required this.name,
    this.status = 1,
    this.parts = const [],
    this.refs = const [],
  });

  factory Preset.fromJson(Map<String, dynamic> j) {
    final details = asMapList(j['presetDetails'] ?? j['PresetDetails']);
    final refs = asMapList(
      j['ref_model_category_parts'] ?? j['Ref_Model_Category_Parts'],
    );
    return Preset(
      id: asInt(j['PresetID']) ?? 0,
      name: asString(j['Preset']) ?? '-',
      status: asInt(j['Status']) ?? 1,
      parts: [
        for (final d in details)
          if (asMap(d['part']) != null)
            PresetPart(
              Part.fromJson(asMap(d['part'])!),
              asInt(d['NumOfUse']) ?? 1,
            ),
      ],
      refs: [
        for (final r in refs)
          PresetRef(
            repairCategoryId: asInt(r['RepairCategoryID']),
            brandId: asInt(r['BrandID']),
            modelId: asInt(r['ModelID']),
          ),
      ],
    );
  }

  final int id;
  final String name;
  final int status;
  final List<PresetPart> parts;
  final List<PresetRef> refs;

  bool get isActive => status == 1;

  bool appliesToCategory(int categoryId) =>
      refs.any((r) => r.repairCategoryId == categoryId);

  /// True when a ref matches the category and car model (or brand when the
  /// ref has no model).
  bool appliesToCar(int categoryId, int? brandId, int? modelId) {
    return refs.any(
      (r) =>
          r.repairCategoryId == categoryId &&
          (r.modelId == null || r.modelId == modelId) &&
          (r.brandId == null || r.brandId == brandId),
    );
  }
}

/// Car photo (`ImageCar`, includes `imageCarType`).
class CarImage {
  const CarImage({
    required this.id,
    required this.repairId,
    required this.fileName,
    this.typeId,
    this.typeName,
  });

  factory CarImage.fromJson(Map<String, dynamic> j) {
    return CarImage(
      id: asInt(j['ImageCarID']) ?? 0,
      repairId: asInt(j['RepairID']) ?? 0,
      fileName: asString(j['FileName']) ?? '',
      typeId: asInt(j['ImageCarTypeID']),
      typeName: asString(asMap(j['imageCarType'])?['ImageCarType']),
    );
  }

  final int id;
  final int repairId;
  final String fileName;
  final int? typeId;
  final String? typeName;
}

/// Minimal invoice info linked to a repair.
class RepairInvoice {
  const RepairInvoice({
    required this.invoiceId,
    this.statusId,
    this.statusTitle,
    this.invoiceDate,
  });

  factory RepairInvoice.fromJson(Map<String, dynamic> j) {
    return RepairInvoice(
      invoiceId: asString(j['InvoiceID']) ?? '',
      statusId: asInt(j['InvoiceStatusID']),
      statusTitle: asString(asMap(j['invoiceStatus'])?['InvoiceStatus']),
      invoiceDate: asDate(j['InvoiceDate']) ?? asDate(j['createdAt']),
    );
  }

  final String invoiceId;
  final int? statusId;
  final String? statusTitle;
  final DateTime? invoiceDate;
}
