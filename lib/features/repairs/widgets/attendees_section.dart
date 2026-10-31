import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/employee.dart';
import '../repairs_api.dart';
import 'inline_error.dart';

/// Technicians assigned to the repair (`RepairAttendance`).
class AttendeesSection extends StatefulWidget {
  const AttendeesSection({
    super.key,
    required this.api,
    required this.repairId,
    required this.editable,
    this.onChanged,
  });

  final RepairsApi api;
  final int repairId;
  final bool editable;

  /// Called after a successful change.
  final VoidCallback? onChanged;

  @override
  State<AttendeesSection> createState() => _AttendeesSectionState();
}

class _AttendeesSectionState extends State<AttendeesSection> {
  late Future<List<Employee>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.attendees(widget.repairId);
  }

  void _reload() {
    setState(() => _future = widget.api.attendees(widget.repairId));
  }

  /// Lets the page refresh the timeline; falls back to a local reload.
  void _changed() {
    final cb = widget.onChanged;
    if (cb != null) {
      cb();
    } else {
      _reload();
    }
  }

  Future<void> _edit(List<Employee> current) async {
    final ids = await showAttendeePicker(
      context,
      api: widget.api,
      selected: current.map((e) => e.id).toSet(),
    );
    if (ids == null || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await widget.api.setAttendees(widget.repairId, ids);
      return true;
    }, successMessage: 'บันทึกช่างผู้รับผิดชอบเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _changed();
    }
  }

  Future<void> _remove(Employee e) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการนำออก?',
      message: 'ท่านต้องการนำ "${e.fullName}" ออกจากงานซ่อมนี้ ใช่หรือไม่?',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await widget.api.removeAttendees(widget.repairId, [e.id]);
      return true;
    }, successMessage: 'นำช่างออกเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Employee>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final list = snap.data ?? const <Employee>[];
        Widget child;
        if (loading) {
          child = const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError) {
          child = InlineError(error: snap.error!, onRetry: _reload);
        } else if (list.isEmpty) {
          child = const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'ยังไม่ได้มอบหมายช่าง',
              style: TextStyle(color: Colors.grey),
            ),
          );
        } else {
          child = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in list)
                InputChip(
                  avatar: CircleAvatar(child: Text(e.initials)),
                  label: Text(
                    e.positionTitle == null
                        ? e.fullName
                        : '${e.fullName} (${e.positionTitle})',
                  ),
                  onDeleted: widget.editable ? () => _remove(e) : null,
                  deleteButtonTooltipMessage: 'นำออก',
                ),
            ],
          );
        }
        return SectionCard(
          title: 'ช่างผู้รับผิดชอบ',
          trailing: widget.editable && !loading && !snap.hasError
              ? TextButton.icon(
                  onPressed: () => _edit(list),
                  icon: const Icon(Icons.edit),
                  label: const Text('แก้ไข'),
                )
              : null,
          child: child,
        );
      },
    );
  }
}

/// Multi-select of active employees (technicians listed first). Returns the
/// chosen ids, or null when cancelled. With [requireOne] the dialog refuses
/// an empty selection (finishing a repair needs at least one technician).
Future<List<int>?> showAttendeePicker(
  BuildContext context, {
  required RepairsApi api,
  required Set<int> selected,
  bool requireOne = false,
  String confirmLabel = 'บันทึก',
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (_) => _EmployeePickerDialog(
      api: api,
      selected: selected,
      requireOne: requireOne,
      confirmLabel: confirmLabel,
    ),
  );
}

class _EmployeePickerDialog extends StatefulWidget {
  const _EmployeePickerDialog({
    required this.api,
    required this.selected,
    required this.requireOne,
    required this.confirmLabel,
  });

  final RepairsApi api;
  final Set<int> selected;
  final bool requireOne;
  final String confirmLabel;

  @override
  State<_EmployeePickerDialog> createState() => _EmployeePickerDialogState();
}

class _EmployeePickerDialogState extends State<_EmployeePickerDialog> {
  late Future<List<Employee>> _future;
  late final Set<int> _selected = {...widget.selected};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Employee>> _load() async {
    final all = await widget.api.employees();
    // Active employees (status 1) plus anyone already assigned.
    final list = all
        .where(
          (e) =>
              e.employeeStatusId == null ||
              e.employeeStatusId == 1 ||
              widget.selected.contains(e.id),
        )
        .toList();
    int rank(Employee e) => e.positionId == Position.technician ? 0 : 1;
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.fullName.compareTo(b.fullName);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เลือกช่างผู้รับผิดชอบ'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: FutureBuilder<List<Employee>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final q = _query.toLowerCase();
            final list = snap.data!
                .where(
                  (e) =>
                      q.isEmpty ||
                      e.fullName.toLowerCase().contains(q) ||
                      (e.positionTitle ?? '').toLowerCase().contains(q),
                )
                .toList();
            return Column(
              children: [
                SearchField(
                  hint: 'ค้นหาชื่อพนักงาน',
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyView()
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final e = list[i];
                            return CheckboxListTile(
                              value: _selected.contains(e.id),
                              title: Text(e.fullName),
                              subtitle: Text(e.positionTitle ?? '-'),
                              onChanged: (v) => setState(() {
                                if (v ?? false) {
                                  _selected.add(e.id);
                                } else {
                                  _selected.remove(e.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () {
            if (widget.requireOne && _selected.isEmpty) {
              AppDialogs.warn(context, 'กรุณาเลือกพนักงานซ่อมอย่างน้อย 1 คน');
              return;
            }
            Navigator.of(context).pop(_selected.toList());
          },
          child: Text('${widget.confirmLabel} (${_selected.length})'),
        ),
      ],
    );
  }
}
