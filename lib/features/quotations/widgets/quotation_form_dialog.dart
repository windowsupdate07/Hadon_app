import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';

/// Values entered in [showCreateQuotationDialog].
class NewQuotation {
  const NewQuotation({required this.brandId, required this.modelId, this.comment});

  final int brandId;
  final int modelId;
  final String? comment;
}

/// Dialog asking for the brand / model (required by `POST /quotation`) and
/// an optional comment.
Future<NewQuotation?> showCreateQuotationDialog(BuildContext context) {
  return showDialog<NewQuotation>(
    context: context,
    builder: (_) => const _CreateQuotationDialog(),
  );
}

class _CreateQuotationDialog extends StatefulWidget {
  const _CreateQuotationDialog();

  @override
  State<_CreateQuotationDialog> createState() => _CreateQuotationDialogState();
}

class _CreateQuotationDialogState extends State<_CreateQuotationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  late final Future<List<Option>> _brands;
  Future<List<Option>>? _models;
  Option? _brand;
  Option? _model;

  @override
  void initState() {
    super.initState();
    _brands = context.read<Lookups>().brands();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _onBrand(Option? b) {
    setState(() {
      _brand = b;
      _model = null;
      _models = b == null ? null : context.read<Lookups>().carModels(b.id);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      NewQuotation(
        brandId: _brand!.id,
        modelId: _model!.id,
        comment: _comment.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('สร้างใบเสนอราคา'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OptionDropdown(
                future: _brands,
                label: 'ยี่ห้อรถ *',
                value: _brand,
                onChanged: _onBrand,
              ),
              const SizedBox(height: 12),
              if (_models == null)
                DropdownButtonFormField<Option>(
                  items: const [],
                  onChanged: null,
                  decoration: const InputDecoration(
                    labelText: 'รุ่นรถ *',
                    helperText: 'กรุณาเลือกยี่ห้อก่อน',
                  ),
                  validator: (_) => 'กรุณาเลือกรุ่นรถ',
                )
              else
                _OptionDropdown(
                  key: ValueKey(_brand?.id),
                  future: _models!,
                  label: 'รุ่นรถ *',
                  value: _model,
                  onChanged: (m) => setState(() => _model = m),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _comment,
                maxLines: 3,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('สร้าง')),
      ],
    );
  }
}

class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    super.key,
    required this.future,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Future<List<Option>> future;
  final String label;
  final Option? value;
  final ValueChanged<Option?> onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Option>>(
      future: future,
      builder: (context, snap) {
        final items = snap.data ?? const <Option>[];
        final loading = snap.connectionState != ConnectionState.done;
        return DropdownButtonFormField<Option>(
          initialValue: items.contains(value) ? value : null,
          isExpanded: true,
          items: [
            for (final o in items)
              DropdownMenuItem(value: o, child: Text(o.label)),
          ],
          onChanged: loading ? null : onChanged,
          decoration: InputDecoration(
            labelText: label,
            helperText: snap.hasError
                ? 'โหลดข้อมูลไม่สำเร็จ'
                : (loading ? 'กำลังโหลด...' : null),
          ),
          validator: (v) => v == null ? 'กรุณาเลือก${label.replaceAll(' *', '')}' : null,
        );
      },
    );
  }
}

/// Dialog to edit the quotation comment. Returns the new text.
Future<String?> showEditCommentDialog(BuildContext context, String? current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditCommentDialog(current: current),
  );
}

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({this.current});

  final String? current;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _controller = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขหมายเหตุ'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        maxLength: 255,
        decoration: const InputDecoration(labelText: 'หมายเหตุ'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
