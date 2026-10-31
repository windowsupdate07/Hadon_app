import '../../core/utils/json.dart';
import '../parts/part_model.dart';
import '../quotations/quotation_models.dart'
    show QuotationReceipt, addressText, carPlate, customerName;
import '../quotations/totals.dart';

// JSON shape of `GET /invoices`, `GET /invoices/:id` and
// `GET /invoices/by-quotation-id/:id` (.data[]), see
// honda-ntp-antigravity/backend/controllers/invoices.controller.js
// includeOptions:
//   invoice.{InvoiceID, RepairID, QuotationID, IsDeposit, isVat, VatType,
//            InvoiceDate, InvoiceStatusID, EmployeeID, Amount}
//   invoice.invoiceStatus
//   invoice.employee
//   invoice.repair.{QuotationID, workStatus}
//   invoice.repair.car.{customer.{customerTitle, addresses[]}, brand, model, province}
//   invoice.repair.repairDetails[].{repairCategory, preset,
//       repairParts[].{part.unit, partStatus}}
//   invoice.quotation.{Mileage, GasInstalation, TireType, TaxDate,
//       car.{customer.{customerTitle, addresses[]}, brand, model, province},
//       customer.customerTitle, address.{province, district, subDistrict}}
//   invoice.receipts[].{BillingID, RecieptStatusID}
//   invoice.feeDiscounts[].{DiscountAmount, isDiscount, DiscountNote}

/// `RepairPart` row: a billed part line of a repair invoice.
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
      isDiscount: asInt(j['isDiscount']) ?? DiscountKind.baht,
      part: part == null ? null : Part.fromJson(part),
      partStatusId: asInt(j['PartStatusID']),
    );
  }

  final int id;
  final int partId;
  final int quantity;
  final double pricePerUnit;

  /// Summed into the "รวมค่าบริการ" row, not part of [total].
  final double serviceFee;
  final double discount;

  /// [DiscountKind.baht] (1) or [DiscountKind.percent] (2).
  final int isDiscount;
  final Part? part;
  final int? partStatusId;

  String get name => part?.displayName ?? 'อะไหล่ #$partId';

  /// "-" / "50.00 ฿" / "10 %" like the PDF's discount column.
  String get discountLabel => discount == 0
      ? '-'
      : '${discount.toStringAsFixed(2)}${isDiscount == DiscountKind.baht ? ' ฿' : ' %'}';

  double get discountAmount => invoiceLineDiscount(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        discount: discount,
        isDiscount: isDiscount,
      );

  /// `NumOfUse * PricePerUnit - discount` (service fee excluded).
  double get total => invoiceLineTotal(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
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

  /// Name used for the per-preset service fee rows on the PDF.
  String get feeName => presetName ?? repairCategory ?? '-';

  double get serviceFee => lines.fold(0, (a, l) => a + l.serviceFee);

  double get total => lines.fold(0, (a, l) => a + l.total);
}

/// Invoice-level discount on the service fee (`feeDiscounts[0]`).
class FeeDiscount {
  const FeeDiscount({this.amount = 0, this.isDiscount = DiscountKind.baht, this.note});

  factory FeeDiscount.fromJson(Map<String, dynamic>? j) => j == null
      ? const FeeDiscount()
      : FeeDiscount(
          amount: asDouble(j['DiscountAmount']),
          isDiscount: asInt(j['isDiscount']) ?? DiscountKind.baht,
          note: asString(j['DiscountNote']),
        );

  final double amount;
  final int isDiscount;
  final String? note;

  String get label => amount == 0
      ? '-'
      : '${amount.toStringAsFixed(2)}${isDiscount == DiscountKind.baht ? ' ฿' : ' %'}';
}

class Invoice {
  const Invoice({
    required this.id,
    this.date,
    this.statusId,
    this.statusName,
    this.isVat = false,
    this.vatType = VatType.include,
    this.isDeposit = false,
    this.amount,
    this.repairId,
    this.quotationId,
    this.employeeName,
    this.car,
    this.customer,
    this.address,
    this.groups = const [],
    this.feeDiscount = const FeeDiscount(),
    this.receipts = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final repair = asMap(j['repair']);
    final quotation = asMap(j['quotation']);
    // Web: dataOrigin = invoice.repair || invoice.quotation.
    final car = asMap(repair?['car']) ?? asMap(quotation?['car']);
    final emp = asMap(j['employee']);
    final invoiceId = asString(j['InvoiceID']) ?? '';
    final isDeposit = asInt(j['IsDeposit']) == 1;
    return Invoice(
      id: invoiceId,
      date: asDate(j['InvoiceDate']),
      statusId: asInt(j['InvoiceStatusID']),
      statusName: asString(asMap(j['invoiceStatus'])?['InvoiceStatus']),
      isVat: isVatOn(j['isVat']),
      vatType: asInt(j['VatType']) ?? VatType.include,
      isDeposit: isDeposit,
      amount: j['Amount'] == null ? null : asDouble(j['Amount']),
      repairId: asInt(j['RepairID'] ?? repair?['RepairID']),
      quotationId: asString(
        j['QuotationID'] ?? repair?['QuotationID'] ?? quotation?['QuotationID'],
      ),
      employeeName: emp == null
          ? null
          : '${emp['FirstName'] ?? ''} ${emp['LastName'] ?? ''}'.trim(),
      car: car,
      customer: asMap(car?['customer']) ?? asMap(quotation?['customer']),
      address: asMap(quotation?['address']),
      groups: asMapList(repair?['repairDetails'])
          .map(InvoiceGroup.fromJson)
          .toList(),
      feeDiscount: FeeDiscount.fromJson(
        asMapList(j['feeDiscounts']).isEmpty
            ? null
            : asMapList(j['feeDiscounts']).first,
      ),
      receipts: asMapList(j['receipts'])
          .map(
            (r) => QuotationReceipt.fromJson({
              ...r,
              'InvoiceID': invoiceId,
              // Receipts inherit IsDeposit from their invoice.
              'IsDeposit': isDeposit ? 1 : 0,
            }),
          )
          .toList(),
    );
  }

  final String id;
  final DateTime? date;
  final int? statusId;
  final String? statusName;
  final bool isVat;
  final int vatType;

  /// Deposit (มัดจำ) invoice created by `POST /cash-pledge`; has no repair.
  final bool isDeposit;

  /// Saved net total (set when confirmed / paid / cancelled).
  final double? amount;
  final int? repairId;
  final String? quotationId;
  final String? employeeName;
  final Map<String, dynamic>? car;
  final Map<String, dynamic>? customer;

  /// Billing address chosen on the quotation.
  final Map<String, dynamic>? address;
  final List<InvoiceGroup> groups;
  final FeeDiscount feeDiscount;
  final List<QuotationReceipt> receipts;

  List<InvoiceLine> get lines => groups.expand((g) => g.lines).toList();

  /// Σ ServiceFee of all lines ("รวมค่าบริการ").
  double get totalServiceFee => lines.fold(0, (a, l) => a + l.serviceFee);

  double get feeDiscountAmount => feeDiscountValue(
        totalFee: totalServiceFee,
        amount: feeDiscount.amount,
        isDiscount: feeDiscount.isDiscount,
      );

  /// Fee groups printed as "(ค่าบริการ) preset-name" rows (only fees > 0).
  Map<String, double> get feesByPreset {
    final out = <String, double>{};
    for (final g in groups) {
      out[g.feeName] = (out[g.feeName] ?? 0) + g.serviceFee;
    }
    out.removeWhere((_, v) => v <= 0);
    return out;
  }

  /// Sum of the PDF item rows.
  double get itemsSum => isDeposit
      ? depositItemsSum(amount: amount ?? 0, isVat: isVat, vatType: vatType)
      : lines.fold<double>(0, (a, l) => a + l.total) +
          totalServiceFee -
          feeDiscountAmount;

  /// Totals exactly as `pdfCreateInvoice` / `pdfCreateDepositInvoice`
  /// print them. Pass the quotation's cash pledges (`GET /cash-pledge/
  /// by-quotation-id/:id`) for repair invoices.
  DocumentTotals totals({Iterable<double> cashPledges = const []}) =>
      DocumentTotals.compute(
        itemsSum: itemsSum,
        isVat: isVat,
        vatType: vatType,
        cashPledges: isDeposit ? const [] : cashPledges,
        deductPledge: !isDeposit,
      );

  bool get hasPaidReceipt => receipts.any((r) => r.isPaid);

  String get plate => carPlate(car);

  String get customerDisplayName => customerName(customer);

  String? get customerTel => asString(customer?['CustomerTel']);

  String? get customerTaxId => asString(customer?['IDNumber']);

  /// Web `customerAddress()`: quotation address, else customer default.
  String get addressDisplay {
    if (address != null) {
      return addressText(address);
    }
    final list = asMapList(customer?['addresses']);
    final def = list.where((a) => asBool(a['IsDefault']));
    return def.isEmpty ? '' : addressText(def.first);
  }

  String get brandModel => [
        asString(asMap(car?['brand'])?['Brand']),
        asString(asMap(car?['model'])?['Model']),
      ].whereType<String>().join(' ');

  String get typeLabel => isDeposit ? 'ใบแจ้งหนี้ (เงินมัดจำ)' : 'ใบแจ้งหนี้';

  /// `/pdf/create-deposit-invoice/:id` or `/pdf/create-invoice/:id`.
  String get pdfPath => isDeposit
      ? '/pdf/create-deposit-invoice/${Uri.encodeComponent(id)}'
      : '/pdf/create-invoice/${Uri.encodeComponent(id)}';

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
