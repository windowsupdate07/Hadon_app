import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import 'repair_models.dart';
import 'repairs_api.dart';
import 'widgets/attendees_section.dart';
import 'widgets/cancel_repair_dialog.dart';
import 'widgets/car_photos_section.dart';
import 'widgets/invoice_link_card.dart';
import 'widgets/receive_type_dialog.dart';
import 'widgets/repair_header_card.dart';
import 'widgets/repair_items_section.dart';
import 'widgets/repair_timeline.dart';

/// Repair job detail. Status changes follow the web's workflow buttons
/// (pages/system/repairs/** + components/repair/**) instead of a free-form
/// status picker, because the backend attaches side effects to specific
/// transitions (e.g. -> 5 sets AllocatedNum, cancel returns stock).
class RepairDetailPage extends StatefulWidget {
  const RepairDetailPage({super.key, required this.repairId});

  final int repairId;

  @override
  State<RepairDetailPage> createState() => _RepairDetailPageState();
}

class _RepairDetailPageState extends State<RepairDetailPage> {
  late final RepairsApi _api;
  late Future<Repair> _future;

  /// Bumped on refresh so every section re-creates its state and reloads.
  int _generation = 0;

  /// Latest items reported by [RepairItemsSection] (null while loading).
  List<RepairItem>? _items;

  @override
  void initState() {
    super.initState();
    _api = RepairsApi(context.read<ApiClient>());
    _future = _api.findOne(widget.repairId);
  }

  Future<void> _refresh() async {
    final future = _api.findOne(widget.repairId);
    setState(() {
      _future = future;
      _generation++;
      _items = null;
    });
    try {
      await future;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  void _onItemsLoaded(List<RepairItem> items) {
    if (mounted) {
      setState(() => _items = items);
    }
  }

  // ----------------------------------------------------------- rules (web)

  static bool _isEditable(int? s) =>
      s != WorkStatus.repaired &&
      s != WorkStatus.success &&
      s != WorkStatus.cancel;

  /// Web: RepairHeader shows "ยกเลิกการซ่อม" unless 6 or 99, and the edit
  /// page holding it is only reachable when not 6 / 7 / 99.
  static bool _canCancel(int? s) => _isEditable(s);

  /// Web: "ยกเลิกการซ่อมเสร็จสิ้น" when status >= 6, not 9 and not 99.
  static bool _canUndoFinish(int? s) =>
      s != null &&
      s >= WorkStatus.repaired &&
      s != WorkStatus.allocateMore &&
      s != WorkStatus.cancel;

  bool get _hasItems => _items?.isNotEmpty ?? false;

  /// Parts changed since the allocation (NumOfUse != AllocatedNum).
  bool get _hasAllocationChanges =>
      _items?.any((i) => i.parts.any((p) => p.allocationDiff != 0)) ?? false;

  // --------------------------------------------------------------- actions

  Future<void> _setStatus(
    Repair repair,
    int status, {
    required String message,
    required String success,
  }) async {
    final ok = await AppDialogs.confirm(context, message: message);
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.updateWorkStatus(repair.id, status);
      return true;
    }, successMessage: success);
    if (done == true && mounted) {
      await _refresh();
    }
  }

  /// 1 -> 2. On the web this happens when the checker presses "บันทึกข้อมูล".
  Future<void> _confirmChecked(Repair r) => _setStatus(
    r,
    WorkStatus.checked,
    message: 'ยืนยันว่าตรวจสอบรถและบันทึกรายการซ่อมเรียบร้อยแล้ว ใช่หรือไม่?',
    success: 'เปลี่ยนสถานะเป็น "ตรวจสอบรถแล้ว" เรียบร้อยแล้ว',
  );

  /// 2 -> 4.
  Future<void> _allocate(Repair r) => _setStatus(
    r,
    WorkStatus.allocating,
    message: 'ท่านต้องการจัดสรรอุปกรณ์ ใช่หรือไม่?',
    success: 'เปลี่ยนสถานะเป็นรอจัดสรรอุปกรณ์แล้ว',
  );

  /// 4 -> 2.
  Future<void> _cancelAllocate(Repair r) => _setStatus(
    r,
    WorkStatus.checked,
    message: 'ยกเลิกการจัดสรรอุปกรณ์ ใช่หรือไม่?',
    success: 'ยกเลิกการจัดสรรอุปกรณ์แล้ว',
  );

  /// 5 -> 9. Part edits are saved immediately in the app, so only the
  /// status change is needed.
  Future<void> _requestMore(Repair r) => _setStatus(
    r,
    WorkStatus.allocateMore,
    message:
        'ยืนยันขอจัดสรรอุปกรณ์เพิ่มเติม?\n'
        'ระบบจะแจ้งฝ่ายจัดสรรอุปกรณ์ถึงรายการที่เปลี่ยนแปลง',
    success: 'ส่งคำขอจัดสรรอุปกรณ์เพิ่มเติมเรียบร้อยแล้ว',
  );

  /// 5 -> 6: choose the technicians (at least one), save them, finish.
  Future<void> _finish(Repair r) async {
    final ids = await showAttendeePicker(
      context,
      api: _api,
      selected: r.attendees.map((e) => e.id).toSet(),
      requireOne: true,
      confirmLabel: 'ยืนยัน',
    );
    if (ids == null || !mounted) {
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการบันทึก?',
      message: 'ระบบจะบันทึกรายชื่อผู้ซ่อม และเปลี่ยนสถานะเป็น "ซ่อมเสร็จแล้ว"',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.setAttendees(r.id, ids);
      await _api.updateWorkStatus(r.id, WorkStatus.repaired);
      return true;
    }, successMessage: 'บันทึกข้อมูลและเปลี่ยนสถานะเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  /// 6/7/8 -> 5, blocked once the invoice is confirmed (status 2/3) or an
  /// active receipt (RecieptStatusID 1) exists.
  Future<void> _undoFinish(Repair r) async {
    final check = await runWithProgress(context, () async {
      final results = await Future.wait([
        _api.invoice(r.id),
        _api.receiptStatuses(r.id),
      ]);
      return (results[0] as RepairInvoice?, results[1] as List<int?>);
    });
    if (check == null || !mounted) {
      return;
    }
    final (invoice, receipts) = check;
    final invoiceBlock =
        invoice != null &&
        (invoice.statusId ?? 0) > InvoiceStatus.pendingConfirm &&
        invoice.statusId != InvoiceStatus.cancelled;
    final receiptBlock = receipts.contains(1);
    if (invoiceBlock || receiptBlock) {
      await AppDialogs.warn(
        context,
        'ไม่สามารถยกเลิกสถานะซ่อมเสร็จได้เนื่องจาก:\n'
        '${invoiceBlock ? '- ใบแจ้งหนี้ได้รับการยืนยันแล้ว\n' : ''}'
        '${receiptBlock ? '- มีการออกใบเสร็จรับเงินแล้ว\n' : ''}',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await _setStatus(
      r,
      WorkStatus.repairing,
      message:
          'ยกเลิกการซ่อมเสร็จสิ้น และกลับไปสถานะ "อยู่ระหว่างซ่อม" ใช่หรือไม่?',
      success: 'เปลี่ยนสถานะการซ่อมแล้ว',
    );
  }

  Future<void> _cancelRepair(Repair r) async {
    final reason = await askCancelRepairReason(context, r.id);
    if (reason == null || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.cancel(r.id, reason);
      return true;
    }, successMessage: 'ยกเลิกงานซ่อมเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _editReceiveType(Repair r) async {
    final result = await showReceiveTypeDialog(context, r);
    if (result == null || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.updateReceiveType(
        r.id,
        result.receiveType,
        result.appointment,
      );
      return true;
    }, successMessage: 'อัปเดตข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  void _openTimeline() {
    openRepairTimeline(context, api: _api, repairId: widget.repairId);
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final canManage = employee?.canManage ?? false;

    return FutureBuilder<Repair>(
      future: _future,
      builder: (context, snap) {
        return Scaffold(
          appBar: AppBar(
            title: Text('งานซ่อม #${widget.repairId}'),
            actions: [
              IconButton(
                tooltip: 'Timeline ดำเนินการ',
                onPressed: _openTimeline,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'รีเฟรช',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _body(snap, canManage),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<Repair> snap, bool canManage) {
    // Keep showing the previous data while a refresh is in flight.
    if (!snap.hasData) {
      if (snap.connectionState != ConnectionState.done) {
        return const LoadingView();
      }
      if (snap.hasError) {
        return ErrorView(error: snap.error!, onRetry: _refresh);
      }
    }
    final repair = snap.data!;
    final status = repair.workStatusId;
    final editable = _isEditable(status);
    final g = _generation;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (status == WorkStatus.cancel) _cancelledBanner(),
          RepairHeaderCard(
            repair: repair,
            onTapStatus: _openTimeline,
            onEditReceiveType: status == WorkStatus.cancel
                ? null
                : () => _editReceiveType(repair),
          ),
          _actionsCard(repair),
          if (!editable && status != WorkStatus.cancel)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'งานซ่อมนี้ซ่อมเสร็จแล้ว ไม่สามารถแก้ไขรายการซ่อมได้',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          InvoiceLinkCard(
            key: ValueKey('invoice-$g'),
            api: _api,
            repairId: repair.id,
          ),
          RepairItemsSection(
            key: ValueKey('items-$g'),
            api: _api,
            repair: repair,
            editable: editable,
            canDelete: canManage,
            onLoaded: _onItemsLoaded,
            onChanged: _refresh,
          ),
          AttendeesSection(
            key: ValueKey('attendees-$g'),
            api: _api,
            repairId: repair.id,
            editable: editable,
            onChanged: _refresh,
          ),
          RepairTimelineSection(
            key: ValueKey('timeline-$g'),
            api: _api,
            repairId: repair.id,
          ),
          CarPhotosSection(
            key: ValueKey('photos-$g'),
            api: _api,
            quotationId: repair.quotationId,
            editable: editable,
          ),
        ],
      ),
    );
  }

  Widget _cancelledBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.block, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'งานซ่อมนี้ถูกยกเลิกแล้ว (ดูเหตุผลใน Timeline)',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Workflow buttons per status, mirroring RepairActions.vue and the web
  /// detail page. Allocation itself (4 -> 5, 9 -> 5) is done by the
  /// allocation team on the web's /system/monitoring page.
  Widget _actionsCard(Repair r) {
    final s = r.workStatusId;
    final buttons = <Widget>[];
    String? note;

    if (s == WorkStatus.checking) {
      buttons.add(
        FilledButton.icon(
          onPressed: _hasItems ? () => _confirmChecked(r) : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('ยืนยันตรวจสอบรถแล้ว'),
        ),
      );
      if (_items != null && !_hasItems) {
        note = 'เพิ่มรายการซ่อมอย่างน้อย 1 รายการก่อนยืนยัน';
      }
    }
    if (s == WorkStatus.checked) {
      buttons.add(
        FilledButton.icon(
          onPressed: _hasItems ? () => _allocate(r) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('จัดสรรอุปกรณ์'),
        ),
      );
    }
    if (s == WorkStatus.allocating) {
      note = 'รอฝ่ายจัดสรรอุปกรณ์ดำเนินการ';
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _cancelAllocate(r),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.undo),
          label: const Text('ยกเลิกการจัดสรรอุปกรณ์'),
        ),
      );
    }
    if (s == WorkStatus.repairing) {
      buttons
        ..add(
          FilledButton.icon(
            onPressed: () => _finish(r),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            icon: const Icon(Icons.check),
            label: const Text('ยืนยันการซ่อมแล้วเสร็จ'),
          ),
        )
        ..add(
          OutlinedButton.icon(
            onPressed: _hasAllocationChanges ? () => _requestMore(r) : null,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('ขอจัดสรรอุปกรณ์เพิ่มเติม'),
          ),
        );
      if (_items != null && !_hasAllocationChanges) {
        note = 'แก้ไขจำนวน / เพิ่มอะไหล่ก่อน จึงจะขอจัดสรรอุปกรณ์เพิ่มเติมได้';
      }
    }
    if (s == WorkStatus.allocateMore) {
      note = 'รอฝ่ายจัดสรรอุปกรณ์จัดสรรรายการที่เปลี่ยนแปลง';
    }
    if (_canUndoFinish(s)) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _undoFinish(r),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange[800]),
          icon: const Icon(Icons.undo),
          label: const Text('ยกเลิกการซ่อมเสร็จสิ้น'),
        ),
      );
    }
    if (_canCancel(s)) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _cancelRepair(r),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('ยกเลิกการซ่อม'),
        ),
      );
    }

    if (buttons.isEmpty && note == null) {
      return const SizedBox.shrink();
    }
    return SectionCard(
      title: 'การดำเนินการ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(note, style: const TextStyle(color: Colors.grey)),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ],
      ),
    );
  }
}
