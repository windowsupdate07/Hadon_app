import 'dart:convert';

import '../../core/utils/json.dart';
import '../auth/employee.dart';
import '../parts/part_model.dart';

/// How the customer collects the car (`Repair.ReceiveType`).
class ReceiveType {
  ReceiveType._();

  /// Customer waits at the garage.
  static const wait = 1;

  /// Customer comes back at `ReceiveAppointmentDate`.
  static const appointment = 2;
}

/// Repair job (`Repair` table) as returned by `GET /repair` and
/// `GET /repair/:id` (includes car.brand/model/province, customer with
/// customerTitle/addresses, workStatus, employee, attendees and quotation).
class Repair {
  const Repair({
    required this.id,
    this.workStatusId,
    this.workStatusLabel,
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
    this.carColor,
    this.brandName,
    this.modelName,
    this.customerName,
    this.customerTel,
    this.customerIdNumber,
    this.customerAddress,
    this.employeeName,
    this.receiveType,
    this.receiveAppointmentDate,
    this.mileage,
    this.gasInstallation,
    this.tireType,
    this.taxDate,
    this.attendees = const [],
  });

  factory Repair.fromJson(Map<String, dynamic> j) {
    final car = asMap(j['car']);
    final customer = asMap(j['customer']);
    final title = asMap(customer?['customerTitle']);
    final employee = asMap(j['employee']);
    final quotation = asMap(j['quotation']);
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
      workStatusId:
          asInt(j['WorkStatusID']) ??
          asInt(asMap(j['workStatus'])?['WorkStatusID']),
      workStatusLabel: asString(asMap(j['workStatus'])?['WorkStatus_th']),
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
      carColor: asString(car?['Color']),
      brandName: asString(asMap(car?['brand'])?['Brand']),
      modelName: asString(asMap(car?['model'])?['Model']),
      customerName: customerName.isEmpty ? null : customerName,
      customerTel: asString(customer?['CustomerTel']),
      customerIdNumber: asString(customer?['IDNumber']),
      customerAddress: _defaultAddress(customer?['addresses']),
      employeeName: employeeName.isEmpty ? null : employeeName,
      receiveType: asInt(j['ReceiveType']),
      receiveAppointmentDate: asDate(j['ReceiveAppointmentDate']),
      mileage: asInt(quotation?['Mileage']),
      gasInstallation: asInt(quotation?['GasInstalation']),
      tireType: asInt(quotation?['TireType']),
      taxDate: asDate(quotation?['TaxDate']),
      attendees: asMapList(j['attendees']).map(Employee.fromJson).toList(),
    );
  }

  /// Same format as the web: "Line1 Line2 ตำบล, อำเภอ, จังหวัด Zipcode",
  /// using the default address (or the first one).
  static String? _defaultAddress(dynamic raw) {
    final list = asMapList(raw);
    if (list.isEmpty) {
      return null;
    }
    final a = list.firstWhere(
      (e) => asBool(e['IsDefault']),
      orElse: () => list.first,
    );
    final sub = asMap(a['subDistrict']);
    final parts = [
      [
        asString(a['Line1']),
        asString(a['Line2']),
      ].whereType<String>().join(' '),
      asString(sub?['name_th']),
      asString(asMap(a['district'])?['name_th']),
      [
        asString(asMap(a['province'])?['name_th']),
        asString(sub?['Zipcode']),
      ].whereType<String>().join(' '),
    ].where((s) => s != null && s.trim().isNotEmpty).join(', ');
    return parts.isEmpty ? null : parts;
  }

  final int id;
  final int? workStatusId;

  /// `workStatus.WorkStatus_th` from the server (fallback label).
  final String? workStatusLabel;
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
  final String? carColor;
  final String? brandName;
  final String? modelName;
  final String? customerName;
  final String? customerTel;
  final String? customerIdNumber;
  final String? customerAddress;
  final String? employeeName;

  /// See [ReceiveType].
  final int? receiveType;
  final DateTime? receiveAppointmentDate;

  /// From the linked quotation.
  final int? mileage;

  /// 1 = gas installed.
  final int? gasInstallation;

  /// 1 = nitrogen.
  final int? tireType;
  final DateTime? taxDate;
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
        (quotationId ?? '').toLowerCase().contains(s) ||
        id.toString() == s ||
        '#$id' == s;
  }
}

/// Part used in a repair item (`RepairPart`, includes `part.unit` and
/// `partStatus`).
class RepairPartLine {
  const RepairPartLine({
    required this.id,
    required this.repairDetailId,
    this.partId,
    this.numOfUse = 0,
    this.allocatedNum = 0,
    this.pricePerUnit = 0,
    this.serviceFee = 0,
    this.discount = 0,
    this.isDiscount = 1,
    this.partStatusId,
    this.partStatusLabel,
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
      allocatedNum: asInt(j['AllocatedNum']) ?? 0,
      pricePerUnit: asDouble(j['PricePerUnit']),
      serviceFee: asDouble(j['ServiceFee']),
      discount: asDouble(j['Discount']),
      isDiscount: asInt(j['isDiscount']) ?? 1,
      partStatusId: asInt(j['PartStatusID']),
      partStatusLabel: asString(asMap(j['partStatus'])?['PartStatus_th']),
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

  /// Quantity already handed out by the allocation team. The backend sets
  /// it to `NumOfUse` whenever the repair moves to REPAIRING (5); while in
  /// ALLOCATE MORE (9) the allocation page works on `NumOfUse - AllocatedNum`.
  final int allocatedNum;
  final double pricePerUnit;
  final double serviceFee;

  /// Edited on the invoice page. Baht when [isDiscount] == 1, otherwise
  /// percent (`pdfCreateInvoice.controller.js` uses 2 for percent).
  final double discount;
  final int isDiscount;
  final int? partStatusId;
  final String? partStatusLabel;
  final String? partName;
  final String? partNumber;
  final String? unitName;

  bool get discountIsBaht => isDiscount == 1;

  String get displayName =>
      partName ?? partNumber ?? 'อะไหล่ #${partId ?? '-'}';

  /// Same as the web repair pages: price × qty + service fee (discounts are
  /// applied on the invoice).
  double get subtotal => numOfUse * pricePerUnit + serviceFee;

  /// `NumOfUse - AllocatedNum`; meaningful once the parts were allocated.
  int get allocationDiff => numOfUse - allocatedNum;
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

  /// Preset name is the item title on the web; category is secondary.
  String get title => presetName ?? categoryName ?? 'รายการ #$id';

  double get subtotal => parts.fold(0, (sum, p) => sum + p.subtotal);
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

/// Car photo (`ImageCar`, includes `imageCarType`). Photos belong to the
/// quotation, not the repair.
class CarImage {
  const CarImage({
    required this.id,
    required this.quotationId,
    required this.fileName,
    this.typeId,
    this.typeName,
  });

  factory CarImage.fromJson(Map<String, dynamic> j) {
    final type = asMap(j['imageCarType']);
    return CarImage(
      id: asInt(j['ImageCarID']) ?? 0,
      quotationId: asString(j['QuotationID']) ?? '',
      fileName: asString(j['FileName']) ?? '',
      typeId: asInt(j['ImageCarTypeID']) ?? asInt(type?['ImageCarTypeID']),
      typeName: asString(type?['ImageCarType']),
    );
  }

  final int id;
  final String quotationId;
  final String fileName;
  final int? typeId;
  final String? typeName;
}

/// Minimal invoice info linked to a repair (`GET /invoices/by-repair-id`).
class RepairInvoice {
  const RepairInvoice({
    required this.invoiceId,
    this.statusId,
    this.statusTitle,
    this.invoiceDate,
    this.amount,
  });

  factory RepairInvoice.fromJson(Map<String, dynamic> j) {
    return RepairInvoice(
      invoiceId: asString(j['InvoiceID']) ?? '',
      statusId:
          asInt(j['InvoiceStatusID']) ??
          asInt(asMap(j['invoiceStatus'])?['InvoiceStatusID']),
      statusTitle: asString(asMap(j['invoiceStatus'])?['InvoiceStatus']),
      invoiceDate: asDate(j['InvoiceDate']) ?? asDate(j['createdAt']),
      amount: j['Amount'] == null ? null : asDouble(j['Amount']),
    );
  }

  final String invoiceId;
  final int? statusId;
  final String? statusTitle;
  final DateTime? invoiceDate;

  /// Set when the invoice is confirmed.
  final double? amount;
}

/// Entry of `GET /repair/logs/:id` (`RepairLog` + employee).
class RepairLog {
  const RepairLog({
    required this.id,
    required this.action,
    required this.module,
    this.details,
    this.referenceId,
    this.createdAt,
    this.employeeName,
  });

  factory RepairLog.fromJson(Map<String, dynamic> j) {
    final e = asMap(j['employee']);
    final name = [
      asString(e?['FirstName']),
      asString(e?['LastName']),
    ].whereType<String>().join(' ').trim();
    return RepairLog(
      id: asInt(j['LogID']) ?? 0,
      action: asString(j['Action']) ?? '-',
      module: asString(j['Module']) ?? '-',
      details: asString(j['Details']),
      referenceId: asString(j['ReferenceID']),
      createdAt: asDate(j['createdAt']),
      employeeName: name.isEmpty ? null : name,
    );
  }

  final int id;

  /// สร้าง / แก้ไข / ลบ / ยกเลิก.
  final String action;

  /// ใบรับรถ / รายละเอียดการซ่อม / อะไหล่ซ่อม / ใบเสนอราคา / ...
  final String module;
  final String? details;
  final String? referenceId;
  final DateTime? createdAt;

  /// Null means the action was done by the system.
  final String? employeeName;

  /// Part edits (`PUT /repairPart/bulk/update`) store the raw `updates`
  /// array as JSON; returns it as rows, or null for plain-text details.
  List<Map<String, dynamic>>? get jsonRows {
    final d = details?.trim();
    if (d == null || !(d.startsWith('[') || d.startsWith('{'))) {
      return null;
    }
    try {
      final decoded = jsonDecode(d);
      if (decoded is List) {
        return asMapList(decoded);
      }
      final m = asMap(decoded);
      return m == null ? null : [m];
    } catch (_) {
      return null;
    }
  }
}
