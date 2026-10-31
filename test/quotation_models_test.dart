import 'package:flutter_test/flutter_test.dart';
import 'package:honda_ntp/features/quotations/quotation_models.dart';
import 'package:honda_ntp/features/quotations/totals.dart';

// Shapes follow honda-ntp-antigravity/backend/controllers/
// quotation.contoller.js includeOptions, receipts.controller.js
// findByQuotationID, imageCar.controller.js findByQuotationID and
// getQuotationLogs.

Map<String, dynamic> quotationJson({
  List<Map<String, dynamic>> repairs = const [],
  List<Map<String, dynamic>> pledges = const [],
  int partAmount = 10,
}) =>
    {
      'QuotationID': 'QT-20261031-001',
      'QuotationDate': '2026-10-31T02:00:00.000Z',
      'isVat': 1,
      'VatType': 1,
      'BrandID': 1,
      'ModelID': 2,
      'CarID': 3,
      'Mileage': 120000,
      'GasInstalation': 1,
      'TireType': 0,
      'TaxDate': '2027-03-15',
      'Comment': 'ทดสอบ',
      'EmployeeID': 1,
      'CustomerID': 4,
      'AddressID': 5,
      'brand': {'BrandID': 1, 'Brand': 'Honda'},
      'model': {'ModelID': 2, 'Model': 'Civic'},
      'employee': {'EmployeeID': 1, 'FirstName': 'สมหญิง', 'LastName': 'ขยัน'},
      'car': {
        'CarID': 3,
        'CarTitle': '1กข',
        'CarNumber': '999',
        'Color': 'ขาว',
        'province': {'name_th': 'เชียงใหม่'},
        'customer': {'CustomerName': 'ก', 'CustomerSurname': 'ข'},
      },
      'customer': {
        'CustomerName': 'สมชาย',
        'CustomerSurname': 'ใจดี',
        'CustomerTel': '0899999999',
        'customerTitle': {'CustomerTitle': 'นาย'},
      },
      'address': {
        'Line1': '10',
        'Line2': 'ซอย 1',
        'province': {'name_th': 'เชียงใหม่'},
        'district': {'name_th': 'เมือง'},
        'subDistrict': {'name_th': 'ศรีภูมิ', 'Zipcode': '50200'},
      },
      'repairs': repairs,
      'cashPledges': pledges,
      'quotationDetails': [
        {
          'QuotationDetailID': 1,
          'quotationParts': [
            {
              'QuotationPartID': 1,
              'NumOfUse': 4,
              'part': {'PartID': 1, 'PartAmount': partAmount},
            },
          ],
        },
      ],
    };

void main() {
  test('Quotation parses the new header fields', () {
    final q = Quotation.fromJson(quotationJson());
    expect(q.isVat, isTrue);
    expect(q.vatType, VatType.exclude);
    expect(q.carId, 3);
    expect(q.customerId, 4);
    expect(q.addressId, 5);
    expect(q.mileage, 120000);
    expect(q.gasText, 'ติดแก๊ส');
    expect(q.tireText, 'ลมยางธรรมดา');
    expect(q.taxDate, DateTime(2027, 3, 15));
    expect(q.plate, '1กข 999 เชียงใหม่');
    expect(q.customerDisplayName, 'นาย สมชาย ใจดี');
    expect(q.customerTel, '0899999999');
    expect(q.employeeName, 'สมหญิง ขยัน');
    expect(addressText(q.address), '10 ซอย 1, ศรีภูมิ, เมือง, เชียงใหม่ 50200');
    expect(q.matches('0899'), isTrue);
    expect(q.matches('999'), isTrue);
  });

  group('stage (web QuotationTable filter)', () {
    test('no pledge and no repair -> pending', () {
      expect(Quotation.fromJson(quotationJson()).stage, QuotationStage.pending);
    });

    test('pledge and enough stock -> waiting repair', () {
      final q = Quotation.fromJson(
        quotationJson(pledges: [
          {'CashPledgeID': 1, 'PledgeAmount': 500},
        ]),
      );
      expect(q.stage, QuotationStage.waitingRepair);
    });

    test('pledge and short stock -> waiting parts', () {
      final q = Quotation.fromJson(
        quotationJson(
          partAmount: 2,
          pledges: [
            {'CashPledgeID': 1, 'PledgeAmount': 500},
          ],
        ),
      );
      expect(q.stage, QuotationStage.waitingParts);
    });

    test('repair opened -> sent, locked', () {
      final q = Quotation.fromJson(
        quotationJson(repairs: [
          {
            'RepairID': 9,
            'WorkStatusID': 5,
            'invoices': [
              {
                'InvoiceID': 'INV-1',
                'receipts': [
                  {'BillingID': 'RC-1', 'RecieptStatusID': 2},
                ],
              },
            ],
          },
        ]),
      );
      expect(q.stage, QuotationStage.sent);
      expect(q.isApproved, isTrue);
      expect(q.isCancelledRepair, isFalse);
      expect(q.hasPaidRepairReceipt, isFalse);
      expect(q.repairs.single.invoiceIds, ['INV-1']);
    });
  });

  test('paid repair receipt and cancelled repair are detected', () {
    final q = Quotation.fromJson(
      quotationJson(repairs: [
        {
          'RepairID': 9,
          'WorkStatusID': 99,
          'invoices': [
            {
              'InvoiceID': 'INV-1',
              'receipts': [
                {'BillingID': 'RC-1', 'RecieptStatusID': 1},
              ],
            },
          ],
        },
      ]),
    );
    expect(q.hasPaidRepairReceipt, isTrue);
    expect(q.isCancelledRepair, isTrue);
  });

  test('QuotationReceipt (GET /receipts/by-quotation-id/:id .data[])', () {
    final r = QuotationReceipt.fromJson({
      'BillingID': 'RC-20261031-002',
      'RecieptStatusID': 1,
      'IsDeposit': 1,
      'InvoiceID': 'INV-20261031-002',
      'Amount': '1070.00',
      'invoice': {'InvoiceID': 'INV-20261031-002', 'QuotationID': 'QT-1'},
    });
    expect(r.isPaid, isTrue);
    expect(r.isDeposit, isTrue);
    expect(r.amount, 1070);
    expect(r.pdfPath, '/pdf/create-deposit-receipt/RC-20261031-002');
  });

  test('QuotationImage (GET /imageCar/quotationID/:id)', () {
    final i = QuotationImage.fromJson({
      'ImageCarID': 4,
      'FileName': '20261031-101010-ABC.jpg',
      'ImageCarTypeID': 2,
      'QuotationID': 'QT-20261031-001',
      'imageCarType': {'ImageCarTypeID': 2, 'ImageCarType': 'ด้านหลัง'},
    });
    expect(i.id, 4);
    expect(i.typeId, 2);
    expect(i.typeName, 'ด้านหลัง');
  });

  test('QuotationLog (GET /quotation/logs/:id .data[])', () {
    final l = QuotationLog.fromJson({
      'LogID': 3,
      'RepairID': null,
      'Action': 'สร้าง',
      'Module': 'ใบเสนอราคา',
      'Details': 'สร้างใบเสนอราคาเลขที่ QT-20261031-001',
      'createdAt': '2026-10-31T02:00:00.000Z',
      'employee': {'FirstName': 'สมหญิง', 'LastName': 'ขยัน'},
    });
    expect(l.action, 'สร้าง');
    expect(l.employeeName, 'สมหญิง ขยัน');
    expect(l.createdAt, isNotNull);
  });
}
