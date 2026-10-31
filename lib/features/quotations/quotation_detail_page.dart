import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../invoices/invoice_models.dart';
import 'quotation_models.dart';
import 'quotations_api.dart';
import 'totals.dart';
import 'widgets/add_item_page.dart';
import 'widgets/car_picker.dart';
import 'widgets/cash_pledge_dialog.dart';
import 'widgets/part_line_dialog.dart';
import 'widgets/quotation_dialogs.dart';
import 'widgets/quotation_form_dialog.dart';
import 'widgets/quotation_photos_section.dart';
import 'widgets/totals_card.dart';

class _DetailData {
  const _DetailData({
    required this.quotation,
    required this.details,
    required this.pledges,
    this.invoices,
    this.receipts,
  });

  final Quotation quotation;
  final List<QuotationDetail> details;
  final List<CashPledge> pledges;

  /// `GET /invoices/by-quotation-id/:id`; null when it failed to load.
  final List<Invoice>? invoices;

  /// `GET /receipts/by-quotation-id/:id`; null when it failed to load.
  final List<QuotationReceipt>? receipts;

  DocumentTotals get totals => quotationTotals(
    quotation,
    details,
    cashPledges: pledges.map((p) => p.amount),
  );

  /// Web `isCanEdit == false`: a repair was opened from the quotation.
  bool get locked => quotation.isApproved;

  /// Web `isCancelledRepair`.
  bool get cancelled => quotation.isCancelledRepair;

  /// Active (not cancelled) deposit invoice created with the pledge.
  Invoice? get depositInvoice {
    for (final inv in invoices ?? const <Invoice>[]) {
      if (inv.isDeposit && inv.statusId != InvoiceStatus.cancelled) {
        return inv;
      }
    }
    return null;
  }

  /// A PAID receipt exists (repair receipts from the quotation include, or
  /// any receipt of the quotation incl. deposit receipts).
  bool get hasPaidReceipt =>
      quotation.hasPaidRepairReceipt ||
      (receipts ?? const []).any((r) => r.isPaid);

  /// A repair invoice was already confirmed/paid with the pledge deducted.
  bool get repairInvoiceSettled => (invoices ?? const <Invoice>[]).any(
    (i) =>
        !i.isDeposit &&
        (i.statusId == InvoiceStatus.pendingPayment ||
            i.statusId == InvoiceStatus.paid),
  );

  List<QuotationPart> get parts => details.expand((d) => d.parts).toList();

  // ---- Rules mirrored from the web quotation page ----

  bool get canEditItems => !locked && !cancelled;

  /// The web only lets the service fee be edited while no deposit invoice
  /// exists (the pledge was computed from the totals).
  bool get canEditPartValues => canEditItems && depositInvoice == null;

  bool get canDeleteParts => canEditItems && !hasPaidReceipt;

  bool get canChangeVat => canEditItems && pledges.isEmpty;

  bool get canAddPledge =>
      details.isNotEmpty &&
      pledges.isEmpty &&
      !hasPaidReceipt &&
      !cancelled &&
      totals.grandTotal > 0;

  bool get canRemovePledge =>
      pledges.isNotEmpty &&
      !hasPaidReceipt &&
      !cancelled &&
      !repairInvoiceSettled &&
      invoices != null &&
      receipts != null &&
      (depositInvoice == null ||
          depositInvoice!.statusId == InvoiceStatus.pendingConfirm ||
          depositInvoice!.statusId == InvoiceStatus.pendingPayment);

  bool get canDelete => pledges.isEmpty && !locked && !cancelled;

  bool get canPrint => details.isNotEmpty && !cancelled;
}

class QuotationDetailPage extends StatefulWidget {
  const QuotationDetailPage({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuotationDetailPage> createState() => _QuotationDetailPageState();
}

class _QuotationDetailPageState extends State<QuotationDetailPage> {
  late final QuotationsApi _api = QuotationsApi(context.read<ApiClient>());
  final _photosKey = GlobalKey<QuotationPhotosSectionState>();
  late Future<_DetailData> _future;
  _DetailData? _data;
  List<QuotationImage>? _images;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final id = widget.quotationId;
    Future<T?> soft<T>(Future<T> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      _api.findOne(id),
      _api.details(id),
      _api.cashPledges(id),
      soft(_api.invoicesOf(id)),
      soft(_api.receiptsOf(id)),
    ]);
    final data = _DetailData(
      quotation: results[0]! as Quotation,
      details: results[1]! as List<QuotationDetail>,
      pledges: results[2]! as List<CashPledge>,
      invoices: results[3] as List<Invoice>?,
      receipts: results[4] as List<QuotationReceipt>?,
    );
    if (mounted) {
      // The app bar menus and bottom bar depend on the loaded data.
      setState(() => _data = data);
    }
    return data;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _future = f;
    });
    _photosKey.currentState?.reload();
    try {
      await f;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  /// Runs [action] with a progress dialog and reloads on success.
  Future<bool> _mutate(Future<void> Function() action, {String? toast}) async {
    final ok = await runWithProgress(context, () async {
      await action();
      return true;
    }, successMessage: toast);
    if (ok == true && mounted) {
      await _refresh();
      return true;
    }
    return false;
  }

  void _openInvoice(String id) async {
    await context.push('/invoices/${Uri.encodeComponent(id)}');
    if (mounted) {
      _refresh();
    }
  }

  // ---- Header ----

  Future<void> _editComment(Quotation q) async {
    final text = await showEditCommentDialog(context, q.comment);
    if (text == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.update(q.id, {'Comment': text}),
      toast: 'บันทึกหมายเหตุแล้ว',
    );
  }

  Future<void> _editVehicle(Quotation q) async {
    final v = await showEditVehicleDialog(context, q);
    if (v == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.updateVehicle(q.id, v),
      toast: 'บันทึกข้อมูลรถยนต์แล้ว',
    );
  }

  Future<void> _setVat(Quotation q, bool isVat, int vatType) {
    return _mutate(() => _api.setVat(q.id, isVat: isVat, vatType: vatType));
  }

  Future<void> _deleteQuotation(Quotation q) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการยกเลิกใบเสนอราคา?',
      message:
          'คุณต้องการยกเลิกใบเสนอราคา ${q.id} ใช่หรือไม่?\n'
          'ข้อมูลจะถูกลบออกจากระบบ',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(q.id);
      return true;
    });
    if (done == true && mounted) {
      AppDialogs.toast(context, 'ยกเลิกใบเสนอราคาแล้ว');
      context.pop();
    }
  }

  // ---- Copy ----

  Future<void> _copy(_DetailData d) async {
    final req = await showCopyQuotationDialog(context, details: d.details);
    if (req == null || !mounted) {
      return;
    }
    String? newId;
    if (req.useExisting) {
      final ok = await AppDialogs.confirm(
        context,
        title: 'ยืนยันการคัดลอก?',
        message:
            'คุณต้องการคัดลอกรายการไปยังใบเสนอราคาใหม่ '
            'โดยใช้ข้อมูลรถยนต์เดิมใช่หรือไม่?',
      );
      if (!ok || !mounted) {
        return;
      }
      newId = await runWithProgress(
        context,
        () => _api.copy(
          sourceQuotationId: d.quotation.id,
          detailIds: req.detailIds,
        ),
      );
    } else {
      final input = await openCreateQuotationForm(
        context,
        api: _api,
        title: 'สร้างใบเสนอราคาใหม่ (คัดลอก)',
        defaultComment: d.quotation.comment,
      );
      if (input == null || !mounted) {
        return;
      }
      newId = await runWithProgress(context, () async {
        final target = await _api.create(input);
        return _api.copy(
          sourceQuotationId: d.quotation.id,
          targetQuotationId: target,
          detailIds: req.detailIds,
        );
      });
    }
    if (newId == null || !mounted) {
      return;
    }
    AppDialogs.toast(context, 'คัดลอกใบเสนอราคาเรียบร้อยแล้ว');
    await context.push('/quotations/${Uri.encodeComponent(newId)}');
    if (mounted) {
      _refresh();
    }
  }

  // ---- Items ----

  Future<void> _addItem(Quotation q) async {
    final saved = await openAddQuotationItem(context, api: _api, quotation: q);
    if (saved && mounted) {
      AppDialogs.toast(context, 'เพิ่มรายการแล้ว');
      await _refresh();
    }
  }

  Future<void> _deleteItem(QuotationDetail d) async {
    final ok = await AppDialogs.confirmDelete(context, 'รายการ ${d.title}');
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() => _api.deleteDetail(d.id), toast: 'ลบรายการแล้ว');
  }

  Future<void> _editPart(QuotationPart p) async {
    final v = await showPartLineDialog(
      context,
      title: p.name,
      initial: PartLineValues(
        quantity: p.quantity,
        pricePerUnit: p.pricePerUnit,
        serviceFee: p.serviceFee,
      ),
    );
    if (v == null || !mounted) {
      return;
    }
    await _mutate(() => _api.updatePart(p.id, v.toJson()), toast: 'บันทึกแล้ว');
  }

  Future<void> _deletePart(QuotationPart p) async {
    final ok = await AppDialogs.confirmDelete(context, 'อะไหล่ ${p.name}');
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() => _api.deletePart(p.id), toast: 'ลบอะไหล่แล้ว');
  }

  // ---- Cash pledge ----

  Future<void> _addPledge(_DetailData d) async {
    final amount = await showCashPledgeDialog(context, totals: d.totals);
    if (amount == null || !mounted) {
      return;
    }
    final invoiceId = await runWithProgress(
      context,
      () async =>
          await _api.addCashPledge(
            quotationId: d.quotation.id,
            amount: amount,
          ) ??
          '',
    );
    if (invoiceId == null || !mounted) {
      return;
    }
    await _refresh();
    if (!mounted || invoiceId.isEmpty) {
      return;
    }
    final go = await AppDialogs.confirm(
      context,
      title: 'บันทึกข้อมูลสำเร็จ',
      message: 'ท่านต้องการไปยังหน้าใบแจ้งหนี้สำหรับรายการมัดจำนี้หรือไม่?',
    );
    if (go && mounted) {
      _openInvoice(invoiceId);
    }
  }

  /// The web removes a pledge by cancelling its deposit invoice (status
  /// 99), which makes the server delete the quotation's pledges. Legacy
  /// pledges without a deposit invoice are deleted directly.
  Future<void> _removePledge(_DetailData d) async {
    final dep = d.depositInvoice;
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยกเลิกเงินมัดจำ?',
      message: dep == null
          ? 'ท่านต้องการลบเงินมัดจำ ใช่หรือไม่?'
          : 'ระบบจะยกเลิกใบแจ้งหนี้ (เงินมัดจำ) ${dep.id} '
                'และลบเงินมัดจำของใบเสนอราคานี้ ใช่หรือไม่?',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() async {
      if (dep != null) {
        await _api.invoices.changeStatus(
          dep.id,
          InvoiceStatus.cancelled,
          netTotal:
              dep.amount ?? d.pledges.fold<double>(0, (a, p) => a + p.amount),
        );
      } else {
        for (final p in d.pledges) {
          await _api.deleteCashPledge(p.id);
        }
      }
    }, toast: 'ยกเลิกเงินมัดจำแล้ว');
  }

  // ---- Send to repair ----

  Future<void> _sendToRepair(_DetailData d) async {
    var q = d.quotation;
    if (d.details.isEmpty) {
      await AppDialogs.warn(context, 'กรุณาเพิ่มรายการชุดอุปกรณ์ก่อนส่งซ่อม');
      return;
    }

    // The server deducts stock for every part and rolls back when any part
    // is short, so check up-front for a clear message.
    final need = <int, int>{};
    final byId = <int, QuotationPart>{};
    for (final p in d.parts) {
      need[p.partId] = (need[p.partId] ?? 0) + p.quantity;
      byId[p.partId] = p;
    }
    final short = <String>[];
    need.forEach((partId, qty) {
      final part = byId[partId]!.part;
      if (part != null && part.amount < qty) {
        short.add(
          '• ${part.displayName}: ต้องการ $qty คงเหลือ ${formatNumber(part.amount)}',
        );
      }
    });
    if (short.isNotEmpty) {
      await AppDialogs.warn(
        context,
        'สินค้าคงคลังไม่เพียงพอ ไม่สามารถส่งซ่อมได้\n\n${short.join('\n')}',
      );
      return;
    }

    // Quotations made by the old backend have no car/customer yet.
    var carId = q.carId;
    var customerId = q.customerId;
    if (carId == null || customerId == null) {
      final car = await showCarPicker(context, api: _api, modelId: q.modelId);
      if (car == null || !mounted) {
        return;
      }
      if (car.customerId == null) {
        await AppDialogs.warn(context, 'รถยนต์คันนี้ไม่มีข้อมูลเจ้าของ');
        return;
      }
      carId = car.id;
      customerId = car.customerId;
      final saved = await runWithProgress(context, () async {
        await _api.update(q.id, {'CarID': carId, 'CustomerID': customerId});
        return _api.findOne(q.id);
      });
      if (saved == null || !mounted) {
        return;
      }
      q = saved;
    }
    final brandId = q.brandId;
    final modelId = q.modelId;
    if (brandId == null || modelId == null) {
      await AppDialogs.warn(
        context,
        'ข้อมูลใบเสนอราคาไม่ครบถ้วน (ยี่ห้อ/รุ่น)',
      );
      return;
    }

    // Web: warn when the 8 standard car photos are not all uploaded.
    final images = _images ?? await _tryImages(q.id);
    if (!mounted) {
      return;
    }
    if (images != null) {
      final missing = requiredImageTypeIds
          .where((id) => !images.any((i) => i.typeId == id))
          .length;
      if (missing > 0) {
        final go = await AppDialogs.confirm(
          context,
          title: 'แจ้งเตือนรูปภาพรถยนต์',
          message:
              'ยังไม่ได้แนบรูปรถยนต์ครบทั้ง 8 ภาพ (ขาด $missing ภาพ)\n'
              'ต้องการส่งซ่อมต่อไปโดยไม่อัปโหลดรูปภาพหรือไม่?',
        );
        if (!go || !mounted) {
          return;
        }
      }
    }

    final receive = await showReceiveTypeDialog(context);
    if (receive == null || !mounted) {
      return;
    }
    final t = d.totals;
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการเปิดใบสั่งซ่อม?',
      message:
          'ระบบจะสร้างงานซ่อมและใบแจ้งหนี้ พร้อมตัดสต็อกอะไหล่\n\n'
          'ลูกค้า: ${q.customerDisplayName.isEmpty ? 'ไม่ระบุ' : q.customerDisplayName}\n'
          'รถยนต์: ${q.brandModel}\n'
          'ทะเบียน: ${q.plate.isEmpty ? 'ไม่ระบุ' : q.plate}\n'
          'รูปแบบรับรถ: ${receive.label}\n'
          'รายการ: ${d.details.length} ชุด\n'
          'รูปแบบภาษี: ${t.isVat ? VatType.label(t.vatType) : 'ไม่คิดภาษี'}\n'
          'ยอดรวมสุทธิ: ${formatMoney(t.grandTotal)} บาท',
    );
    if (!ok || !mounted) {
      return;
    }
    final result = await runWithProgress(
      context,
      () => _api.approve(
        quotationId: q.id,
        brandId: brandId,
        modelId: modelId,
        carId: carId!,
        customerId: customerId!,
        receiveType: receive.type,
        appointment: receive.appointment,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    AppDialogs.toast(context, 'เปิดใบสั่งซ่อมเรียบร้อยแล้ว');
    await _refresh();
    if (!mounted) {
      return;
    }
    if (result.repairId != null) {
      context.push('/repairs/${result.repairId}');
    } else if (result.invoiceId != null) {
      _openInvoice(result.invoiceId!);
    }
  }

  Future<List<QuotationImage>?> _tryImages(String id) async {
    try {
      return await _api.images(id);
    } catch (_) {
      return null;
    }
  }

  // ---- PDF ----

  Future<void> _pdf(_DetailData d, {required bool grouped}) async {
    if (d.quotation.customerId == null) {
      await AppDialogs.warn(
        context,
        'ใบเสนอราคานี้ยังไม่ระบุลูกค้า จึงไม่สามารถสร้าง PDF ได้',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await openQuotationPdf(
      context,
      quotationId: d.quotation.id,
      grouped: grouped,
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quotationId),
        actions: [
          IconButton(
            tooltip: 'ประวัติการดำเนินการ',
            icon: const Icon(Icons.history),
            onPressed: () => showQuotationTimeline(
              context,
              api: _api,
              quotationId: widget.quotationId,
            ),
          ),
          if (data != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'pdf':
                    _pdf(data, grouped: false);
                  case 'pdf-group':
                    _pdf(data, grouped: true);
                  case 'copy':
                    _copy(data);
                  case 'delete':
                    _deleteQuotation(data.quotation);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pdf',
                  enabled: data.canPrint,
                  child: const ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('ใบเสนอราคาแบบรายการ (PDF)'),
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf-group',
                  enabled: data.canPrint,
                  child: const ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('ใบเสนอราคาแบบจัดกลุ่ม (PDF)'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.content_copy),
                    title: Text('คัดลอกใบเสนอราคา'),
                  ),
                ),
                if (canManage && data.canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('ยกเลิกใบเสนอราคา'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: AsyncBody<_DetailData>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, d) => _body(d, canManage),
      ),
      bottomNavigationBar: data == null ? null : _bottomBar(data),
    );
  }

  Widget? _bottomBar(_DetailData d) {
    if (d.cancelled) {
      return null;
    }
    if (d.locked) {
      final repair = d.quotation.repairs.first;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => context.push('/repairs/${repair.id}'),
            icon: const Icon(Icons.car_repair),
            label: Text('ดูงานซ่อม #${repair.id}'),
          ),
        ),
      );
    }
    final short = d.parts.any((p) => p.isShort);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: d.details.isEmpty ? null : () => _sendToRepair(d),
          icon: const Icon(Icons.build_circle_outlined),
          label: Text(
            short ? 'ส่งซ่อม (อะไหล่ไม่พอ)' : 'ส่งซ่อม / เปิดใบสั่งซ่อม',
          ),
        ),
      ),
    );
  }

  Widget _body(_DetailData d, bool canManage) {
    final q = d.quotation;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (d.cancelled)
          _banner(
            Colors.red,
            Icons.block,
            'งานซ่อมของใบเสนอราคานี้ถูกยกเลิกแล้ว',
          ),
        if (d.locked && !d.cancelled)
          _banner(
            Colors.green,
            Icons.verified,
            'ส่งซ่อมแล้ว — แก้ไขรายการในใบเสนอราคาไม่ได้',
          ),
        SectionCard(
          title: 'ข้อมูลใบเสนอราคา',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow('เลขที่', q.id, bold: true),
              InfoRow('วันที่', formatThaiDateTime(q.date)),
              InfoRow('ผู้เสนอราคา', q.employeeName),
              InfoRow('สถานะ', q.stage.label),
              const Divider(),
              InfoRow('ลูกค้า', q.customerDisplayName),
              InfoRow('เบอร์โทรศัพท์', q.customerTel),
              InfoRow('ที่อยู่', addressText(q.address)),
            ],
          ),
        ),
        _vehicleCard(d),
        QuotationPhotosSection(
          key: _photosKey,
          api: _api,
          quotationId: q.id,
          editable: d.canEditItems,
          onChanged: (list) => _images = list,
        ),
        _itemsCard(d),
        TotalsCard(
          totals: d.totals,
          vatControls: VatControls(
            isVat: q.isVat,
            vatType: q.vatType,
            onChanged: d.canChangeVat ? (v, t) => _setVat(q, v, t) : null,
            disabledReason: d.cancelled || d.locked || d.pledges.isNotEmpty
                ? '(ไม่สามารถแก้ไขการตั้งค่าภาษีได้ เนื่องจากมีการวางมัดจำหรือส่งซ่อมแล้ว)'
                : null,
          ),
        ),
        _pledgeCard(d, canManage),
        _documentsCard(d),
        SectionCard(
          title: 'หมายเหตุ',
          trailing: d.cancelled
              ? null
              : IconButton(
                  tooltip: 'แก้ไขหมายเหตุ',
                  icon: const Icon(Icons.edit_note),
                  onPressed: () => _editComment(q),
                ),
          child: Text(
            (q.comment ?? '').isEmpty ? '-' : q.comment!,
            style: (q.comment ?? '').isEmpty
                ? const TextStyle(color: Colors.grey)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _banner(Color color, IconData icon, String text) {
    return Card(
      color: color.withValues(alpha: 0.08),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleCard(_DetailData d) {
    final q = d.quotation;
    return SectionCard(
      title: 'ข้อมูลรถยนต์',
      trailing: d.canEditItems
          ? IconButton(
              tooltip: 'แก้ไขข้อมูลรถยนต์',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editVehicle(q),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('ยี่ห้อ / รุ่น', q.brandModel),
          InfoRow('ทะเบียน', q.plate),
          InfoRow('สีรถยนต์', q.car?['Color']?.toString()),
          InfoRow(
            'เลขไมล์ (กม.)',
            q.mileage == null ? null : formatNumber(q.mileage),
          ),
          InfoRow('การติดตั้งแก๊ส', q.gasText),
          InfoRow('ประเภทลมยาง', q.tireText),
          InfoRow(
            'ป้ายภาษีหมดอายุ',
            q.taxDate == null ? 'ไม่ระบุป้ายภาษี' : formatThaiDate(q.taxDate),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(_DetailData d) {
    return SectionCard(
      title: 'รายการซ่อม (${d.details.length})',
      trailing: d.canEditItems
          ? TextButton.icon(
              onPressed: () => _addItem(d.quotation),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มรายการ'),
            )
          : null,
      child: d.details.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ยังไม่มีรายการซ่อม',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < d.details.length; i++)
                  _detailBlock(i + 1, d.details[i], d),
              ],
            ),
    );
  }

  Widget _detailBlock(int no, QuotationDetail detail, _DetailData d) {
    final theme = Theme.of(context);
    final copied = detail.copiedToQuotationId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text(
              '$no. ${detail.title}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('ประเภท: ${detail.repairCategory ?? '-'}'),
            trailing: d.canEditItems
                ? IconButton(
                    tooltip: 'ลบรายการ',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteItem(detail),
                  )
                : null,
          ),
          if (copied != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.content_copy, size: 16),
                  label: Text('คัดลอกไป $copied แล้ว'),
                  onPressed: () => context.push(
                    '/quotations/${Uri.encodeComponent(copied)}',
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          if (detail.parts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ไม่มีอะไหล่', style: TextStyle(color: Colors.grey)),
            ),
          for (final p in detail.parts) _partTile(p, d),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                if (d.canEditPartValues || d.canDeleteParts)
                  Expanded(
                    child: Text(
                      [
                        if (d.canEditPartValues) 'แตะเพื่อแก้ไข',
                        if (d.canDeleteParts) 'กดค้างเพื่อลบ',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  'รวม ${formatMoney(detail.total)} บาท',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _partTile(QuotationPart p, _DetailData d) {
    // Stock shortage only matters before the repair is opened (web
    // setRowColor).
    final short = !d.locked && p.isShort;
    return Container(
      color: short ? Colors.red.withValues(alpha: 0.08) : null,
      child: ListTile(
        dense: true,
        title: Text(p.name),
        subtitle: Text(
          '${p.quantity} ${p.part?.unitName ?? ''} × '
          '${formatMoney(p.pricePerUnit)}'
          ' + ค่าบริการ ${formatMoney(p.serviceFee)}'
          '${short ? '\nคงเหลือในคลัง ${formatNumber(p.part?.amount)} — ไม่เพียงพอ' : ''}',
          style: short ? const TextStyle(color: Colors.red) : null,
        ),
        trailing: Text(
          formatMoney(p.total),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: d.canEditPartValues ? () => _editPart(p) : null,
        onLongPress: d.canDeleteParts ? () => _deletePart(p) : null,
      ),
    );
  }

  Widget _pledgeCard(_DetailData d, bool canManage) {
    final dep = d.depositInvoice;
    final canRemove = canManage && d.canRemovePledge;
    return SectionCard(
      title: 'เงินมัดจำ',
      trailing: d.canAddPledge
          ? TextButton.icon(
              onPressed: () => _addPledge(d),
              icon: const Icon(Icons.add),
              label: const Text('วางมัดจำ'),
            )
          : null,
      child: d.pledges.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'ไม่มีเงินมัดจำ',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in d.pledges)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.savings_outlined),
                    title: Text(p.title),
                    trailing: Text('${formatMoney(p.amount)} บาท'),
                  ),
                if (dep != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('ใบแจ้งหนี้ (เงินมัดจำ) ${dep.id}'),
                    subtitle: Text(InvoiceStatus.info(dep.statusId).label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openInvoice(dep.id),
                  ),
                if (canRemove)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _removePledge(d),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('ยกเลิกเงินมัดจำ'),
                    ),
                  )
                else if (d.hasPaidReceipt)
                  const Text(
                    'มีการชำระเงินแล้ว ไม่สามารถยกเลิกเงินมัดจำหรือลบอะไหล่ได้',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
    );
  }

  Widget _documentsCard(_DetailData d) {
    final q = d.quotation;
    final invoices = d.invoices;
    final receipts = d.receipts;
    if (q.repairs.isEmpty &&
        (invoices?.isEmpty ?? false) &&
        (receipts?.isEmpty ?? false)) {
      return const SizedBox.shrink();
    }
    return SectionCard(
      title: 'เอกสารที่เกี่ยวข้อง',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (q.repairs.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in q.repairs)
                  ActionChip(
                    avatar: const Icon(Icons.car_repair, size: 18),
                    label: Text(
                      'งานซ่อม #${r.id}${r.isCancelled ? ' (ยกเลิก)' : ''}',
                    ),
                    onPressed: () => context.push('/repairs/${r.id}'),
                  ),
              ],
            ),
          if (invoices == null)
            const Text(
              'โหลดรายการใบแจ้งหนี้ไม่สำเร็จ',
              style: TextStyle(color: Colors.red, fontSize: 12),
            )
          else
            for (final inv in invoices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  inv.isDeposit
                      ? Icons.savings_outlined
                      : Icons.receipt_long_outlined,
                ),
                title: Text('${inv.typeLabel} ${inv.id}'),
                subtitle: Text(
                  '${InvoiceStatus.info(inv.statusId).label}'
                  '${inv.amount == null || inv.amount == 0 ? '' : ' · ${formatMoney(inv.amount)} บาท'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openInvoice(inv.id),
              ),
          if (receipts == null)
            const Text(
              'โหลดรายการใบเสร็จไม่สำเร็จ',
              style: TextStyle(color: Colors.red, fontSize: 12),
            )
          else
            for (final r in receipts) _receiptTile(r, invoices),
        ],
      ),
    );
  }

  Widget _receiptTile(QuotationReceipt r, List<Invoice>? invoices) {
    final inv = invoices?.where((i) => i.id == r.invoiceId).firstOrNull;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.task_alt,
        color: r.isPaid ? Colors.green : Colors.grey,
      ),
      title: Text('ใบเสร็จ${r.isDeposit ? ' (เงินมัดจำ)' : ''} ${r.billingId}'),
      subtitle: Text(
        '${r.isPaid ? 'ชำระเงินแล้ว' : 'ยกเลิกการชำระเงิน'} · '
        '${formatMoney(r.amount)} บาท',
      ),
      trailing: const Icon(Icons.picture_as_pdf_outlined),
      onTap: () => openBillingPdf(
        context,
        path: r.pdfPath,
        fileName: '${r.billingId}.pdf',
        isVat: inv?.isVat ?? _data?.quotation.isVat ?? true,
      ),
    );
  }
}
