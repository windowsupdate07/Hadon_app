import 'package:flutter/material.dart';

import '../../../core/widgets/app_dialogs.dart';

/// Two-step confirmation used by the web before `POST /repair/cancel/:id`:
/// 1) ask for a reason (required by the backend), 2) confirm again because
/// the action cannot be undone. Returns the trimmed reason, or null.
Future<String?> askCancelRepairReason(
  BuildContext context,
  int repairId,
) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(repairId: repairId),
  );
  if (reason == null || !context.mounted) {
    return null;
  }
  final ok = await AppDialogs.confirm(
    context,
    title: 'ยืนยันอีกครั้ง? (ครั้งที่ 2/2)',
    message:
        'การกระทำนี้ไม่สามารถย้อนกลับได้\n'
        'อะไหล่ทั้งหมดจะถูกคืนเข้าสต๊อก และใบแจ้งหนี้ของงานซ่อมนี้จะถูกยกเลิก',
    destructive: true,
  );
  return ok ? reason : null;
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.repairId});

  final int repairId;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_reason.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 40),
      title: const Text('ยืนยันการยกเลิกการซ่อม?'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ต้องการยกเลิกการซ่อม #${widget.repairId} ใช่หรือไม่? '
              '(ครั้งที่ 1/2)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'เหตุผลในการยกเลิก *',
                hintText: 'กรุณาระบุเหตุผล...',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณาระบุเหตุผล!' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('กลับ'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('ยืนยันการยกเลิก'),
        ),
      ],
    );
  }
}
