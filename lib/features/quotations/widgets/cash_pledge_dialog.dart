import 'package:flutter/material.dart';

/// Values for `POST /cash-pledge`.
class CashPledgeInput {
  const CashPledgeInput(this.title, this.amount);

  final String title;
  final double amount;
}

Future<CashPledgeInput?> showCashPledgeDialog(BuildContext context) {
  return showDialog<CashPledgeInput>(
    context: context,
    builder: (_) => const _CashPledgeDialog(),
  );
}

class _CashPledgeDialog extends StatefulWidget {
  const _CashPledgeDialog();

  @override
  State<_CashPledgeDialog> createState() => _CashPledgeDialogState();
}

class _CashPledgeDialogState extends State<_CashPledgeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'เงินมัดจำ');
  final _amount = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มเงินมัดจำ'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'รายการ *'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกรายการ' : null,
            ),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'จำนวนเงิน (บาท) *',
              ),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) {
                  return 'กรุณากรอกจำนวนเงินให้ถูกต้อง';
                }
                return null;
              },
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              CashPledgeInput(_title.text.trim(), double.parse(_amount.text)),
            );
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
