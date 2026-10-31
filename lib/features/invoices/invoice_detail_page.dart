import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pdf.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../quotations/widgets/totals_card.dart';
import 'invoice_models.dart';
import 'invoices_api.dart';

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late final InvoicesApi _api = InvoicesApi(context.read<ApiClient>());
  late Future<Invoice> _future;
  Invoice? _invoice;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Invoice> _load() async {
    final inv = await _api.findOne(widget.invoiceId);
    if (mounted) {
      // Bottom action bar depends on the loaded status.
      setState(() => _invoice = inv);
    }
    return inv;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  Future<void> _mutate(Future<void> Function() action, {String? toast}) async {
    final ok = await runWithProgress(
      context,
      () async {
        await action();
        return true;
      },
      successMessage: toast,
    );
    if (ok == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _setStatus(
    Invoice inv,
    int status, {
    required String title,
    required String message,
    bool destructive = false,
  }) async {
    final ok = await AppDialogs.confirm(
      context,
      title: title,
      message: message,
      destructive: destructive,
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(
      () => _api.setStatus(inv.id, status),
      toast: 'อัปเดตสถานะเป็น "${InvoiceStatus.info(status).label}" แล้ว',
    );
  }

  Future<void> _pdf(Invoice inv) async {
    if (!inv.hasPdfAddress) {
      await AppDialogs.warn(
        context,
        'ลูกค้ายังไม่มีที่อยู่หลัก (ที่อยู่ตามบัตร/ค่าเริ่มต้น) '
        'จึงไม่สามารถสร้าง PDF ใบแจ้งหนี้ได้ กรุณาเพิ่มที่อยู่ลูกค้าก่อน',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await openServerPdf(
      context,
      '/pdf/create-invoice/${Uri.encodeComponent(inv.id)}',
      '${inv.id}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoiceId),
        actions: [
          IconButton(
            tooltip: 'PDF ใบแจ้งหนี้',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: inv == null ? null : () => _pdf(inv),
          ),
        ],
      ),
      body: AsyncBody<Invoice>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, data) => _body(data),
      ),
      bottomNavigationBar: inv == null ? null : _actions(inv),
    );
  }

  Widget? _actions(Invoice inv) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    final status = inv.statusId;
    final buttons = <Widget>[];
    final canCancel = canManage &&
        (status == InvoiceStatus.pendingConfirm ||
            status == InvoiceStatus.pendingPayment);
    if (canCancel) {
      buttons.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _setStatus(
            inv,
            InvoiceStatus.cancelled,
            title: 'ยกเลิกใบแจ้งหนี้?',
            message: 'ท่านต้องการยกเลิกใบแจ้งหนี้ ${inv.id} ใช่หรือไม่?',
            destructive: true,
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('ยกเลิก'),
        ),
      );
    }
    if (status == InvoiceStatus.pendingConfirm) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _setStatus(
            inv,
            InvoiceStatus.pendingPayment,
            title: 'ยืนยันใบแจ้งหนี้?',
            message: 'ยอดรวมสุทธิ ${formatMoney(inv.totals.grandTotal)} บาท\n'
                'หลังยืนยันจะไม่สามารถเปลี่ยนการคิดภาษีได้',
          ),
          icon: const Icon(Icons.check),
          label: const Text('ยืนยันใบแจ้งหนี้'),
        ),
      );
    } else if (status == InvoiceStatus.pendingPayment) {
      buttons.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () => _setStatus(
            inv,
            InvoiceStatus.paid,
            title: 'บันทึกการชำระเงิน?',
            message: 'ยืนยันว่าได้รับชำระเงิน '
                '${formatMoney(inv.totals.grandTotal)} บาท แล้ว',
          ),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('ชำระเงินแล้ว'),
        ),
      );
    }
    if (buttons.isEmpty) {
      return null;
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(Invoice inv) {
    final editableVat = inv.statusId == InvoiceStatus.pendingConfirm;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SectionCard(
          title: 'ข้อมูลใบแจ้งหนี้',
          trailing: StatusChip(InvoiceStatus.info(inv.statusId)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow('เลขที่', inv.id, bold: true),
              InfoRow('วันที่', formatThaiDateTime(inv.date)),
              InfoRow('ผู้ออกเอกสาร', inv.employeeName),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (inv.repairId != null)
                    ActionChip(
                      avatar: const Icon(Icons.car_repair, size: 18),
                      label: Text('งานซ่อม #${inv.repairId}'),
                      onPressed: () => context.push('/repairs/${inv.repairId}'),
                    ),
                  if (inv.quotationId != null)
                    ActionChip(
                      avatar: const Icon(Icons.request_quote_outlined, size: 18),
                      label: Text(inv.quotationId!),
                      onPressed: () => context.push(
                        '/quotations/${Uri.encodeComponent(inv.quotationId!)}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'ลูกค้า / รถยนต์',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow('ชื่อลูกค้า', inv.customerDisplayName),
              InfoRow('เบอร์โทรศัพท์', inv.customerTel),
              InfoRow('ทะเบียนรถ', inv.plate),
              InfoRow('ยี่ห้อ / รุ่น', inv.brandModel),
            ],
          ),
        ),
        _linesCard(inv),
        TotalsCard(
          totals: inv.totals,
          vatSwitch: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('คิดภาษีมูลค่าเพิ่ม 7%'),
            subtitle: editableVat
                ? null
                : const Text('เปลี่ยนได้เฉพาะสถานะรอยืนยันใบแจ้งหนี้'),
            value: inv.isVat,
            onChanged: editableVat
                ? (v) => _mutate(() => _api.setVat(inv.id, v))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _linesCard(Invoice inv) {
    final groups = inv.groups;
    return SectionCard(
      title: 'รายการ (${inv.lines.length})',
      child: groups.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ไม่มีรายการอะไหล่',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${i + 1}. ${groups[i].repairCategory ?? '-'}'
                      '${groups[i].presetName == null ? '' : ' · ${groups[i].presetName}'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (groups[i].lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'ไม่มีอะไหล่',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  for (final l in groups[i].lines) _lineTile(l),
                  const Divider(),
                ],
              ],
            ),
    );
  }

  Widget _lineTile(InvoiceLine l) {
    final hasDiscount = l.discount != 0;
    final discountText = l.isDiscount == 1
        ? '${formatMoney(l.discount)} ฿'
        : '${formatNumber(l.discount)} %';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.name),
      subtitle: Text(
        '${l.quantity} ${l.part?.unitName ?? ''} × ${formatMoney(l.pricePerUnit)}'
        ' + ค่าบริการ ${formatMoney(l.serviceFee)}'
        '${hasDiscount ? '\nส่วนลด $discountText (-${formatMoney(l.discountAmount)})' : ''}',
      ),
      trailing: Text(
        formatMoney(l.total),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
