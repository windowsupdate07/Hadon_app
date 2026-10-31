import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../repair_models.dart';

/// Edits quantity / service fee / discount / part status of a repair part.
/// Returns the fields for `PUT /repairPart/bulk/update`, or null if cancelled
/// or nothing changed.
Future<Map<String, dynamic>?> showEditRepairPartDialog(
  BuildContext context,
  RepairPartLine line,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _EditRepairPartDialog(line: line),
  );
}

class _EditRepairPartDialog extends StatefulWidget {
  const _EditRepairPartDialog({required this.line});

  final RepairPartLine line;

  @override
  State<_EditRepairPartDialog> createState() => _EditRepairPartDialogState();
}

class _EditRepairPartDialogState extends State<_EditRepairPartDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late final TextEditingController _fee;
  late final TextEditingController _discount;

  /// 1 = baht; any other value = percent (backend PDF only checks `== 1`).
  late int _isDiscount;

  /// Value sent for "percent": keep the stored non-1 value, else 0.
  int get _percentValue =>
      widget.line.isDiscount != 1 ? widget.line.isDiscount : 0;
  late int _partStatusId;

  @override
  void initState() {
    super.initState();
    final l = widget.line;
    _qty = TextEditingController(text: '${l.numOfUse}');
    _fee = TextEditingController(text: _plain(l.serviceFee));
    _discount = TextEditingController(text: _plain(l.discount));
    _isDiscount = l.isDiscount;
    _partStatusId = l.partStatusId ?? PartStatus.locked;
  }

  @override
  void dispose() {
    _qty.dispose();
    _fee.dispose();
    _discount.dispose();
    super.dispose();
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  RepairPartLine get _preview {
    final l = widget.line;
    return RepairPartLine(
      id: l.id,
      repairDetailId: l.repairDetailId,
      numOfUse: int.tryParse(_qty.text) ?? 0,
      pricePerUnit: l.pricePerUnit,
      serviceFee: double.tryParse(_fee.text) ?? 0,
      discount: double.tryParse(_discount.text) ?? 0,
      isDiscount: _isDiscount,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final l = widget.line;
    final p = _preview;
    final fields = <String, dynamic>{};
    if (p.numOfUse != l.numOfUse) {
      fields['NumOfUse'] = p.numOfUse;
    }
    if (p.serviceFee != l.serviceFee) {
      fields['ServiceFee'] = p.serviceFee;
    }
    if (p.discount != l.discount) {
      fields['Discount'] = p.discount;
    }
    if (_isDiscount != l.isDiscount) {
      fields['isDiscount'] = _isDiscount;
    }
    if (_partStatusId != l.partStatusId) {
      fields['PartStatusID'] = _partStatusId;
    }
    Navigator.of(context).pop(fields.isEmpty ? null : fields);
  }

  String? _nonNegative(String? v) {
    final n = double.tryParse(v ?? '');
    if (n == null || n < 0) {
      return 'กรุณากรอกตัวเลขให้ถูกต้อง';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final preview = _preview;
    return AlertDialog(
      title: Text(l.displayName),
      scrollable: true,
      content: Form(
        key: _formKey,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow('ราคา/หน่วย', formatMoney(l.pricePerUnit)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _qty,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'จำนวน',
                suffixText: l.unitName,
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) {
                  return 'กรุณากรอกจำนวนเต็มที่มากกว่า 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'ค่าบริการ',
                suffixText: 'บาท',
              ),
              validator: _nonNegative,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'ส่วนลด'),
                    validator: (v) {
                      final err = _nonNegative(v);
                      if (err != null) {
                        return err;
                      }
                      final n = double.parse(v!);
                      if (_isDiscount != 1 && n > 100) {
                        return 'ไม่เกิน 100%';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: 1, label: Text('฿')),
                      ButtonSegment(
                        value: _percentValue,
                        label: const Text('%'),
                      ),
                    ],
                    selected: {_isDiscount},
                    onSelectionChanged: (s) =>
                        setState(() => _isDiscount = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _partStatusId,
              decoration: const InputDecoration(labelText: 'สถานะอะไหล่'),
              items: [
                for (final id in [
                  PartStatus.locked,
                  PartStatus.used,
                  PartStatus.purchasing,
                ])
                  DropdownMenuItem(
                    value: id,
                    child: Text(PartStatus.info(id).label),
                  ),
              ],
              onChanged: (v) => setState(() {
                _partStatusId = v ?? _partStatusId;
              }),
            ),
            const SizedBox(height: 12),
            InfoRow('รวม', formatMoney(preview.total), bold: true),
          ],
        ),
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
