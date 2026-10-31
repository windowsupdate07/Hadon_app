import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import 'part_model.dart';

/// Result of [showPartPicker]: the chosen part and quantity.
class PickedPart {
  const PickedPart(this.part, this.quantity);

  final Part part;
  final double quantity;
}

/// Bottom sheet to search a part, then enter a quantity.
/// When [checkStock] is true the quantity cannot exceed `PartAmount`.
Future<PickedPart?> showPartPicker(
  BuildContext context, {
  bool checkStock = true,
}) {
  return showModalBottomSheet<PickedPart>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PartPickerSheet(checkStock: checkStock),
  );
}

class _PartPickerSheet extends StatefulWidget {
  const _PartPickerSheet({required this.checkStock});

  final bool checkStock;

  @override
  State<_PartPickerSheet> createState() => _PartPickerSheetState();
}

class _PartPickerSheetState extends State<_PartPickerSheet> {
  late Future<List<Part>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = PartsApi(context.read<ApiClient>()).findAll();
  }

  Future<void> _choose(Part part) async {
    final qty = await showDialog<double>(
      context: context,
      builder: (_) =>
          _QuantityDialog(part: part, checkStock: widget.checkStock),
    );
    if (qty != null && mounted) {
      Navigator.of(context).pop(PickedPart(part, qty));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Text('เลือกอะไหล่', style: Theme.of(context).textTheme.titleMedium),
          SearchField(
            hint: 'ค้นหารหัส / ชื่ออะไหล่',
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: FutureBuilder<List<Part>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(error: snap.error!);
                }
                final parts = snap.data!
                    .where((p) => _query.isEmpty || p.matches(_query))
                    .toList();
                if (parts.isEmpty) {
                  return const EmptyView();
                }
                return ListView.separated(
                  controller: scroll,
                  itemCount: parts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = parts[i];
                    final outOfStock = widget.checkStock && p.amount <= 0;
                    return ListTile(
                      enabled: !outOfStock,
                      title: Text(p.displayName),
                      subtitle: Text(
                        '${p.partNumber ?? '-'} · ${formatMoney(p.pricePerUnit)} บาท',
                      ),
                      trailing: Text(
                        'คงเหลือ ${formatNumber(p.amount)} ${p.unitName ?? ''}',
                        style: TextStyle(
                          color: outOfStock ? Colors.red : Colors.green,
                        ),
                      ),
                      onTap: () => _choose(p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.part, required this.checkStock});

  final Part part;
  final bool checkStock;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.part;
    final qty = double.tryParse(_qty.text) ?? 0;
    return AlertDialog(
      title: Text(p.displayName),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow('ราคา/หน่วย', formatMoney(p.pricePerUnit)),
            InfoRow('คงเหลือ', '${formatNumber(p.amount)} ${p.unitName ?? ''}'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'จำนวน'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) {
                  return 'กรุณากรอกจำนวนให้ถูกต้อง';
                }
                if (widget.checkStock && n > p.amount) {
                  return 'สินค้าคงเหลือไม่เพียงพอ';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            InfoRow('รวม', formatMoney(qty * p.pricePerUnit), bold: true),
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
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(double.parse(_qty.text));
            }
          },
          child: const Text('เพิ่ม'),
        ),
      ],
    );
  }
}
