import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../repair_models.dart';

/// Result of [showReceiveTypeDialog].
class ReceiveTypeResult {
  const ReceiveTypeResult(this.receiveType, this.appointment);

  final int receiveType;

  /// Only set for [ReceiveType.appointment].
  final DateTime? appointment;
}

/// "รูปแบบการรับรถ" dialog, same choices as the web: wait, or an
/// appointment between 08:00 and 18:00 in 15-minute slots.
Future<ReceiveTypeResult?> showReceiveTypeDialog(
  BuildContext context,
  Repair repair,
) {
  return showDialog<ReceiveTypeResult>(
    context: context,
    builder: (_) => _ReceiveTypeDialog(repair: repair),
  );
}

class _ReceiveTypeDialog extends StatefulWidget {
  const _ReceiveTypeDialog({required this.repair});

  final Repair repair;

  @override
  State<_ReceiveTypeDialog> createState() => _ReceiveTypeDialogState();
}

class _ReceiveTypeDialogState extends State<_ReceiveTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _type;
  DateTime? _date;
  String? _time;

  static final List<String> _slots = [
    for (var h = 8; h <= 18; h++)
      for (var m = 0; m < 60; m += 15)
        if (!(h == 18 && m > 0))
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.repair;
    _type = r.receiveType == ReceiveType.appointment
        ? ReceiveType.appointment
        : ReceiveType.wait;
    final d = r.receiveAppointmentDate;
    if (d != null) {
      _date = DateTime(d.year, d.month, d.day);
      final t =
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      _time = _slots.contains(t) ? t : null;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_type == ReceiveType.wait) {
      Navigator.of(
        context,
      ).pop(const ReceiveTypeResult(ReceiveType.wait, null));
      return;
    }
    final parts = _time!.split(':');
    final d = _date!;
    Navigator.of(context).pop(
      ReceiveTypeResult(
        ReceiveType.appointment,
        DateTime(
          d.year,
          d.month,
          d.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('รูปแบบการรับรถ'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<int>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v ?? _type),
              child: const Column(
                children: [
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: ReceiveType.wait,
                    title: Text('ลูกค้ารอรับ (ซ่อมเสร็จรับกลับทันที)'),
                  ),
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: ReceiveType.appointment,
                    title: Text('ลูกค้านัดรับในวันเวลาอื่น'),
                  ),
                ],
              ),
            ),
            if (_type == ReceiveType.appointment) ...[
              const SizedBox(height: 8),
              FormField<DateTime>(
                validator: (_) =>
                    _date == null ? 'กรุณาเลือกวันที่นัดรับ' : null,
                builder: (field) => InkWell(
                  onTap: () async {
                    await _pickDate();
                    field.didChange(_date);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'วันที่นัดรับ',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: const OutlineInputBorder(),
                      errorText: field.errorText,
                    ),
                    child: Text(_date == null ? '-' : formatThaiDate(_date)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _time,
                decoration: const InputDecoration(
                  labelText: 'เวลานัดรับ (24 น.)',
                  prefixIcon: Icon(Icons.schedule),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in _slots)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                validator: (v) => v == null ? 'กรุณาเลือกเวลานัดรับ' : null,
                onChanged: (v) => setState(() => _time = v),
              ),
            ],
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
