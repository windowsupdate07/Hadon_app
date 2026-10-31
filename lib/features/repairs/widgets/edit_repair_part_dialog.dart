import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../parts/part_model.dart';
import '../repair_models.dart';
import '../repairs_api.dart';

/// Edits the quantity of a repair part, which is the only field the web's
/// repair page edits (discounts are edited on the invoice page). Returns the
/// new quantity, or null if cancelled or unchanged.
///
/// `PUT /repairPart/bulk/update` deducts / returns the difference from stock
/// and rejects increases larger than `PartAmount`, so the current stock is
/// fetched to validate before sending.
Future<int?> showEditRepairPartDialog(
  BuildContext context, {
  required RepairsApi api,
  required RepairPartLine line,
  required bool allocated,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _EditRepairPartDialog(api: api, line: line, allocated: allocated),
  );
}

class _EditRepairPartDialog extends StatefulWidget {
  const _EditRepairPartDialog({
    required this.api,
    required this.line,
    required this.allocated,
  });

  final RepairsApi api;
  final RepairPartLine line;

  /// True once the parts were handed out (status 5 / 9): show AllocatedNum.
  final bool allocated;

  @override
  State<_EditRepairPartDialog> createState() => _EditRepairPartDialogState();
}

class _EditRepairPartDialogState extends State<_EditRepairPartDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late Future<Part?> _stock;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: '${widget.line.numOfUse}');
    _stock = _loadStock();
  }

  /// Null when the part cannot be loaded; the server still checks stock.
  Future<Part?> _loadStock() async {
    final id = widget.line.partId;
    if (id == null) {
      return null;
    }
    try {
      return await widget.api.part(id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final n = int.parse(_qty.text.trim());
    Navigator.of(context).pop(n == widget.line.numOfUse ? null : n);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final n = int.tryParse(_qty.text.trim()) ?? 0;
    final preview = n * l.pricePerUnit + l.serviceFee;
    return AlertDialog(
      title: Text(l.displayName),
      scrollable: true,
      content: FutureBuilder<Part?>(
        future: _stock,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final stock = snap.data?.amount;
          return Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (l.partNumber != null) InfoRow('รหัสอะไหล่', l.partNumber),
                InfoRow('ราคา/หน่วย', formatMoney(l.pricePerUnit)),
                InfoRow('ค่าบริการ', formatMoney(l.serviceFee)),
                InfoRow(
                  'คงเหลือในคลัง',
                  loading
                      ? 'กำลังโหลด...'
                      : stock == null
                      ? 'ไม่ทราบ'
                      : '${formatNumber(stock)} ${l.unitName ?? ''}',
                ),
                if (widget.allocated)
                  InfoRow(
                    'จัดสรรแล้ว',
                    '${formatNumber(l.allocatedNum)} ${l.unitName ?? ''}',
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'จำนวน',
                    suffixText: l.unitName,
                    helperText: stock == null
                        ? null
                        : 'ใช้ได้สูงสุด ${formatNumber(l.numOfUse + stock)}',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n <= 0) {
                      return 'กรุณากรอกจำนวนเต็มที่มากกว่า 0';
                    }
                    if (stock != null && n - l.numOfUse > stock) {
                      return 'สินค้าคงเหลือในคลังไม่เพียงพอ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InfoRow('จำนวนเงิน', formatMoney(preview), bold: true),
                if (widget.allocated && n != l.allocatedNum)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'มีการเปลี่ยนแปลงจากจำนวนที่จัดสรรแล้ว '
                      'กรุณากด "ขอจัดสรรอุปกรณ์เพิ่มเติม" หลังบันทึก',
                      style: TextStyle(color: Colors.deepOrange[700]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}
