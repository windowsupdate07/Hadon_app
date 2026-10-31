import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../totals.dart';

/// Summary card shared by the quotation and invoice detail pages. Rows and
/// labels follow the server PDFs' `generateTotals()`:
///   ยอดรวม (Subtotal) / ภาษีมูลค่าเพิ่ม 7% / ยอดรวมสุทธิ, or — when the
///   pledge is deducted (repair invoices) — รวมจำนวนเงิน / หักมัดจำ /
///   ยอดที่ต้องชำระ.
class TotalsCard extends StatelessWidget {
  const TotalsCard({
    super.key,
    required this.totals,
    this.vatControls,
    this.title = 'สรุปยอด',
  });

  final DocumentTotals totals;

  /// Optional VAT toggles shown above the totals.
  final Widget? vatControls;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = totals;
    final strong = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
    final pledgeDeducted = t.deductPledge && t.hasPledge;
    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?vatControls,
          if (t.isVat)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                VatType.label(t.vatType),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.vatType == VatType.exclude ? Colors.red : Colors.green,
                ),
              ),
            ),
          if (t.isVat && t.vatType != VatType.exclude)
            _row('รวมเป็นเงิน (รวมภาษีแล้ว)', t.itemsSum),
          _row('ยอดรวม (Subtotal)', t.priceBeforeVat),
          _row('ภาษีมูลค่าเพิ่ม 7%', t.vat, text: t.isVat ? null : '-'),
          const Divider(),
          if (pledgeDeducted) ...[
            _row('รวมจำนวนเงิน', t.grandTotal),
            _row('หักมัดจำ', -t.cashPledge, color: Colors.red),
            const Divider(),
            _row('ยอดที่ต้องชำระ', t.netTotal, style: strong),
          ] else ...[
            _row('ยอดรวมสุทธิ', t.grandTotal, style: strong),
            if (t.hasPledge) ...[
              _row('เงินมัดจำ', -t.cashPledge, color: Colors.red),
              _row(
                'ยอดคงเหลือหลังหักมัดจำ',
                t.balanceAfterPledge,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '* ใบเสนอราคา (PDF) ไม่หักเงินมัดจำ — หักในใบแจ้งหนี้ค่าซ่อม',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    double value, {
    String? text,
    TextStyle? style,
    Color? color,
  }) {
    final s = style ?? (color == null ? null : TextStyle(color: color));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: s)),
          Text('${text ?? formatMoney(value)} บาท', style: s),
        ],
      ),
    );
  }
}

/// VAT on/off + include/exclude controls (web checkbox + switch).
class VatControls extends StatelessWidget {
  const VatControls({
    super.key,
    required this.isVat,
    required this.vatType,
    required this.onChanged,
    this.disabledReason,
  });

  final bool isVat;
  final int vatType;

  /// Called with the new (isVat, vatType); null disables the controls.
  final void Function(bool isVat, int vatType)? onChanged;

  /// Shown under the controls when they are disabled.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (change == null && disabledReason != null)
          Text(
            disabledReason!,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('คิดภาษีมูลค่าเพิ่ม (VAT 7%)'),
          value: isVat,
          onChanged: change == null ? null : (v) => change(v ?? false, vatType),
        ),
        if (isVat)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: VatType.include, label: Text('Include VAT')),
                ButtonSegment(value: VatType.exclude, label: Text('Exclude VAT')),
              ],
              selected: {vatType},
              onSelectionChanged:
                  change == null ? null : (s) => change(true, s.first),
            ),
          ),
      ],
    );
  }
}
