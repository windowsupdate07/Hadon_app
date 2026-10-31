import 'package:flutter_test/flutter_test.dart';
import 'package:honda_ntp/features/invoices/invoice_models.dart';
import 'package:honda_ntp/features/quotations/totals.dart';

// Expected values follow ntp-api/controllers/pdfCreateInvoice.controller.js:
//   base     = NumOfUse * PricePerUnit + ServiceFee
//   discount = isDiscount === 1 ? Discount : Discount / 100 * base
//   line     = base - discount
//   vat      = isVat === 1 ? subtotal * 0.07 : 0

void main() {
  group('invoice line', () {
    test('baht discount (isDiscount = 1) is subtracted as-is', () {
      expect(
        invoiceLineTotal(
          quantity: 2,
          pricePerUnit: 500,
          serviceFee: 100,
          discount: 50,
          isDiscount: 1,
        ),
        1050,
      );
    });

    test('percent discount (isDiscount != 1) applies to price + fee', () {
      expect(
        invoiceLineDiscount(
          quantity: 2,
          pricePerUnit: 500,
          serviceFee: 100,
          discount: 10,
          isDiscount: 0,
        ),
        110,
      );
      expect(
        invoiceLineTotal(
          quantity: 2,
          pricePerUnit: 500,
          serviceFee: 100,
          discount: 10,
          isDiscount: 0,
        ),
        990,
      );
    });

    test('no discount equals the quotation line formula', () {
      expect(
        invoiceLineTotal(quantity: 3, pricePerUnit: 10, serviceFee: 5),
        quotationLineTotal(quantity: 3, pricePerUnit: 10, serviceFee: 5),
      );
    });
  });

  Map<String, dynamic> invoiceJson({required int isVat}) => {
        'InvoiceID': 'INV-20261031-001',
        'RepairID': 12,
        'isVat': isVat,
        'InvoiceStatusID': 1,
        'InvoiceDate': '2026-10-31T03:00:00.000Z',
        'repair': {
          'RepairID': 12,
          'QuotationID': 'QT-20261030-002',
          'car': {
            'CarTitle': 'กข',
            'CarNumber': '1234',
            'province': {'name_th': 'กรุงเทพมหานคร'},
            'brand': {'Brand': 'Honda'},
            'model': {'Model': 'City'},
            'customer': {
              'CustomerName': 'สมชาย',
              'CustomerSurname': 'ใจดี',
              'customerTitle': {'CustomerTitleID': 1, 'CustomerTitle': 'นาย'},
              'addresses': [
                {'AddressTypeID': 1, 'IsDefault': true},
              ],
            },
          },
          'repairDetails': [
            {
              'RepairDetailID': 1,
              'repairCategory': {'RepairCategory': 'เครื่องยนต์'},
              'preset': {'Preset': 'เปลี่ยนน้ำมันเครื่อง'},
              'repairParts': [
                {
                  'RepairPartID': 1,
                  'PartID': 5,
                  'NumOfUse': 4,
                  'PricePerUnit': 250,
                  'ServiceFee': 200,
                  'Discount': 0,
                  'isDiscount': 1,
                },
                {
                  'RepairPartID': 2,
                  'PartID': 6,
                  'NumOfUse': 1,
                  'PricePerUnit': '300.00',
                  'ServiceFee': 0,
                  'Discount': 10,
                  'isDiscount': 0,
                },
              ],
            },
            {
              'RepairDetailID': 2,
              'repairParts': [
                {
                  'RepairPartID': 3,
                  'PartID': 7,
                  'NumOfUse': 2,
                  'PricePerUnit': 1000,
                  'ServiceFee': 150,
                  'Discount': 100,
                  'isDiscount': 1,
                },
              ],
            },
          ],
        },
      };

  test('Invoice totals without VAT', () {
    final inv = Invoice.fromJson(invoiceJson(isVat: 0));
    // 1200 + (300 - 30) + (2150 - 100) = 3520
    expect(inv.lines.length, 3);
    expect(inv.totals.subtotal, closeTo(3520, 1e-9));
    expect(inv.totals.vat, 0);
    expect(inv.totals.grandTotal, closeTo(3520, 1e-9));
  });

  test('Invoice totals with VAT', () {
    final inv = Invoice.fromJson(invoiceJson(isVat: 1));
    expect(inv.totals.vat, closeTo(246.4, 1e-9));
    expect(inv.totals.grandTotal, closeTo(3766.4, 1e-9));
  });

  test('Invoice header fields', () {
    final inv = Invoice.fromJson(invoiceJson(isVat: 0));
    expect(inv.quotationId, 'QT-20261030-002');
    expect(inv.plate, 'กข 1234 กรุงเทพมหานคร');
    expect(inv.customerDisplayName, 'นาย สมชาย ใจดี');
    expect(inv.brandModel, 'Honda City');
    expect(inv.hasPdfAddress, isTrue);
    expect(inv.matches('1234'), isTrue);
    expect(inv.matches('สมชาย'), isTrue);
    expect(inv.matches('zzz'), isFalse);
  });
}
