import '../../core/utils/json.dart';
import '../parts/part_model.dart';
import '../quotations/quotation_models.dart' show carPlate, customerName;
import '../quotations/totals.dart';

// JSON shape of `GET /invoices` and `GET /invoices/:id`
// (ntp-api/controllers/invoices.controller.js includeOptions):
//   invoice.invoiceStatus
//   invoice.employee
//   invoice.repair.workStatus
//   invoice.repair.car.{customer.{customerTitle, addresses[]}, brand, model, province}
//   invoice.repair.repairDetails[].{repairCategory, preset,
//       repairParts[].{part.unit, partStatus}}

/// `RepairPart` row: a billed line of the invoice.
class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.partId,
    required this.quantity,
    required this.pricePerUnit,
    required this.serviceFee,
    required this.discount,
    required this.isDiscount,
    this.part,
    this.partStatusId,
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> j) {
    final part = asMap(j['part']);
    return InvoiceLine(
      id: asInt(j['RepairPartID']) ?? 0,
      partId: asInt(j['PartID']) ?? 0,
      quantity: asInt(j['NumOfUse']) ?? 0,
      pricePerUnit: asDouble(j['PricePerUnit']),
      serviceFee: asDouble(j['ServiceFee']),
      discount: asDouble(j['Discount']),
      // Column default is 1 (baht).
      isDiscount: asInt(j['isDiscount']) ?? 1,
      part: part == null ? null : Part.fromJson(part),
      partStatusId: asInt(j['PartStatusID']),
    );
  }

  final int id;
  final int partId;
  final int quantity;
  final double pricePerUnit;
  final double serviceFee;
  final double discount;

  /// 1 = [discount] is baht, otherwise percent.
  final int isDiscount;
  final Part? part;
  final int? partStatusId;

  String get name => part?.displayName ?? 'อะไหล่ #$partId';

  double get discountAmount => invoiceLineDiscount(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        serviceFee: serviceFee,
        discount: discount,
        isDiscount: isDiscount,
      );

  double get total => invoiceLineTotal(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        serviceFee: serviceFee,
        discount: discount,
        isDiscount: isDiscount,
      );
}

/// `RepairDetail` with its parts.
class InvoiceGroup {
  const InvoiceGroup({
    required this.id,
    this.repairCategory,
    this.presetName,
    this.lines = const [],
  });

  factory InvoiceGroup.fromJson(Map<String, dynamic> j) => InvoiceGroup(
        id: asInt(j['RepairDetailID']) ?? 0,
        repairCategory: asString(asMap(j['repairCategory'])?['RepairCategory']),
        presetName: asString(asMap(j['preset'])?['Preset']),
        lines: asMapList(j['repairParts']).map(InvoiceLine.fromJson).toList(),
      );

  final int id;
  final String? repairCategory;
  final String? presetName;
  final List<InvoiceLine> lines;

  double get total => lines.fold(0, (a, l) => a + l.total);
}

class Invoice {
  const Invoice({
    required this.id,
    this.date,
    this.statusId,
    this.isVat = false,
    this.repairId,
    this.quotationId,
    this.employeeName,
    this.car,
    this.customer,
    this.groups = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final repair = asMap(j['repair']);
    final car = asMap(repair?['car']);
    final emp = asMap(j['employee']);
    return Invoice(
      id: asString(j['InvoiceID']) ?? '',
      date: asDate(j['InvoiceDate']),
      statusId: asInt(j['InvoiceStatusID']),
      isVat: isVatOn(asInt(j['isVat'])),
      repairId: asInt(j['RepairID'] ?? repair?['RepairID']),
      quotationId: asString(repair?['QuotationID']),
      employeeName: emp == null
          ? null
          : '${emp['FirstName'] ?? ''} ${emp['LastName'] ?? ''}'.trim(),
      car: car,
      customer: asMap(car?['customer']),
      groups: asMapList(repair?['repairDetails'])
          .map(InvoiceGroup.fromJson)
          .toList(),
    );
  }

  final String id;
  final DateTime? date;
  final int? statusId;
  final bool isVat;
  final int? repairId;
  final String? quotationId;
  final String? employeeName;
  final Map<String, dynamic>? car;
  final Map<String, dynamic>? customer;
  final List<InvoiceGroup> groups;

  List<InvoiceLine> get lines => groups.expand((g) => g.lines).toList();

  /// Totals exactly as `pdfCreateInvoice.controller.js` prints them.
  DocumentTotals get totals => DocumentTotals.fromLines(
        lines.map((l) => l.total),
        isVat: isVat,
      );

  String get plate => carPlate(car);

  String get customerDisplayName => customerName(customer);

  String? get customerTel => asString(customer?['CustomerTel']);

  String get brandModel => [
        asString(asMap(car?['brand'])?['Brand']),
        asString(asMap(car?['model'])?['Model']),
      ].whereType<String>().join(' ');

  /// The invoice PDF crashes on the server when the customer has no
  /// default (IsDefault) address of AddressTypeID 1.
  bool get hasPdfAddress => asMapList(customer?['addresses']).any(
        (a) => asInt(a['AddressTypeID']) == 1 && asBool(a['IsDefault']),
      );

  bool matches(String q) {
    final s = q.toLowerCase();
    bool has(String? v) => (v ?? '').toLowerCase().contains(s);
    return has(id) ||
        has(repairId?.toString()) ||
        has(quotationId) ||
        has(customerDisplayName) ||
        has(customerTel) ||
        has(plate) ||
        has(brandModel);
  }
}
