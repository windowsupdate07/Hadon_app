import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../totals.dart';

/// Pledge amount for a percentage of [grandTotal], as the web's
/// CashPledgeDialog.calculatePledge: rounded up to whole baht but never
/// above the grand total (then rounded down).
double pledgeForPercent(double grandTotal, int percent) {
  final amount = grandTotal * percent / 100;
  var rounded = amount.ceilToDouble();
  if (rounded > grandTotal) {
    rounded = grandTotal.floorToDouble();
  }
  return rounded;
}

/// Asks for the deposit amount (web CashPledgeDialog): 20–100 % of the
/// quotation's grand total or a manual amount (capped at the grand total).
/// Returns the amount in baht.
Future<double?> showCashPledgeDialog(
  BuildContext context, {
  required DocumentTotals totals,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _CashPledgeDialog(totals: totals),
  );
}

class _CashPledgeDialog extends StatefulWidget {
  const _CashPledgeDialog({required this.totals});

  final DocumentTotals totals;

  @override
  State<_CashPledgeDialog> createState() => _CashPledgeDialogState();
}

class _CashPledgeDialogState extends State<_CashPledgeDialog> {
  static const _percents = [20, 40, 60, 80, 100];

  final _manual = TextEditingController();

  /// Selected percentage, or null for manual input.
  int? _percent = 100;

  double get _grand => widget.totals.grandTotal;

  double get _amount {
    if (_percent != null) {
      return pledgeForPercent(_grand, _percent!);
    }
    final v = double.tryParse(_manual.text) ?? 0;
    return v > _grand ? _grand.floorToDouble() : v;
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.totals;
    final amount = _amount;
    return AlertDialog(
      title: const Text('เงินมัดจำ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'เลือกเปอร์เซ็นต์มัดจำ (จากยอดรวม ${formatMoney(_grand)} บาท)',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _percents)
                  ChoiceChip(
                    label: Text('$p%'),
                    selected: _percent == p,
                    onSelected: (_) => setState(() => _percent = p),
                  ),
                ChoiceChip(
                  label: const Text('กรอกเอง'),
                  selected: _percent == null,
                  onSelected: (_) => setState(() => _percent = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_percent == null)
              TextField(
                controller: _manual,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'จำนวนเงิน (บาท)',
                  helperText:
                      'ไม่เกิน ${formatMoney(_grand.floorToDouble())} บาท',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                onChanged: (_) => setState(() {}),
              )
            else
              Text(
                'ยอดก่อนปัดเศษ: ${formatMoney(_grand * _percent! / 100)} บาท',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            const Divider(),
            if (t.isVat) InfoRow('รูปแบบภาษี', VatType.label(t.vatType)),
            InfoRow('ยอดรวมสุทธิ', '${formatMoney(_grand)} บาท'),
            InfoRow('จำนวนเงินมัดจำ', '${formatMoney(amount)} บาท', bold: true),
            InfoRow('ยอดคงเหลือ', '${formatMoney(_grand - amount)} บาท'),
            const SizedBox(height: 4),
            const Text(
              'ระบบจะสร้างใบแจ้งหนี้ (เงินมัดจำ) สถานะรอชำระเงินให้อัตโนมัติ',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: amount <= 0
              ? null
              : () => Navigator.of(context).pop(amount),
          child: const Text('บันทึกข้อมูล'),
        ),
      ],
    );
  }
}
