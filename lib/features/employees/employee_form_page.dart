import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../auth/employee.dart';
import '../parts/lookup_dropdown.dart';
import 'employees_api.dart';

/// Create (employee == null, via `/auth/register`) or edit an employee.
/// Pops `true` after a successful save.
class EmployeeFormPage extends StatefulWidget {
  const EmployeeFormPage({super.key, this.employee});

  final Employee? employee;

  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _tel;
  int? _positionId;
  int? _roleId;
  int? _statusId;

  bool get _isEdit => widget.employee != null;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _username = TextEditingController(text: e?.username ?? '');
    _firstName = TextEditingController(text: e?.firstName ?? '');
    _lastName = TextEditingController(text: e?.lastName ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _tel = TextEditingController(text: e?.tel ?? '');
    _positionId = e?.positionId;
    _roleId = e?.roleId;
    _statusId = e?.employeeStatusId ?? EmployeeStatusId.active;
  }

  @override
  void dispose() {
    _username.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _tel.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController c) {
    final s = c.text.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_positionId == null || _roleId == null || _statusId == null) {
      await AppDialogs.warn(
        context,
        'กรุณาเลือกตำแหน่ง สิทธิ์ และสถานะให้ครบถ้วน',
      );
      return;
    }
    final input = EmployeeInput(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      positionId: _positionId!,
      roleId: _roleId!,
      statusId: _statusId!,
      email: _nullIfEmpty(_email),
      tel: _nullIfEmpty(_tel),
    );

    if (!_isEdit) {
      final ok = await AppDialogs.confirm(
        context,
        title: 'ยืนยันการเพิ่มพนักงาน',
        message:
            'ระบบจะตั้งรหัสผ่านเริ่มต้นเป็น "$defaultEmployeePassword" '
            'กรุณาแจ้งพนักงานให้เข้าสู่ระบบและเปลี่ยนรหัสผ่านทันที',
      );
      if (!ok || !mounted) {
        return;
      }
    }

    final api = EmployeesApi(context.read<ApiClient>());
    final ok = await runWithProgress(context, () async {
      if (_isEdit) {
        await api.update(widget.employee!.id, input);
      } else {
        await api.register(_username.text.trim(), input);
      }
      return true;
    });
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<Lookups>();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขข้อมูลพนักงาน' : 'เพิ่มพนักงาน'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) ...[
              Card(
                color: Colors.orange.shade50,
                child: const ListTile(
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                  title: Text('รหัสผ่านเริ่มต้น: "$defaultEmployeePassword"'),
                  subtitle: Text(
                    'ระบบจะกำหนดรหัสผ่านนี้ให้อัตโนมัติ '
                    'พนักงานต้องเปลี่ยนรหัสผ่านที่เมนู "บัญชีผู้ใช้" '
                    'หลังเข้าสู่ระบบครั้งแรก',
                  ),
                ),
              ),
              gap,
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'ชื่อผู้ใช้งาน *'),
                autocorrect: false,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) {
                    return 'กรุณากรอกชื่อผู้ใช้งาน';
                  }
                  if (s.length < 3) {
                    return 'ชื่อผู้ใช้งานต้องมีอย่างน้อย 3 ตัวอักษร';
                  }
                  return null;
                },
              ),
              gap,
            ] else ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'ชื่อผู้ใช้งาน',
                  enabled: false,
                ),
                child: Text(widget.employee!.username),
              ),
              gap,
            ],
            TextFormField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'ชื่อ *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อ' : null,
            ),
            gap,
            TextFormField(
              controller: _lastName,
              decoration: const InputDecoration(labelText: 'นามสกุล *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกนามสกุล' : null,
            ),
            gap,
            LookupDropdown(
              label: 'ตำแหน่ง',
              required: true,
              load: lookups.positions,
              value: _positionId,
              onChanged: (o) => setState(() => _positionId = o?.id),
            ),
            gap,
            LookupDropdown(
              label: 'สิทธิ์การใช้งาน',
              required: true,
              load: lookups.roles,
              value: _roleId,
              onChanged: (o) => setState(() => _roleId = o?.id),
            ),
            gap,
            LookupDropdown(
              label: 'สถานะ',
              required: true,
              load: lookups.employeeStatuses,
              value: _statusId,
              onChanged: (o) => setState(() => _statusId = o?.id),
            ),
            gap,
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'อีเมล'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isNotEmpty && !_emailPattern.hasMatch(s)) {
                  return 'รูปแบบอีเมลไม่ถูกต้อง';
                }
                return null;
              },
            ),
            gap,
            TextFormField(
              controller: _tel,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทรศัพท์',
                counterText: '',
              ),
              keyboardType: TextInputType.phone,
              maxLength: 20,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+ ]')),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
