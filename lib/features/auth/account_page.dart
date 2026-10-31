import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import 'auth_provider.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SectionCard(
          title: 'ข้อมูลผู้ใช้งาน',
          child: Column(
            children: [
              InfoRow('ชื่อ-นามสกุล', employee?.fullName),
              InfoRow('ชื่อผู้ใช้งาน', employee?.username),
              InfoRow('ตำแหน่ง', employee?.positionTitle),
              InfoRow('สิทธิ์', employee?.roleName),
              InfoRow('อีเมล', employee?.email),
              InfoRow('เบอร์โทร', employee?.tel),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.password),
            label: const Text('เปลี่ยนรหัสผ่าน'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _ChangePasswordDialog(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.logout),
            label: const Text('ออกจากระบบ'),
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final ok = await AppDialogs.confirm(
                context,
                message: 'ท่านต้องการออกจากระบบ ใช่หรือไม่?',
              );
              if (ok) {
                await auth.logout();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final ok = await runWithProgress(
      context,
      () async {
        await auth.changePassword(_old.text, _new.text);
        return true;
      },
    );
    if (ok == true && mounted) {
      navigator.pop();
      await AppDialogs.success(context, 'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว');
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.isEmpty) ? 'กรุณากรอกข้อมูล' : null;
    return AlertDialog(
      title: const Text('เปลี่ยนรหัสผ่าน'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _old,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'รหัสผ่านเดิม'),
              validator: required,
            ),
            TextFormField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่'),
              validator: required,
            ),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่'),
              validator: (v) => v != _new.text ? 'รหัสผ่านไม่ตรงกัน' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _save, child: const Text('บันทึก')),
      ],
    );
  }
}
