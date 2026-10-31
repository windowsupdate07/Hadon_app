import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import '../auth/auth_provider.dart';
import '../auth/employee.dart';
import 'employee_avatar.dart';
import 'employee_form_page.dart';
import 'employees_api.dart';

enum _StatusFilter { all, active, disabled }

StatusInfo _positionInfo(Employee e) {
  final label = e.positionTitle ?? '-';
  switch (e.positionId) {
    case Position.admin:
      return StatusInfo(label, Colors.red);
    case Position.manager:
      return StatusInfo(label, Colors.purple);
    case Position.accountant:
      return StatusInfo(label, Colors.teal);
    case Position.receptionist:
      return StatusInfo(label, Colors.blue);
    case Position.technician:
      return StatusInfo(label, Colors.orange);
    default:
      return StatusInfo(label, Colors.blueGrey);
  }
}

StatusInfo _statusInfo(Employee e) {
  final disabled = e.isDisabled;
  return StatusInfo(
    e.employeeStatusTitle ?? (disabled ? 'ยกเลิกผู้ใช้งาน' : 'ปกติ'),
    disabled ? Colors.grey : Colors.green,
  );
}

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late final EmployeesApi _api;
  late Future<List<Employee>> _future;
  String _query = '';
  int _page = 0;
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _api = EmployeesApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<List<Employee>> _load() async {
    final list = await _api.findAll();
    // Active first, then by name.
    list.sort((a, b) {
      final sa = a.isDisabled ? 1 : 0;
      final sb = b.isDisabled ? 1 : 0;
      if (sa != sb) {
        return sa - sb;
      }
      return a.fullName.compareTo(b.fullName);
    });
    return list;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  List<Employee> _apply(List<Employee> all) {
    return all.where((e) {
      if (_query.isNotEmpty && !e.matches(_query)) {
        return false;
      }
      final disabled = e.isDisabled;
      switch (_filter) {
        case _StatusFilter.active:
          return !disabled;
        case _StatusFilter.disabled:
          return disabled;
        case _StatusFilter.all:
          return true;
      }
    }).toList();
  }

  Future<void> _openForm([Employee? employee]) async {
    final auth = context.read<AuthProvider>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeFormPage(employee: employee)),
    );
    if (saved != true || !mounted) {
      return;
    }
    AppDialogs.toast(context, 'บันทึกข้อมูลเรียบร้อยแล้ว');
    if (employee != null && employee.id == auth.employee?.id) {
      // Refresh the signed-in user's cached profile (name, position ...).
      await auth.restore();
    }
    await _refresh();
  }

  Future<void> _delete(Employee employee) async {
    final ok = await AppDialogs.confirmDelete(
      context,
      'พนักงาน "${employee.fullName}"',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(employee.id);
      return true;
    }, successMessage: 'ลบข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _resetPassword(Employee employee) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'รีเซ็ตรหัสผ่าน',
      message:
          'ท่านต้องการรีเซ็ตรหัสผ่านของ "${employee.fullName}" '
          'เป็น "$defaultEmployeePassword" ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.resetPassword(employee.id);
      return true;
    });
    if (done == true && mounted) {
      await AppDialogs.success(
        context,
        'รีเซ็ตรหัสผ่านเป็น "$defaultEmployeePassword" แล้ว '
        'กรุณาแจ้งพนักงานให้เปลี่ยนรหัสผ่านหลังเข้าสู่ระบบ',
      );
    }
  }

  Future<void> _changePhoto(Employee employee) async {
    final auth = context.read<AuthProvider>();
    final changed = await changeEmployeePhoto(context, employee);
    if (!changed || !mounted) {
      return;
    }
    if (employee.id == auth.employee?.id) {
      // Keep the signed-in user's cached profile in sync.
      await auth.restore();
    }
    await _refresh();
  }

  Future<void> _showDetail(Employee e) async {
    final me = context.read<AuthProvider>().employee;
    final isMe = me?.id == e.id;
    final canEdit = me?.canEditEmployee(e) ?? false;
    final canDelete = me?.canDeleteEmployee(e) ?? false;
    final canPhoto = me?.canChangePhotoOf(e) ?? false;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  EmployeeAvatar(employee: e, radius: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      isMe ? '${e.fullName} (คุณ)' : e.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(_positionInfo(e)),
                  if (e.roleName != null)
                    StatusChip(StatusInfo(e.roleName!, Colors.indigo)),
                  StatusChip(_statusInfo(e)),
                ],
              ),
              const Divider(),
              InfoRow('ชื่อผู้ใช้งาน', e.username),
              InfoRow('อีเมล', e.email),
              InfoRow('เบอร์โทรศัพท์', e.tel),
              if (canPhoto || canEdit) const SizedBox(height: 12),
              if (canPhoto)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop('photo'),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('เปลี่ยนรูปโปรไฟล์'),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                  ),
                  onPressed: () => Navigator.of(context).pop('reset'),
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('รีเซ็ตรหัสผ่าน'),
                ),
              if (canEdit) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canDelete) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.of(context).pop('delete'),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('ลบ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop('edit'),
                        icon: const Icon(Icons.edit),
                        label: const Text('แก้ไข'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'edit':
        await _openForm(e);
      case 'delete':
        await _delete(e);
      case 'reset':
        await _resetPassword(e);
      case 'photo':
        await _changePhoto(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        context.watch<AuthProvider>().employee?.canCreateEmployee ?? false;
    return AppScaffold(
      title: 'ข้อมูลพนักงาน',
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              tooltip: 'เพิ่มพนักงาน',
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาชื่อ / ชื่อผู้ใช้ / อีเมล / เบอร์โทร / ตำแหน่ง',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip('ทั้งหมด', _StatusFilter.all),
                _filterChip('ปกติ', _StatusFilter.active),
                _filterChip('ยกเลิกผู้ใช้งาน', _StatusFilter.disabled),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Employee>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลพนักงาน',
              builder: (context, data) => _buildList(_apply(data)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _StatusFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() {
          _filter = value;
          _page = 0;
        }),
      ),
    );
  }

  Widget _buildList(List<Employee> list) {
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 80), EmptyView()],
      );
    }
    final pageCount = (list.length / PageBar.pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final items = list
        .skip(page * PageBar.pageSize)
        .take(PageBar.pageSize)
        .toList();
    final myId = context.read<AuthProvider>().employee?.id;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'ทั้งหมด ${list.length} คน',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        if (i == items.length + 1) {
          return PageBar(
            page: page,
            pageCount: pageCount,
            onChanged: (p) => setState(() => _page = p),
          );
        }
        final e = items[i - 1];
        final disabled = e.isDisabled;
        return Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: disabled ? Colors.grey.shade200 : null,
            child: ListTile(
              onTap: () => _showDetail(e),
              leading: EmployeeAvatar(employee: e, dimmed: disabled),
              title: Text(e.id == myId ? '${e.fullName} (คุณ)' : e.fullName),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([e.username, if (e.tel != null) e.tel!].join(' · ')),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusChip(_positionInfo(e)),
                        if (e.roleName != null)
                          StatusChip(StatusInfo(e.roleName!, Colors.indigo)),
                        StatusChip(_statusInfo(e)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
