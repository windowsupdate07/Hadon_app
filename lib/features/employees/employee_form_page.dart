import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../auth/auth_provider.dart';
import '../auth/employee.dart';
import '../parts/lookup_dropdown.dart';
import 'employees_api.dart';

/// Create (employee == null, via `/auth/register`) or edit an employee.
/// Callers must check the role rules in [EmployeeExtras] first.
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

  /// Web rule: letters and digits only, at least 6 characters.
  static const _minUsernameLength = 6;

  /// Roles strictly below the signed-in user's role (web rule). The edited
  /// employee's current role is kept so the dropdown can show it.
  Future<List<Option>> _loadRoles(Lookups lookups) async {
    final myRole = context.read<AuthProvider>().employee?.roleId;
    final current = widget.employee?.roleId;
    final all = await lookups.roles();
    return all
        .where((o) => o.id == current || (myRole != null && o.id > myRole))
        .toList();
  }

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

    final myRole = context.read<AuthProvider>().employee?.roleId;
    if (myRole == null || _roleId! <= myRole) {
      await AppDialogs.warn(
        context,
        'ไม่สามารถกำหนดระดับผู้ใช้งานเท่ากับหรือสูงกว่าของท่านได้',
      );
      return;
    }

    final bool ok;
    if (!_isEdit) {
      ok = await AppDialogs.confirm(
        context,
        title: 'ยืนยันการเพิ่มพนักงาน',
        message:
            'ระบบจะตั้งรหัสผ่านเริ่มต้นเป็น "$defaultEmployeePassword" '
            'กรุณาแจ้งพนักงานให้เข้าสู่ระบบและเปลี่ยนรหัสผ่านทันที',
      );
    } else if (_statusId == EmployeeStatusId.disabled &&
        !widget.employee!.isDisabled) {
      ok = await AppDialogs.confirm(
        context,
        title: 'ยืนยันการยกเลิกผู้ใช้งาน',
        message:
            'พนักงานจะถูกออกจากระบบทุกอุปกรณ์ และไม่สามารถเข้าสู่ระบบได้ '
            'ใช่หรือไม่?',
        destructive: true,
      );
    } else {
      ok = await AppDialogs.confirm(
        context,
        message: 'ท่านต้องการแก้ไขข้อมูลพนักงาน ใช่หรือไม่?',
      );
    }
    if (!ok || !mounted) {
      return;
    }

    final api = EmployeesApi(context.read<ApiClient>());
    final saved = await runWithProgress(context, () async {
      if (_isEdit) {
        await api.update(widget.employee!.id, input);
      } else {
        // Same as the web: start with a random default avatar.
        final avatar =
            defaultProfileImages[Random().nextInt(defaultProfileImages.length)];
        await api.register(_username.text.trim(), input, profileImage: avatar);
      }
      return true;
    });
    if (saved == true && mounted) {
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
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                ],
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) {
                    return 'กรุณากรอกชื่อผู้ใช้งาน';
                  }
                  if (s.length < _minUsernameLength) {
                    return 'ชื่อผู้ใช้งานต้องมีอย่างน้อย '
                        '$_minUsernameLength ตัวอักษร (a-z, 0-9)';
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
              label: 'ระดับผู้ใช้งาน',
              required: true,
              load: () => _loadRoles(lookups),
              value: _roleId,
              onChanged: (o) => setState(() => _roleId = o?.id),
            ),
            gap,
            if (_isEdit) ...[
              LookupDropdown(
                label: 'สถานะ',
                required: true,
                load: lookups.employeeStatuses,
                value: _statusId,
                onChanged: (o) => setState(() => _statusId = o?.id),
              ),
              if (_statusId == EmployeeStatusId.disabled)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'ผู้ใช้งานที่ถูกยกเลิกจะถูกออกจากระบบทุกอุปกรณ์',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              gap,
            ],
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
