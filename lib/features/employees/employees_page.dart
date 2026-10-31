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
  final disabled = e.employeeStatusId == EmployeeStatusId.disabled;
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
      final sa = a.employeeStatusId == EmployeeStatusId.disabled ? 1 : 0;
      final sb = b.employeeStatusId == EmployeeStatusId.disabled ? 1 : 0;
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
      final disabled = e.employeeStatusId == EmployeeStatusId.disabled;
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

  Future<void> _showDetail(Employee e) async {
    final me = context.read<AuthProvider>().employee;
    final canManage = me?.canManage ?? false;
    final isMe = me?.id == e.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isMe ? '${e.fullName} (คุณ)' : e.fullName,
                style: Theme.of(context).textTheme.titleLarge,
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
              if (canManage) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!isMe) ...[
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
    if (action == 'edit') {
      await _openForm(e);
    } else if (action == 'delete') {
      await _delete(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    return AppScaffold(
      title: 'ข้อมูลพนักงาน',
      floatingActionButton: canManage
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
        final disabled = e.employeeStatusId == EmployeeStatusId.disabled;
        return Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: disabled ? Colors.grey.shade200 : null,
            child: ListTile(
              onTap: () => _showDetail(e),
              leading: CircleAvatar(
                backgroundColor: disabled ? Colors.grey.shade400 : null,
                child: Text(e.initials),
              ),
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
