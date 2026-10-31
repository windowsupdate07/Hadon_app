import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import 'repair_models.dart';
import 'repairs_api.dart';
import 'widgets/attendees_section.dart';
import 'widgets/car_photos_section.dart';
import 'widgets/invoice_link_card.dart';
import 'widgets/repair_header_card.dart';
import 'widgets/repair_items_section.dart';
import 'widgets/work_status_sheet.dart';

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
    });
    try {
      await future;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _changeStatus(Repair repair) async {
    final status = await showWorkStatusSheet(context, repair.workStatusId);
    if (status == null || status == repair.workStatusId || !mounted) {
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการเปลี่ยนสถานะ?',
      message:
          'เปลี่ยนสถานะจาก "${WorkStatus.info(repair.workStatusId).label}" '
          'เป็น "${WorkStatus.info(status).label}" ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.updateWorkStatus(repair.id, status);
      return true;
    }, successMessage: 'เปลี่ยนสถานะเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final canManage = employee?.canManage ?? false;

    return FutureBuilder<Repair>(
      future: _future,
      builder: (context, snap) {
        final repair = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text('งานซ่อม #${widget.repairId}'),
            actions: [
              if (repair != null)
                IconButton(
                  tooltip: 'เปลี่ยนสถานะ',
                  onPressed: () => _changeStatus(repair),
                  icon: const Icon(Icons.swap_horiz),
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
    if (snap.connectionState != ConnectionState.done) {
      return const LoadingView();
    }
    if (snap.hasError) {
      return ErrorView(error: snap.error!, onRetry: _refresh);
    }
    final repair = snap.data!;
    final editable =
        repair.workStatusId != WorkStatus.success &&
        repair.workStatusId != WorkStatus.cancel;
    final g = _generation;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          RepairHeaderCard(
            repair: repair,
            onChangeStatus: () => _changeStatus(repair),
          ),
          if (!editable)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'งานซ่อมนี้ปิดแล้ว ไม่สามารถแก้ไขรายการซ่อมได้',
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
          ),
          AttendeesSection(
            key: ValueKey('attendees-$g'),
            api: _api,
            repairId: repair.id,
            editable: editable,
          ),
          CarPhotosSection(
            key: ValueKey('photos-$g'),
            api: _api,
            repairId: repair.id,
          ),
        ],
      ),
    );
  }
}
