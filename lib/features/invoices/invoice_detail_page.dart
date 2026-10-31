import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../quotations/quotation_models.dart' show QuotationReceipt;
import '../quotations/totals.dart';
import '../quotations/widgets/quotation_dialogs.dart' show openBillingPdf;
import '../quotations/widgets/totals_card.dart';
import 'invoice_models.dart';
import 'invoices_api.dart';

class _InvoiceData {
  const _InvoiceData({required this.invoice, required this.pledges});

  final Invoice invoice;

  /// Cash pledges of the invoice's quotation (deducted on repair invoices).
  final List<double> pledges;

  DocumentTotals get totals => invoice.totals(cashPledges: pledges);
}

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late final InvoicesApi _api = InvoicesApi(context.read<ApiClient>());
  late Future<_InvoiceData> _future;
  _InvoiceData? _data;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InvoiceData> _load() async {
    final inv = await _api.findOne(widget.invoiceId);
    final qid = inv.quotationId;
    // Pledges must be known to compute the net total that gets saved, so a
    // failure here fails the whole load instead of silently using 0.
    final pledges = !inv.isDeposit && qid != null
        ? await _api.cashPledges(qid)
        : const <double>[];
    final data = _InvoiceData(invoice: inv, pledges: pledges);
    if (mounted) {
      // The action bar depends on the loaded status.
      setState(() => _data = data);
    }
    return data;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

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

  // ---- Status changes (web changeInvoiceStatus) ----

  Future<void> _confirm(_InvoiceData d) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันใบแจ้งหนี้?',
      message:
          'ยอดที่ต้องชำระ ${formatMoney(d.totals.netTotal)} บาท\n'
          'หลังยืนยันจะไม่สามารถเปลี่ยนการคิดภาษีได้',
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(
      () => _api.changeStatus(
        d.invoice.id,
        InvoiceStatus.pendingPayment,
        netTotal: d.totals.netTotal,
      ),
      toast: 'ยืนยันใบแจ้งหนี้แล้ว',
    );
  }

  Future<void> _backToDraft(_InvoiceData d) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'แก้ไขใบแจ้งหนี้?',
      message: 'สถานะจะกลับเป็น "รอยืนยันใบแจ้งหนี้" ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(
      () => _api.changeStatus(d.invoice.id, InvoiceStatus.pendingConfirm),
      toast: 'เปลี่ยนสถานะเป็นรอยืนยันใบแจ้งหนี้แล้ว',
    );
  }

  /// Paid: status 3 with Amount = net total, then `POST /receipts` like the
  /// web does.
  Future<void> _markPaid(_InvoiceData d) async {
    final inv = d.invoice;
    final net = d.totals.netTotal;
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการชำระเงิน?',
      message:
          'ยืนยันว่าได้รับชำระเงิน ${formatMoney(net)} บาท แล้ว\n'
          'ระบบจะออกใบเสร็จรับเงินให้อัตโนมัติ',
    );
    if (!ok || !mounted) {
      return;
    }
    var receiptFailed = false;
    final done = await runWithProgress(context, () async {
      await _api.changeStatus(inv.id, InvoiceStatus.paid, netTotal: net);
      try {
        await _api.createReceipt(
          invoiceId: inv.id,
          repairId: inv.repairId,
          amount: net,
        );
      } catch (_) {
        receiptFailed = true;
      }
      return true;
    });
    if (done != true || !mounted) {
      return;
    }
    await _refresh();
    if (!mounted) {
      return;
    }
    if (receiptFailed) {
      await AppDialogs.warn(
        context,
        'บันทึกการชำระเงินแล้ว แต่ออกใบเสร็จรับเงินไม่สำเร็จ '
        'กรุณาตรวจสอบที่ระบบเว็บ',
      );
    } else {
      AppDialogs.toast(context, 'บันทึกการชำระเงินเรียบร้อยแล้ว');
    }
  }

  Future<void> _cancel(_InvoiceData d) async {
    final inv = d.invoice;
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยกเลิกใบแจ้งหนี้?',
      message:
          'คุณต้องการยกเลิกใบแจ้งหนี้ ${inv.id} ใช่หรือไม่?'
          '${inv.isDeposit ? '\nเงินมัดจำของใบเสนอราคาจะถูกลบด้วย' : ''}',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.changeStatus(
        inv.id,
        InvoiceStatus.cancelled,
        netTotal: d.totals.netTotal,
      );
      return true;
    });
    if (done != true || !mounted) {
      return;
    }
    AppDialogs.toast(context, 'ยกเลิกใบแจ้งหนี้เรียบร้อยแล้ว');
    final qid = inv.quotationId;
    if (qid != null) {
      // Web: go to the quotation after cancelling.
      context.pushReplacement('/quotations/${Uri.encodeComponent(qid)}');
    } else {
      await _refresh();
    }
  }

  Future<void> _setVat(Invoice inv, bool isVat, int vatType) {
    return _mutate(() => _api.setVat(inv.id, isVat: isVat, vatType: vatType));
  }

  // ---- PDF ----

  Future<void> _pdf(Invoice inv) => openBillingPdf(
    context,
    path: inv.pdfPath,
    fileName: '${inv.id}.pdf',
    isVat: inv.isVat,
  );

  Future<void> _receiptPdf(Invoice inv, QuotationReceipt r) => openBillingPdf(
    context,
    path: r.pdfPath,
    fileName: '${r.billingId}.pdf',
    isVat: inv.isVat,
  );

  // ---- UI ----

  bool _canPrint(Invoice inv) =>
      inv.statusId == InvoiceStatus.pendingPayment ||
      inv.statusId == InvoiceStatus.paid;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoiceId),
        actions: [
          if (d != null && _canPrint(d.invoice))
            IconButton(
              tooltip: 'PDF ${d.invoice.typeLabel}',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _pdf(d.invoice),
            ),
        ],
      ),
      body: AsyncBody<_InvoiceData>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, data) => _body(data),
      ),
      bottomNavigationBar: d == null ? null : _actions(d),
    );
  }

  Widget? _actions(_InvoiceData d) {
    final inv = d.invoice;
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    final buttons = <Widget>[];
    if (inv.statusId == InvoiceStatus.pendingConfirm) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _confirm(d),
          icon: const Icon(Icons.check),
          label: const Text('ยืนยันใบแจ้งหนี้'),
        ),
      );
    } else if (inv.statusId == InvoiceStatus.pendingPayment) {
      if (canManage) {
        buttons.add(
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => _cancel(d),
            child: const Text('ยกเลิก'),
          ),
        );
      }
      if (!inv.isDeposit) {
        buttons.add(
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: () => _backToDraft(d),
            child: const Text('แก้ไข'),
          ),
        );
      }
      buttons.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () => _markPaid(d),
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
              Expanded(
                flex: i == buttons.length - 1 ? 2 : 1,
                child: buttons[i],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(_InvoiceData d) {
    final inv = d.invoice;
    final isDraft = inv.statusId == InvoiceStatus.pendingConfirm;
    final vatLocked = inv.isDeposit || d.pledges.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (inv.statusId == InvoiceStatus.cancelled)
          Card(
            color: Colors.red.withValues(alpha: 0.08),
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.block, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'ยกเลิกใบแจ้งหนี้',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        SectionCard(
          title: inv.typeLabel,
          trailing: StatusChip(InvoiceStatus.info(inv.statusId)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow('เลขที่', inv.id, bold: true),
              InfoRow('วันที่', formatThaiDateTime(inv.date)),
              InfoRow('ผู้ออกเอกสาร', inv.employeeName),
              if (inv.amount != null && inv.amount! > 0)
                InfoRow('ยอดที่บันทึก', '${formatMoney(inv.amount)} บาท'),
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
                      avatar: const Icon(
                        Icons.request_quote_outlined,
                        size: 18,
                      ),
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
              InfoRow('เลขผู้เสียภาษี', inv.customerTaxId),
              InfoRow('เบอร์โทรศัพท์', inv.customerTel),
              InfoRow('ที่อยู่', inv.addressDisplay),
              const Divider(),
              InfoRow('ทะเบียนรถ', inv.plate),
              InfoRow('ยี่ห้อ / รุ่น', inv.brandModel),
              InfoRow('หมายเลขเครื่องยนต์', asString(inv.car?['EC'])),
              InfoRow('หมายเลขตัวถัง', asString(inv.car?['VIN'])),
            ],
          ),
        ),
        inv.isDeposit ? _depositCard(inv) : _linesCard(inv),
        TotalsCard(
          totals: d.totals,
          vatControls: isDraft
              ? VatControls(
                  isVat: inv.isVat,
                  vatType: inv.vatType,
                  onChanged: vatLocked ? null : (v, t) => _setVat(inv, v, t),
                  disabledReason:
                      '* ไม่สามารถแก้ไขภาษีได้ เนื่องจากเป็นรายการเงินมัดจำหรือมีการหักเงินมัดจำ',
                )
              : null,
        ),
        if (inv.receipts.isNotEmpty)
          SectionCard(
            title: 'ใบเสร็จรับเงิน',
            child: Column(
              children: [
                for (final r in inv.receipts)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.task_alt,
                      color: r.isPaid ? Colors.green : Colors.grey,
                    ),
                    title: Text(r.billingId),
                    subtitle: Text(
                      r.isPaid ? 'ชำระเงินแล้ว' : 'ยกเลิกการชำระเงิน',
                    ),
                    trailing: const Icon(Icons.picture_as_pdf_outlined),
                    onTap: () => _receiptPdf(inv, r),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _depositCard(Invoice inv) {
    final net = depositItemsSum(
      amount: inv.amount ?? 0,
      isVat: inv.isVat,
      vatType: inv.vatType,
    );
    return SectionCard(
      title: 'รายการมัดจำ',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.savings_outlined),
        title: const Text('เงินมัดจำ'),
        subtitle: Text('1 × ${formatMoney(net)}'),
        trailing: Text(
          formatMoney(net),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _linesCard(Invoice inv) {
    final groups = inv.groups;
    final fees = inv.feesByPreset;
    final feeTotal = inv.totalServiceFee;
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
                      '${i + 1}. ${groups[i].presetName ?? groups[i].repairCategory ?? '-'}',
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
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'รวมค่าบริการ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      '${fees.length} รายการ · ${formatMoney(feeTotal)}',
                      if (inv.feeDiscount.amount != 0)
                        'ส่วนลด ${inv.feeDiscount.label} '
                            '(-${formatMoney(inv.feeDiscountAmount)})',
                    ].join('\n'),
                  ),
                  trailing: Text(
                    formatMoney(feeTotal - inv.feeDiscountAmount),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final e in fees.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 2),
                    child: Text(
                      '(ค่าบริการ) ${e.key} (${formatMoney(e.value)} ฿)',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _lineTile(InvoiceLine l) {
    final hasDiscount = l.discount != 0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.name),
      subtitle: Text(
        '${l.quantity} ${l.part?.unitName ?? ''} × ${formatMoney(l.pricePerUnit)}'
        '${l.serviceFee == 0 ? '' : ' (ค่าบริการ ${formatMoney(l.serviceFee)})'}'
        '${hasDiscount ? '\nส่วนลด ${l.discountLabel} (-${formatMoney(l.discountAmount)})' : ''}',
      ),
      trailing: Text(
        formatMoney(l.total),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
