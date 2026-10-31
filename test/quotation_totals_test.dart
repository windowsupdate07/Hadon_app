import 'package:flutter_test/flutter_test.dart';
import 'package:honda_ntp/features/quotations/quotation_models.dart';
import 'package:honda_ntp/features/quotations/totals.dart';
import 'package:honda_ntp/features/quotations/widgets/cash_pledge_dialog.dart';

// Expected values follow honda-ntp-antigravity/backend/controllers/
// pdfCreateQuotation.controller.js (createQuotation + generateTotals):
//   itemsSum = Σ NumOfUse * PricePerUnit + Σ ServiceFee
//   no VAT : grand = itemsSum
//   exclude: vat = itemsSum * 0.07, grand = itemsSum + vat
//   include: vat = itemsSum * 7 / 107, grand = itemsSum,
//            priceBeforeVat = itemsSum - vat
//   each rounded with parseFloat(x.toFixed(2)).

void main() {
  group('quotationLineTotal', () {
    test('service fee is added once per line, not per unit', () {
      expect(
        quotationLineTotal(quantity: 3, pricePerUnit: 100, serviceFee: 50),
        350,
      );
    });

    test('null service fee counts as zero', () {
      expect(quotationLineTotal(quantity: 2, pricePerUnit: 99.5), 199);
    });
  });

  group('roundMoney mirrors JS toFixed(2)', () {
    test('binary representation decides, like JS', () {
      expect(roundMoney(0.125), 0.13);
      expect(roundMoney(2.675), 2.67);
      expect(roundMoney(1.005), 1.0);
      expect(roundMoney(248.5175), 248.52);
    });
  });

  group('DocumentTotals (quotation)', () {
    // 2 * 1500 + 200 = 3200 ; 1 * 350.25 + 0 = 350.25
    final itemsSum = [
      quotationLineTotal(quantity: 2, pricePerUnit: 1500, serviceFee: 200),
      quotationLineTotal(quantity: 1, pricePerUnit: 350.25, serviceFee: 0),
    ].fold<double>(0, (a, b) => a + b);

    test('without VAT the grand total equals the items sum', () {
      final t = DocumentTotals.compute(itemsSum: itemsSum, isVat: false);
      expect(t.priceBeforeVat, 3550.25);
      expect(t.vat, 0);
      expect(t.grandTotal, 3550.25);
    });

    test('VatType 1 (exclude) adds 7% on top', () {
      final t = DocumentTotals.compute(
        itemsSum: itemsSum,
        isVat: true,
        vatType: VatType.exclude,
      );
      expect(t.priceBeforeVat, 3550.25);
      expect(t.vat, 248.52);
      expect(t.grandTotal, 3798.77);
    });

    test('VatType 0 (include) extracts 7/107 from the total', () {
      final t = DocumentTotals.compute(
        itemsSum: itemsSum,
        isVat: true,
        vatType: VatType.include,
      );
      expect(t.vat, 232.26);
      expect(t.grandTotal, 3550.25);
      expect(t.priceBeforeVat, 3317.99);
    });

    test('quotation PDF does not deduct the pledge', () {
      final t = DocumentTotals.compute(
        itemsSum: itemsSum,
        isVat: false,
        cashPledges: [1000, 500],
      );
      expect(t.cashPledge, 1500);
      expect(t.netTotal, 3550.25);
      expect(t.balanceAfterPledge, 2050.25);
    });

    test('empty quotation is zero', () {
      final t = DocumentTotals.compute(itemsSum: 0, isVat: true);
      expect(t.priceBeforeVat, 0);
      expect(t.vat, 0);
      expect(t.grandTotal, 0);
    });
  });

  test('isVatOn mirrors Boolean(isVat)', () {
    expect(isVatOn(1), isTrue);
    expect(isVatOn(2), isTrue);
    expect(isVatOn(true), isTrue);
    expect(isVatOn('1'), isTrue);
    expect(isVatOn(0), isFalse);
    expect(isVatOn(null), isFalse);
    expect(isVatOn(false), isFalse);
  });

  group('pledgeForPercent (web CashPledgeDialog.calculatePledge)', () {
    test('rounds up to whole baht', () {
      expect(pledgeForPercent(3798.77, 20), 760); // 759.754
      expect(pledgeForPercent(1000, 40), 400);
    });

    test('never exceeds the grand total', () {
      expect(pledgeForPercent(3798.77, 100), 3798); // ceil 3799 > total
    });
  });

  test('QuotationDetail parses API JSON and sums its parts', () {
    final detail = QuotationDetail.fromJson({
      'QuotationDetailID': 7,
      'RepairCategoryID': 2,
      'PresetID': 3,
      'CopiedToQuotationID': 'QT-20261031-004',
      'repairCategory': {'RepairCategory': 'ช่วงล่าง'},
      'preset': {'Preset': 'เปลี่ยนโช้ค'},
      'quotationParts': [
        {
          'QuotationPartID': 1,
          'PartID': 10,
          'NumOfUse': 2,
          'PricePerUnit': '1200.50',
          'ServiceFee': 300,
          'part': {
            'PartID': 10,
            'PartName_th': 'โช้คอัพหน้า',
            'PartAmount': 1,
            'unit': {'Unit': 'ชิ้น'},
          },
        },
        {
          'QuotationPartID': 2,
          'PartID': 11,
          'NumOfUse': 1,
          'PricePerUnit': 80,
          'ServiceFee': null,
        },
      ],
    });
    expect(detail.title, 'เปลี่ยนโช้ค');
    expect(detail.copiedToQuotationId, 'QT-20261031-004');
    expect(detail.parts.first.name, 'โช้คอัพหน้า');
    expect(detail.parts.first.isShort, isTrue);
    expect(detail.parts.first.total, closeTo(2701, 1e-9));
    expect(detail.total, closeTo(2781, 1e-9));
  });

  test('quotationTotals uses the quotation VAT settings', () {
    final q = Quotation.fromJson({
      'QuotationID': 'QT-20261031-001',
      'isVat': 1,
      'VatType': 1,
    });
    final details = [
      QuotationDetail.fromJson({
        'QuotationDetailID': 1,
        'quotationParts': [
          {'NumOfUse': 1, 'PricePerUnit': 1000, 'ServiceFee': 0},
        ],
      }),
    ];
    final t = quotationTotals(q, details);
    expect(t.vat, 70);
    expect(t.grandTotal, 1070);
  });
}
