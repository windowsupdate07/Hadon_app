// Money math for quotations and invoices.
//
// These formulas mirror the server-side PDF generators exactly, so the totals
// shown in the app match the printed documents:
//
// Quotation (ntp-api/controllers/pdfCreateQuotation.controller.js):
//   line       = NumOfUse * PricePerUnit + ServiceFee
//                (ServiceFee is a flat fee per line, NOT per unit)
//   subtotal   = sum(line)
//   vat        = isVat === 1 ? subtotal * 0.07 : 0
//   grandTotal = subtotal + vat
//
// Invoice (ntp-api/controllers/pdfCreateInvoice.controller.js,
// calculateSingleRow / calSubtotal / generateTotals):
//   base       = NumOfUse * PricePerUnit + ServiceFee
//   discount   = isDiscount === 1 ? Discount               (baht)
//                                 : Discount / 100 * base  (percent)
//   line       = base - discount
//   subtotal   = sum(line)
//   vat        = isVat === 1 ? subtotal * 0.07 : 0
//   grandTotal = subtotal + vat
//
// Neither PDF has a VAT include/exclude type nor deducts cash pledges. The
// app additionally shows the cash pledge (มัดจำ) of a quotation and the
// balance after deducting it; that figure is app-only and is computed
// separately from [DocumentTotals.grandTotal] so the PDF figure is untouched.
//
// Values are kept as doubles (like the JS code) and only rounded for display
// with 2 decimals (the PDFs use `toFixed(2)`).

/// VAT rate used by both PDFs (hard-coded 0.07 on the server).
const double documentVatRate = 0.07;

/// Quotation line total: `NumOfUse * PricePerUnit + ServiceFee`.
double quotationLineTotal({
  required num quantity,
  required num pricePerUnit,
  num? serviceFee,
}) {
  return quantity * pricePerUnit + (serviceFee ?? 0).toDouble();
}

/// Line amount before discount on an invoice (same as a quotation line).
double invoiceLineBase({
  required num quantity,
  required num pricePerUnit,
  num? serviceFee,
}) {
  return quotationLineTotal(
    quantity: quantity,
    pricePerUnit: pricePerUnit,
    serviceFee: serviceFee,
  );
}

/// Discount of an invoice line. `isDiscount == 1` means [discount] is an
/// amount in baht; any other value means it is a percentage of the line base.
double invoiceLineDiscount({
  required num quantity,
  required num pricePerUnit,
  num? serviceFee,
  num? discount,
  int? isDiscount,
}) {
  final d = (discount ?? 0).toDouble();
  if (isDiscount == 1) {
    return d;
  }
  final base = invoiceLineBase(
    quantity: quantity,
    pricePerUnit: pricePerUnit,
    serviceFee: serviceFee,
  );
  return d / 100 * base;
}

/// Invoice line total after discount.
double invoiceLineTotal({
  required num quantity,
  required num pricePerUnit,
  num? serviceFee,
  num? discount,
  int? isDiscount,
}) {
  final base = invoiceLineBase(
    quantity: quantity,
    pricePerUnit: pricePerUnit,
    serviceFee: serviceFee,
  );
  return base -
      invoiceLineDiscount(
        quantity: quantity,
        pricePerUnit: pricePerUnit,
        serviceFee: serviceFee,
        discount: discount,
        isDiscount: isDiscount,
      );
}

/// Document level totals.
class DocumentTotals {
  const DocumentTotals({
    required this.subtotal,
    required this.vat,
    required this.isVat,
    this.cashPledge = 0,
  });

  /// Builds totals from already computed line totals.
  factory DocumentTotals.fromLines(
    Iterable<double> lineTotals, {
    required bool isVat,
    Iterable<double> cashPledges = const [],
  }) {
    final subtotal = lineTotals.fold<double>(0, (a, b) => a + b);
    final vat = isVat ? subtotal * documentVatRate : 0.0;
    final pledge = cashPledges.fold<double>(0, (a, b) => a + b);
    return DocumentTotals(
      subtotal: subtotal,
      vat: vat,
      isVat: isVat,
      cashPledge: pledge,
    );
  }

  /// ยอดรวม (Subtotal).
  final double subtotal;

  /// ภาษีมูลค่าเพิ่ม 7% — 0 when [isVat] is false.
  final bool isVat;
  final double vat;

  /// Sum of cash pledges (app-only, not printed on the PDF).
  final double cashPledge;

  /// ยอดรวมสุทธิ (Grand Total) — exactly as printed on the PDF.
  double get grandTotal => subtotal + vat;

  /// Remaining amount after deducting the cash pledge (app-only).
  double get balance => grandTotal - cashPledge;
}

/// The server stores `isVat` as INTEGER and the PDFs test `isVat === 1`.
bool isVatOn(dynamic value) => value == 1 || value == true || value == '1';
