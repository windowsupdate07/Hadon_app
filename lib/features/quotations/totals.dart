// Money math for quotations and invoices.
//
// These formulas mirror the server-side PDF generators of the current
// backend (honda-ntp-antigravity/backend/controllers) exactly, so the totals
// shown in the app match the printed documents.
//
// Quotation (pdfCreateQuotation.controller.js createQuotation + generateTotals;
// same as the web's quotation page `subtotal`/`vat`/`grandTotal`):
//   itemsSum = Σ NumOfUse * PricePerUnit  +  Σ ServiceFee
//              (ServiceFee is a flat fee per part line, NOT per unit)
//
// Repair invoice (pdfCreateInvoice.controller.js createInvoice + generateTotals):
//   partLine  = NumOfUse * PricePerUnit - discount
//   discount  = isDiscount === 1 ? Discount                         (baht)
//             : isDiscount === 2 ? Discount / 100 * NumOfUse * PricePerUnit (%)
//             : 0
//               (the discount never applies to the service fee)
//   fees      = Σ ServiceFee
//   feeDisc   = feeDiscounts[0].isDiscount === 1 ? DiscountAmount
//             : DiscountAmount / 100 * fees   (no row -> 0, isDiscount 1)
//   itemsSum  = Σ partLine + fees - feeDisc
//
// Deposit invoice (pdfCreateDepositInvoice.controller.js):
//   itemsSum  = isVat && VatType === 1 ? Amount * 100 / 107 : Amount
//
// VAT, shared by every PDF's generateTotals():
//   no VAT (isVat falsy)   priceBeforeVat = itemsSum, vat = 0, grand = itemsSum
//   VatType 1 (exclude)    priceBeforeVat = itemsSum, vat = itemsSum * 0.07,
//                          grand = itemsSum + vat
//   otherwise (include)    vat = itemsSum * 7 / 107, grand = itemsSum,
//                          priceBeforeVat = itemsSum - vat
//   each of the three is rounded with parseFloat(x.toFixed(2)).
//
// Cash pledge (invoice PDFs only, not the quotation PDF):
//   pledge = Σ CashPledge.PledgeAmount of the quotation
//   net    = round2(max(0, round2(grand) - pledge))
//   A deposit invoice never deducts the pledge (web netTotal = grandTotal).
//   Confirming / paying / cancelling an invoice stores `net` in Invoices.Amount
//   (web invoices/details/[invoiceID].vue changeInvoiceStatus).

/// VAT rate hard-coded in every PDF generator.
const double documentVatRate = 0.07;

/// `VatType` column values (Quotation and Invoices).
class VatType {
  VatType._();

  /// Prices already include VAT (column default).
  static const include = 0;

  /// VAT is added on top of the prices.
  static const exclude = 1;

  static String label(int vatType) => vatType == exclude
      ? 'Exclude VAT (แยกจากราคาสินค้า)'
      : 'Include VAT (รวมในราคาสินค้า)';
}

/// `isDiscount` values of RepairPart / FeeDiscount.
class DiscountKind {
  DiscountKind._();

  static const baht = 1;
  static const percent = 2;
}

/// JavaScript `parseFloat(x.toFixed(2))`.
double roundMoney(num value) => double.parse(value.toStringAsFixed(2));

/// The PDFs test `Boolean(isVat) || isVat === 1`, i.e. any truthy value.
bool isVatOn(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final n = num.tryParse(value);
    return n != null ? n != 0 : value.toLowerCase() == 'true';
  }
  return false;
}

/// Quotation line total: `NumOfUse * PricePerUnit + ServiceFee`.
double quotationLineTotal({
  required num quantity,
  required num pricePerUnit,
  num? serviceFee,
}) {
  return quantity * pricePerUnit + (serviceFee ?? 0).toDouble();
}

/// Discount of an invoice part line (applies to `NumOfUse * PricePerUnit`
/// only). Unknown `isDiscount` values count as no discount, like the PDF.
double invoiceLineDiscount({
  required num quantity,
  required num pricePerUnit,
  num? discount,
  int? isDiscount,
}) {
  final d = (discount ?? 0).toDouble();
  if (isDiscount == DiscountKind.baht) {
    return d;
  }
  if (isDiscount == DiscountKind.percent) {
    return d / 100 * (quantity * pricePerUnit);
  }
  return 0;
}

/// Invoice part line total after discount, WITHOUT the service fee (fees
/// are summed into a separate "รวมค่าบริการ" row on the PDF).
double invoiceLineTotal({
  required num quantity,
  required num pricePerUnit,
  num? discount,
  int? isDiscount,
}) {
  return quantity * pricePerUnit -
      invoiceLineDiscount(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        discount: discount,
        isDiscount: isDiscount,
      );
}

/// Invoice-level discount on the summed service fees (`FeeDiscounts` row).
/// `isDiscount == 1` is baht, anything else is percent of [totalFee].
double feeDiscountValue({
  required double totalFee,
  num? amount,
  int? isDiscount,
}) {
  final a = (amount ?? 0).toDouble();
  return (isDiscount ?? DiscountKind.baht) == DiscountKind.baht
      ? a
      : a / 100 * totalFee;
}

/// Net price row of a deposit invoice.
double depositItemsSum({
  required double amount,
  required bool isVat,
  required int vatType,
}) {
  return isVat && vatType == VatType.exclude ? amount * 100 / 107 : amount;
}

/// Document level totals, as printed by `generateTotals()`.
class DocumentTotals {
  const DocumentTotals._({
    required this.itemsSum,
    required this.isVat,
    required this.vatType,
    required this.priceBeforeVat,
    required this.vat,
    required this.grandTotal,
    required this.cashPledge,
    required this.deductPledge,
  });

  /// [itemsSum] is the sum of the PDF's item rows (unrounded).
  /// [cashPledges] are the quotation's pledges; they are deducted only when
  /// [deductPledge] is true (repair invoices).
  factory DocumentTotals.compute({
    required double itemsSum,
    required bool isVat,
    int vatType = VatType.include,
    Iterable<double> cashPledges = const [],
    bool deductPledge = false,
  }) {
    var vat = 0.0;
    var priceBeforeVat = itemsSum;
    var grand = itemsSum;
    if (isVat) {
      if (vatType == VatType.exclude) {
        vat = itemsSum * documentVatRate;
        grand = itemsSum + vat;
      } else {
        vat = itemsSum * 7 / 107;
        priceBeforeVat = itemsSum - vat;
      }
    }
    return DocumentTotals._(
      itemsSum: itemsSum,
      isVat: isVat,
      vatType: vatType,
      priceBeforeVat: roundMoney(priceBeforeVat),
      vat: roundMoney(vat),
      grandTotal: roundMoney(grand),
      cashPledge: cashPledges.fold<double>(0, (a, b) => a + b),
      deductPledge: deductPledge,
    );
  }

  /// Sum of the item rows before VAT handling ("รวมเป็นเงิน" on the web).
  final double itemsSum;
  final bool isVat;
  final int vatType;

  /// ยอดรวม (Subtotal) on the PDF.
  final double priceBeforeVat;

  /// ภาษีมูลค่าเพิ่ม 7% (0 when [isVat] is false).
  final double vat;

  /// ยอดรวมสุทธิ / รวมจำนวนเงิน.
  final double grandTotal;

  /// Sum of cash pledges (มัดจำ).
  final double cashPledge;

  /// Whether [cashPledge] is deducted on this document (repair invoices).
  final bool deductPledge;

  bool get hasPledge => cashPledge > 0;

  /// ยอดที่ต้องชำระ: grand total minus the pledge when it is deducted,
  /// never negative. This is what the web saves into `Invoices.Amount`.
  double get netTotal => deductPledge
      ? roundMoney(grandTotal - cashPledge < 0 ? 0 : grandTotal - cashPledge)
      : grandTotal;

  /// Remaining after the pledge, for quotations where the PDF does not
  /// deduct it (shown as app-only info).
  double get balanceAfterPledge {
    final b = grandTotal - cashPledge;
    return roundMoney(b < 0 ? 0 : b);
  }
}
