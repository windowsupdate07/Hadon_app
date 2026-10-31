import '../../core/constants/statuses.dart';
import '../../core/utils/json.dart';
import '../parts/part_model.dart';
import 'totals.dart';

// JSON keys of included objects follow Sequelize's default association
// aliases (honda-ntp-antigravity/backend/models/index.js): belongsTo ->
// singular model name (`brand`, `model`, `employee`, `car`, `customer`,
// `address`, `province`, `district`, `subDistrict`, `part`, `unit`, `preset`,
// `repairCategory`, `invoice`, `imageCarType`), hasMany -> plural (`repairs`,
// `invoices`, `receipts`, `cashPledges`, `quotationDetails`,
// `quotationParts`, `presetDetails`).

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

/// Address text as printed by the PDFs:
/// "Line1 Line2, ตำบล, อำเภอ, จังหวัด 10000".
String addressText(Map<String, dynamic>? address) {
  if (address == null) {
    return '';
  }
  final sub = asMap(address['subDistrict']);
  final line = [asString(address['Line1']), asString(address['Line2'])]
      .whereType<String>()
      .join(' ');
  return [
    line,
    asString(sub?['name_th']),
    asString(asMap(address['district'])?['name_th']),
    [asString(asMap(address['province'])?['name_th']), asString(sub?['Zipcode'])]
        .whereType<String>()
        .join(' '),
  ].where((s) => s != null && s.isNotEmpty).join(', ');
}

String? _employeeName(Map<String, dynamic>? emp) => emp == null
    ? null
    : '${emp['FirstName'] ?? ''} ${emp['LastName'] ?? ''}'.trim();

/// Receipt status values (`seeders/data/recieptStatus.json`).
class ReceiptStatus {
  ReceiptStatus._();

  static const paid = 1;
  static const voided = 2;
}

/// Repair created from a quotation (`quotation.repairs[]`).
class QuotationRepair {
  const QuotationRepair({
    required this.id,
    this.carId,
    this.customerId,
    this.workStatusId,
    this.car,
    this.invoiceIds = const [],
    this.receiptStatuses = const [],
  });

  factory QuotationRepair.fromJson(Map<String, dynamic> j) {
    final invoices = asMapList(j['invoices']);
    return QuotationRepair(
      id: asInt(j['RepairID']) ?? 0,
      carId: asInt(j['CarID']),
      customerId: asInt(j['CustomerID']),
      workStatusId: asInt(j['WorkStatusID']),
      car: asMap(j['car']),
      invoiceIds: invoices.map((i) => asString(i['InvoiceID'])).whereType<String>().toList(),
      receiptStatuses: [
        for (final inv in invoices)
          for (final r in asMapList(inv['receipts'])) asInt(r['RecieptStatusID']),
      ].whereType<int>().toList(),
    );
  }

  final int id;
  final int? carId;
  final int? customerId;
  final int? workStatusId;
  final Map<String, dynamic>? car;

  /// `repairs[].invoices[].InvoiceID`.
  final List<String> invoiceIds;

  /// `repairs[].invoices[].receipts[].RecieptStatusID`.
  final List<int> receiptStatuses;

  bool get isCancelled => workStatusId == WorkStatus.cancel;

  String get plate => carPlate(car);
}

/// Part line summary included in `GET /quotation` (`quotationDetails[]
/// .quotationParts[]` with `NumOfUse` and `part.PartAmount` only).
class QuotationStockLine {
  const QuotationStockLine({required this.quantity, required this.inStock});

  final int quantity;
  final double inStock;

  bool get isShort => quantity > inStock;
}

/// `Quotation` row from `GET /quotation` and `GET /quotation/:id`.
class Quotation {
  const Quotation({
    required this.id,
    this.date,
    this.isVat = false,
    this.vatType = VatType.include,
    this.brandId,
    this.modelId,
    this.carId,
    this.customerId,
    this.addressId,
    this.mileage,
    this.gasInstallation = 0,
    this.tireType = 0,
    this.taxDate,
    this.brandName,
    this.modelName,
    this.comment,
    this.employeeId,
    this.employeeName,
    this.car,
    this.customer,
    this.address,
    this.repairs = const [],
    this.pledgeAmounts = const [],
    this.stockLines = const [],
  });

  factory Quotation.fromJson(Map<String, dynamic> j) {
    final brand = asMap(j['brand']);
    final model = asMap(j['model']);
    return Quotation(
      id: asString(j['QuotationID']) ?? '',
      date: asDate(j['QuotationDate'] ?? j['createdAt']),
      isVat: isVatOn(j['isVat']),
      vatType: asInt(j['VatType']) ?? VatType.include,
      brandId: asInt(j['BrandID']),
      modelId: asInt(j['ModelID']),
      carId: asInt(j['CarID']),
      customerId: asInt(j['CustomerID']),
      addressId: asInt(j['AddressID']),
      mileage: asInt(j['Mileage']),
      gasInstallation: asInt(j['GasInstalation']) ?? 0,
      tireType: asInt(j['TireType']) ?? 0,
      // DATEONLY "yyyy-MM-dd": parse without converting time zones.
      taxDate: DateTime.tryParse(asString(j['TaxDate']) ?? ''),
      brandName: asString(brand?['Brand']),
      modelName: asString(model?['Model']),
      comment: asString(j['Comment']),
      employeeId: asInt(j['EmployeeID']),
      employeeName: _employeeName(asMap(j['employee'])),
      car: asMap(j['car']),
      customer: asMap(j['customer']),
      address: asMap(j['address']),
      repairs: asMapList(j['repairs']).map(QuotationRepair.fromJson).toList(),
      pledgeAmounts: asMapList(j['cashPledges'])
          .map((p) => asDouble(p['PledgeAmount']))
          .toList(),
      stockLines: [
        for (final d in asMapList(j['quotationDetails']))
          for (final p in asMapList(d['quotationParts']))
            QuotationStockLine(
              quantity: asInt(p['NumOfUse']) ?? 0,
              inStock: asDouble(asMap(p['part'])?['PartAmount']),
            ),
      ],
    );
  }

  final String id;
  final DateTime? date;
  final bool isVat;

  /// [VatType.include] (0) or [VatType.exclude] (1).
  final int vatType;
  final int? brandId;
  final int? modelId;
  final int? carId;
  final int? customerId;
  final int? addressId;
  final int? mileage;

  /// 0 = ไม่ติดแก๊ส, 1 = ติดแก๊ส (column is spelled `GasInstalation`).
  final int gasInstallation;

  /// 0 = ลมยางธรรมดา, 1 = ลมยางไนโตรเจน.
  final int tireType;

  /// วันหมดอายุป้ายภาษี; null = ไม่ระบุ.
  final DateTime? taxDate;
  final String? brandName;
  final String? modelName;
  final String? comment;
  final int? employeeId;
  final String? employeeName;
  final Map<String, dynamic>? car;
  final Map<String, dynamic>? customer;

  /// Billing address picked by the server (customer's default type-1).
  final Map<String, dynamic>? address;

  /// Repairs created from this quotation via `/invoices/create-with-repair`.
  /// Non-empty means the quotation was sent to repair and is locked.
  final List<QuotationRepair> repairs;

  /// `cashPledges[].PledgeAmount` (list/detail include).
  final List<double> pledgeAmounts;

  /// Part lines with stock levels (list/detail include).
  final List<QuotationStockLine> stockLines;

  /// Web `isCanEdit`: no repair opened yet.
  bool get isApproved => repairs.isNotEmpty;

  /// Web `isCancelledRepair`: a repair of this quotation was cancelled (99).
  bool get isCancelledRepair => repairs.any((r) => r.isCancelled);

  /// Web `hasActiveReceipt`: a repair invoice has a PAID receipt.
  bool get hasPaidRepairReceipt => repairs.any(
        (r) => r.receiptStatuses.contains(ReceiptStatus.paid),
      );

  bool get hasPledge => pledgeAmounts.any((a) => a > 0);

  String get brandModel =>
      [brandName, modelName].whereType<String>().join(' ').trim();

  String get plate {
    final p = carPlate(car);
    if (p.isNotEmpty) {
      return p;
    }
    return repairs.map((r) => r.plate).firstWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  String get customerDisplayName =>
      customerName(customer ?? asMap(car?['customer']));

  String? get customerTel =>
      asString(customer?['CustomerTel'] ?? asMap(car?['customer'])?['CustomerTel']);

  String get gasText => gasInstallation == 1 ? 'ติดแก๊ส' : 'ไม่ติดแก๊ส';

  String get tireText => tireType == 1 ? 'ลมยางไนโตรเจน' : 'ลมยางธรรมดา';

  /// Web list filter (`QuotationTable.getQuotationStatusFilter`).
  QuotationStage get stage {
    if (isApproved) {
      return QuotationStage.sent;
    }
    if (!hasPledge) {
      return QuotationStage.pending;
    }
    return stockLines.any((l) => l.isShort)
        ? QuotationStage.waitingParts
        : QuotationStage.waitingRepair;
  }

  bool matches(String q) {
    final s = q.toLowerCase();
    bool has(String? v) => (v ?? '').toLowerCase().contains(s);
    return has(id) ||
        has(brandModel) ||
        has(comment) ||
        has(employeeName) ||
        has(plate) ||
        has(customerDisplayName) ||
        has(customerTel) ||
        repairs.any((r) => has('${r.id}'));
  }
}

/// List filters of the web quotation page.
enum QuotationStage {
  pending('รอส่งซ่อม'),
  waitingRepair('วางมัดจำ (รอส่งซ่อม)'),
  waitingParts('วางมัดจำ (รออะไหล่)'),
  sent('ส่งซ่อมแล้ว');

  const QuotationStage(this.label);

  final String label;
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

  /// Not enough stock to open a repair with this line.
  bool get isShort => part != null && quantity > part!.amount;

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
    this.copiedToQuotationId,
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
      copiedToQuotationId: asString(j['CopiedToQuotationID']),
      parts: asMapList(j['quotationParts']).map(QuotationPart.fromJson).toList(),
    );
  }

  final int id;
  final int? repairCategoryId;
  final String? repairCategory;
  final int? presetId;
  final String? presetName;

  /// Set by `POST /quotation/copy` on the source item.
  final String? copiedToQuotationId;
  final List<QuotationPart> parts;

  String get title => presetName ?? repairCategory ?? '-';

  double get total => parts.fold(0, (a, p) => a + p.total);
}

/// Totals of a quotation exactly as `pdfCreateQuotation` prints them
/// (pledges are listed but not deducted on the quotation PDF).
DocumentTotals quotationTotals(
  Quotation q,
  List<QuotationDetail> details, {
  Iterable<double> cashPledges = const [],
}) {
  final itemsSum =
      details.expand((d) => d.parts).fold<double>(0, (a, p) => a + p.total);
  return DocumentTotals.compute(
    itemsSum: itemsSum,
    isVat: q.isVat,
    vatType: q.vatType,
    cashPledges: cashPledges,
  );
}

/// `CashPledge` row (มัดจำ).
class CashPledge {
  const CashPledge({required this.id, required this.title, required this.amount});

  factory CashPledge.fromJson(Map<String, dynamic> j) => CashPledge(
        id: asInt(j['CashPledgeID']) ?? 0,
        title: asString(j['PledgeTitle']) ?? 'เงินมัดจำ',
        amount: asDouble(j['PledgeAmount']),
      );

  final int id;
  final String title;
  final double amount;
}

/// Row of `GET /quotation/logs/:id` (`RepairLog`).
class QuotationLog {
  const QuotationLog({
    required this.id,
    this.action,
    this.module,
    this.details,
    this.repairId,
    this.employeeName,
    this.createdAt,
  });

  factory QuotationLog.fromJson(Map<String, dynamic> j) => QuotationLog(
        id: asInt(j['LogID']) ?? 0,
        action: asString(j['Action']),
        module: asString(j['Module']),
        details: asString(j['Details']),
        repairId: asInt(j['RepairID']),
        employeeName: _employeeName(asMap(j['employee'])),
        createdAt: asDate(j['createdAt']),
      );

  final int id;

  /// สร้าง / แก้ไข / ลบ / คัดลอก ...
  final String? action;

  /// ใบเสนอราคา / ใบรับรถ / ใบแจ้งหนี้ / ใบเสร็จรับเงิน ...
  final String? module;
  final String? details;
  final int? repairId;

  /// null = ระบบอัตโนมัติ.
  final String? employeeName;
  final DateTime? createdAt;
}

/// Row of `GET /receipts/by-quotation-id/:id` (read-only here).
class QuotationReceipt {
  const QuotationReceipt({
    required this.billingId,
    this.statusId,
    this.isDeposit = false,
    this.invoiceId,
    this.amount = 0,
  });

  factory QuotationReceipt.fromJson(Map<String, dynamic> j) => QuotationReceipt(
        billingId: asString(j['BillingID']) ?? '',
        statusId: asInt(j['RecieptStatusID']),
        isDeposit: asInt(j['IsDeposit']) == 1,
        invoiceId: asString(j['InvoiceID'] ?? asMap(j['invoice'])?['InvoiceID']),
        amount: asDouble(j['Amount']),
      );

  final String billingId;
  final int? statusId;
  final bool isDeposit;
  final String? invoiceId;
  final double amount;

  bool get isPaid => statusId == ReceiptStatus.paid;

  /// `/pdf/create-deposit-receipt/:id` or `/pdf/create-receipt/:id`.
  String get pdfPath => isDeposit
      ? '/pdf/create-deposit-receipt/${Uri.encodeComponent(billingId)}'
      : '/pdf/create-receipt/${Uri.encodeComponent(billingId)}';
}

/// Row of `GET /imageCar/quotationID/:id`.
class QuotationImage {
  const QuotationImage({
    required this.id,
    required this.fileName,
    required this.quotationId,
    this.typeId,
    this.typeName,
  });

  factory QuotationImage.fromJson(Map<String, dynamic> j) {
    final type = asMap(j['imageCarType']);
    return QuotationImage(
      id: asInt(j['ImageCarID']) ?? 0,
      fileName: asString(j['FileName']) ?? '',
      quotationId: asString(j['QuotationID']) ?? '',
      typeId: asInt(j['ImageCarTypeID'] ?? type?['ImageCarTypeID']),
      typeName: asString(type?['ImageCarType']),
    );
  }

  final int id;
  final String fileName;
  final String quotationId;
  final int? typeId;
  final String? typeName;
}

/// Image types 1..8 are the mandatory angles checked before sending a car
/// to repair; 99 (อื่นๆ) may be uploaded any number of times.
const requiredImageTypeIds = [1, 2, 3, 4, 5, 6, 7, 8];
const otherImageTypeId = 99;

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

  String? get ownerTel => asString(asMap(raw['customer'])?['CustomerTel']);

  String? get color => asString(raw['Color']);

  String get brandModel => [
        asString(asMap(raw['brand'])?['Brand']),
        asString(asMap(raw['model'])?['Model']),
      ].whereType<String>().join(' ');

  bool matches(String q) {
    final s = q.toLowerCase();
    return plate.toLowerCase().contains(s) ||
        owner.toLowerCase().contains(s) ||
        (ownerTel ?? '').contains(s) ||
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
