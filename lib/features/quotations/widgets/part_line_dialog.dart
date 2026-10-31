import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../totals.dart';

/// Edited values of a quotation part line.
class PartLineValues {
  const PartLineValues({
    required this.quantity,
    required this.pricePerUnit,
    required this.serviceFee,
  });

  final int quantity;
  final double pricePerUnit;
  final double serviceFee;

  /// Body for `PUT /quotation-part/:id`.
  Map<String, dynamic> toJson() => {
    'NumOfUse': quantity,
    'PricePerUnit': pricePerUnit,
    'ServiceFee': serviceFee,
  };
}

/// Dialog to edit quantity, unit price and service fee of a part line.
/// `NumOfUse` is an INTEGER column, so only whole quantities are accepted.
Future<PartLineValues?> showPartLineDialog(
  BuildContext context, {
  required String title,
  required PartLineValues initial,
}) {
  return showDialog<PartLineValues>(
    context: context,
    builder: (_) => _PartLineDialog(title: title, initial: initial),
  );
}

class _PartLineDialog extends StatefulWidget {
  const _PartLineDialog({required this.title, required this.initial});

  final String title;
  final PartLineValues initial;

  @override
  State<_PartLineDialog> createState() => _PartLineDialogState();
}

class _PartLineDialogState extends State<_PartLineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _qty = TextEditingController(text: '${widget.initial.quantity}');
  late final _price = TextEditingController(
    text: _plain(widget.initial.pricePerUnit),
  );
  late final _fee = TextEditingController(
    text: _plain(widget.initial.serviceFee),
  );

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _fee.dispose();
    super.dispose();
  }

  String? _money(String? v) {
    final n = double.tryParse(v ?? '');
    if (n == null || n < 0) {
      return 'กรุณากรอกจำนวนเงินให้ถูกต้อง';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final total = quotationLineTotal(
      quantity: int.tryParse(_qty.text) ?? 0,
      pricePerUnit: double.tryParse(_price.text) ?? 0,
      serviceFee: double.tryParse(_fee.text) ?? 0,
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'จำนวน'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) {
                    return 'กรุณากรอกจำนวนเต็มมากกว่า 0';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'ราคา/หน่วย'),
                validator: _money,
              ),
              TextFormField(
                controller: _fee,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ค่าบริการ (ต่อรายการ)',
                ),
                validator: _money,
              ),
              const SizedBox(height: 8),
              InfoRow('จำนวนเงิน', '${formatMoney(total)} บาท', bold: true),
            ],
          ),
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
              PartLineValues(
                quantity: int.parse(_qty.text),
                pricePerUnit: double.parse(_price.text),
                serviceFee: double.parse(_fee.text),
              ),
            );
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
