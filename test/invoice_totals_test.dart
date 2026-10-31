import 'package:flutter_test/flutter_test.dart';
import 'package:honda_ntp/core/constants/statuses.dart';
import 'package:honda_ntp/features/invoices/invoice_models.dart';
import 'package:honda_ntp/features/quotations/totals.dart';

// Expected values follow honda-ntp-antigravity/backend/controllers/
// pdfCreateInvoice.controller.js (createInvoice + generateTotals):
//   partLine = NumOfUse * PricePerUnit - discount
//   discount = isDiscount === 1 ? Discount
//            : isDiscount === 2 ? Discount / 100 * NumOfUse * PricePerUnit
//            : 0
//   fees     = Σ ServiceFee ; feeDisc from feeDiscounts[0]
//   itemsSum = Σ partLine + fees - feeDisc
//   VAT include/exclude as the quotation; net = max(0, grand - Σ pledge)
// and pdfCreateDepositInvoice.controller.js for deposit invoices.

void main() {
  group('invoice part line', () {
    test('baht discount (isDiscount = 1) is subtracted as-is', () {
      expect(
        invoiceLineTotal(
          quantity: 2,
          pricePerUnit: 500,
          discount: 50,
          isDiscount: DiscountKind.baht,
        ),
        950,
      );
    });

    test('percent discount (isDiscount = 2) applies to price only', () {
      expect(
        invoiceLineDiscount(
          quantity: 2,
          pricePerUnit: 500,
          discount: 10,
          isDiscount: DiscountKind.percent,
        ),
        100,
      );
    });

    test('any other isDiscount value means no discount (PDF)', () {
      expect(
        invoiceLineTotal(
          quantity: 1,
          pricePerUnit: 100,
          discount: 50,
          isDiscount: 0,
        ),
        100,
      );
    });
  });

  test('fee discount: 1 = baht, otherwise percent of the fee total', () {
    expect(feeDiscountValue(totalFee: 350, amount: 50, isDiscount: 1), 50);
    expect(feeDiscountValue(totalFee: 350, amount: 10, isDiscount: 2), 35);
    expect(feeDiscountValue(totalFee: 350, amount: 0), 0);
  });

  Map<String, dynamic> invoiceJson({
    required int isVat,
    int vatType = 0,
    int status = 1,
  }) =>
      {
        'InvoiceID': 'INV-20261031-001',
        'RepairID': 12,
        'QuotationID': 'QT-20261030-002',
        'IsDeposit': 0,
        'isVat': isVat,
        'VatType': vatType,
        'Amount': null,
        'InvoiceStatusID': status,
        'InvoiceDate': '2026-10-31T03:00:00.000Z',
        'invoiceStatus': {'InvoiceStatusID': status, 'InvoiceStatus': 'x'},
        'feeDiscounts': [
          {'DiscountAmount': 10, 'isDiscount': 2},
        ],
        'receipts': [
          {'BillingID': 'RC-20261031-001', 'RecieptStatusID': 1},
        ],
        'repair': {
          'RepairID': 12,
          'QuotationID': 'QT-20261030-002',
          'car': {
            'CarTitle': 'กข',
            'CarNumber': '1234',
            'VIN': 'V1',
            'province': {'name_th': 'กรุงเทพมหานคร'},
            'brand': {'Brand': 'Honda'},
            'model': {'Model': 'City'},
            'customer': {
              'CustomerName': 'สมชาย',
              'CustomerSurname': 'ใจดี',
              'CustomerTel': '0812345678',
              'customerTitle': {'CustomerTitleID': 1, 'CustomerTitle': 'นาย'},
              'addresses': [
                {
                  'IsDefault': true,
                  'Line1': '1/2',
                  'subDistrict': {'name_th': 'ลาดยาว', 'Zipcode': '10900'},
                  'district': {'name_th': 'จตุจักร'},
                  'province': {'name_th': 'กรุงเทพมหานคร'},
                },
              ],
            },
          },
          'repairDetails': [
            {
              'RepairDetailID': 1,
              'repairCategory': {'RepairCategory': 'เครื่องยนต์'},
              'preset': {'Preset': 'เปลี่ยนน้ำมันเครื่อง'},
              'repairParts': [
                // 4 * 250 = 1000, fee 200
                {
                  'RepairPartID': 1,
                  'PartID': 5,
                  'NumOfUse': 4,
                  'PricePerUnit': 250,
                  'ServiceFee': 200,
                  'Discount': 0,
                  'isDiscount': 1,
                },
                // 300 - 10% = 270
                {
                  'RepairPartID': 2,
                  'PartID': 6,
                  'NumOfUse': 1,
                  'PricePerUnit': '300.00',
                  'ServiceFee': 0,
                  'Discount': 10,
                  'isDiscount': 2,
                },
              ],
            },
            {
              'RepairDetailID': 2,
              'repairCategory': {'RepairCategory': 'ช่วงล่าง'},
              'repairParts': [
                // 2000 - 100 = 1900, fee 150
                {
                  'RepairPartID': 3,
                  'PartID': 7,
                  'NumOfUse': 2,
                  'PricePerUnit': 1000,
                  'ServiceFee': 150,
                  'Discount': 100,
                  'isDiscount': 1,
                },
                // isDiscount 0 -> PDF ignores the discount: 100
                {
                  'RepairPartID': 4,
                  'PartID': 8,
                  'NumOfUse': 1,
                  'PricePerUnit': 100,
                  'ServiceFee': 0,
                  'Discount': 50,
                  'isDiscount': 0,
                },
              ],
            },
          ],
        },
      };

  // parts 1000 + 270 + 1900 + 100 = 3270 ; fees 350 - 10 % = 315
  const itemsSum = 3585.0;

  test('items sum = part lines + fees - fee discount', () {
    final inv = Invoice.fromJson(invoiceJson(isVat: 0));
    expect(inv.lines.length, 4);
    expect(inv.totalServiceFee, 350);
    expect(inv.feeDiscountAmount, 35);
    expect(inv.itemsSum, closeTo(itemsSum, 1e-9));
    expect(inv.feesByPreset, {'เปลี่ยนน้ำมันเครื่อง': 200, 'ช่วงล่าง': 150});
  });

  test('no VAT, pledge deducted into the net total', () {
    final t = Invoice.fromJson(invoiceJson(isVat: 0)).totals(cashPledges: [1000]);
    expect(t.vat, 0);
    expect(t.grandTotal, 3585);
    expect(t.cashPledge, 1000);
    expect(t.netTotal, 2585);
  });

  test('VatType 1 (exclude)', () {
    final t = Invoice.fromJson(invoiceJson(isVat: 1, vatType: 1))
        .totals(cashPledges: [1000]);
    expect(t.priceBeforeVat, 3585);
    expect(t.vat, 250.95);
    expect(t.grandTotal, 3835.95);
    expect(t.netTotal, 2835.95);
  });

  test('VatType 0 (include)', () {
    final t = Invoice.fromJson(invoiceJson(isVat: 1, vatType: 0)).totals();
    expect(t.vat, 234.53);
    expect(t.grandTotal, 3585);
    expect(t.priceBeforeVat, 3350.47);
    expect(t.netTotal, 3585);
  });

  test('net total never goes below zero', () {
    final t = Invoice.fromJson(invoiceJson(isVat: 0)).totals(cashPledges: [5000]);
    expect(t.netTotal, 0);
  });

  group('deposit invoice', () {
    Invoice deposit({required int isVat, required int vatType, required num amount}) =>
        Invoice.fromJson({
          'InvoiceID': 'INV-20261031-002',
          'RepairID': null,
          'QuotationID': 'QT-20261030-002',
          'IsDeposit': 1,
          'isVat': isVat,
          'VatType': vatType,
          'Amount': amount,
          'InvoiceStatusID': 2,
          'quotation': {
            'QuotationID': 'QT-20261030-002',
            'car': {'CarTitle': 'กข', 'CarNumber': '1234'},
            'customer': {'CustomerName': 'สมชาย', 'CustomerSurname': 'ใจดี'},
          },
        });

    test('exclude VAT: row is Amount * 100 / 107, grand = Amount', () {
      final inv = deposit(isVat: 1, vatType: 1, amount: 1070);
      final t = inv.totals(cashPledges: [1070]);
      expect(inv.itemsSum, closeTo(1000, 1e-9));
      expect(t.vat, 70);
      expect(t.grandTotal, 1070);
      // A deposit invoice never deducts the pledge.
      expect(t.netTotal, 1070);
    });

    test('include VAT: grand = Amount', () {
      final t = deposit(isVat: 1, vatType: 0, amount: 1000).totals();
      expect(t.vat, 65.42);
      expect(t.grandTotal, 1000);
      expect(t.priceBeforeVat, 934.58);
    });

    test('header falls back to the quotation car/customer', () {
      final inv = deposit(isVat: 0, vatType: 0, amount: 500);
      expect(inv.isDeposit, isTrue);
      expect(inv.repairId, isNull);
      expect(inv.plate, 'กข 1234');
      expect(inv.customerDisplayName, 'สมชาย ใจดี');
      expect(inv.pdfPath, '/pdf/create-deposit-invoice/INV-20261031-002');
    });
  });

  test('Invoice header fields', () {
    final inv = Invoice.fromJson(invoiceJson(isVat: 0, status: 99));
    expect(inv.statusId, InvoiceStatus.cancelled);
    expect(InvoiceStatus.info(inv.statusId).label, 'ยกเลิกใบแจ้งหนี้');
    expect(inv.quotationId, 'QT-20261030-002');
    expect(inv.plate, 'กข 1234 กรุงเทพมหานคร');
    expect(inv.customerDisplayName, 'นาย สมชาย ใจดี');
    expect(inv.brandModel, 'Honda City');
    expect(inv.addressDisplay, '1/2, ลาดยาว, จตุจักร, กรุงเทพมหานคร 10900');
    expect(inv.hasPaidReceipt, isTrue);
    expect(inv.receipts.single.pdfPath, '/pdf/create-receipt/RC-20261031-001');
    expect(inv.pdfPath, '/pdf/create-invoice/INV-20261031-001');
    expect(inv.matches('1234'), isTrue);
    expect(inv.matches('สมชาย'), isTrue);
    expect(inv.matches('zzz'), isFalse);
  });
}
