import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'preset_models.dart';

/// Values entered in [showPresetFormDialog].
class PresetInput {
  const PresetInput(this.name, this.status);

  final String name;
  final int status;
}

/// Create / edit dialog for a preset's name and status.
Future<PresetInput?> showPresetFormDialog(
  BuildContext context, {
  Preset? preset,
}) {
  return showDialog<PresetInput>(
    context: context,
    builder: (_) => _PresetFormDialog(preset: preset),
  );
}

class _PresetFormDialog extends StatefulWidget {
  const _PresetFormDialog({this.preset});

  final Preset? preset;

  @override
  State<_PresetFormDialog> createState() => _PresetFormDialogState();
}

class _PresetFormDialogState extends State<_PresetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.preset?.name ?? '');
    _active = widget.preset?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      PresetInput(
        _name.text.trim(),
        _active ? PresetStatus.active : PresetStatus.inactive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.preset == null ? 'เพิ่มพรีเซ็ต' : 'แก้ไขพรีเซ็ต'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'ชื่อพรีเซ็ต *'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อพรีเซ็ต' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('เปิดใช้งาน'),
              subtitle: Text(_active ? 'เปิดใช้งาน' : 'ปิดใช้งาน'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}

/// Asks for a whole-number quantity (`NumOfUse` is an INTEGER column).
Future<int?> showQuantityDialog(
  BuildContext context, {
  required String title,
  int initial = 1,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _QuantityDialog(title: title, initial: initial),
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: '${widget.initial}');
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(int.parse(_qty.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _qty,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'จำนวนที่ใช้'),
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            if (n == null || n <= 0) {
              return 'กรุณากรอกจำนวนเต็มมากกว่า 0';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}
