import 'package:flutter_test/flutter_test.dart';
import 'package:honda_ntp/features/quotations/quotation_models.dart';
import 'package:honda_ntp/features/quotations/totals.dart';

// Expected values follow ntp-api/controllers/pdfCreateQuotation.controller.js:
//   line = NumOfUse * PricePerUnit + ServiceFee
//   vat  = isVat === 1 ? subtotal * 0.07 : 0

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

  group('DocumentTotals', () {
    final lines = [
      quotationLineTotal(quantity: 2, pricePerUnit: 1500, serviceFee: 200),
      quotationLineTotal(quantity: 1, pricePerUnit: 350.25, serviceFee: 0),
    ];

    test('without VAT the grand total equals the subtotal', () {
      final t = DocumentTotals.fromLines(lines, isVat: false);
      expect(t.subtotal, closeTo(3550.25, 1e-9));
      expect(t.vat, 0);
      expect(t.grandTotal, closeTo(3550.25, 1e-9));
    });

    test('with VAT adds 7% of the subtotal', () {
      final t = DocumentTotals.fromLines(lines, isVat: true);
      expect(t.vat, closeTo(248.5175, 1e-9));
      expect(t.grandTotal, closeTo(3798.7675, 1e-9));
    });

    test('cash pledge does not change the PDF grand total', () {
      final t = DocumentTotals.fromLines(
        lines,
        isVat: true,
        cashPledges: [1000, 500],
      );
      expect(t.cashPledge, 1500);
      expect(t.grandTotal, closeTo(3798.7675, 1e-9));
      expect(t.balance, closeTo(2298.7675, 1e-9));
    });

    test('empty quotation is zero', () {
      final t = DocumentTotals.fromLines(const [], isVat: true);
      expect(t.subtotal, 0);
      expect(t.vat, 0);
      expect(t.grandTotal, 0);
    });
  });

  test('isVatOn mirrors `isVat === 1`', () {
    expect(isVatOn(1), isTrue);
    expect(isVatOn(0), isFalse);
    expect(isVatOn(null), isFalse);
    expect(isVatOn(2), isFalse);
  });

  test('QuotationDetail parses API JSON and sums its parts', () {
    final detail = QuotationDetail.fromJson({
      'QuotationDetailID': 7,
      'RepairCategoryID': 2,
      'PresetID': 3,
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
    expect(detail.repairCategory, 'ช่วงล่าง');
    expect(detail.presetName, 'เปลี่ยนโช้ค');
    expect(detail.parts.first.name, 'โช้คอัพหน้า');
    expect(detail.parts.first.total, closeTo(2701, 1e-9));
    expect(detail.total, closeTo(2781, 1e-9));
  });
}
