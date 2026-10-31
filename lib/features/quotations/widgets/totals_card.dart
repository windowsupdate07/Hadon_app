import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../totals.dart';

/// Summary card shared by quotation and invoice detail pages. The first
/// three rows match the server PDF; pledge rows are shown only when
/// [showPledge] is true.
class TotalsCard extends StatelessWidget {
  const TotalsCard({
    super.key,
    required this.totals,
    this.showPledge = false,
    this.vatSwitch,
  });

  final DocumentTotals totals;
  final bool showPledge;

  /// Optional VAT toggle shown above the totals.
  final Widget? vatSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'สรุปยอด',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?vatSwitch,
          _row('ยอดรวม (Subtotal)', totals.subtotal),
          _row(
            'ภาษีมูลค่าเพิ่ม 7%',
            totals.vat,
            text: totals.isVat ? null : '-',
          ),
          const Divider(),
          _row(
            'ยอดรวมสุทธิ',
            totals.grandTotal,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          if (showPledge && totals.cashPledge > 0) ...[
            _row('หักเงินมัดจำ', -totals.cashPledge),
            _row(
              'ยอดคงเหลือชำระ',
              totals.balance,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '* ยอดหักมัดจำแสดงในแอปเท่านั้น ไม่ปรากฏในไฟล์ PDF',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double value, {String? text, TextStyle? style}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${text ?? formatMoney(value)} บาท', style: style),
        ],
      ),
    );
  }
}
