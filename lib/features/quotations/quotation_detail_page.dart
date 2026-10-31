import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pdf.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import 'quotation_models.dart';
import 'quotations_api.dart';
import 'totals.dart';
import 'widgets/add_item_page.dart';
import 'widgets/car_picker.dart';
import 'widgets/cash_pledge_dialog.dart';
import 'widgets/part_line_dialog.dart';
import 'widgets/quotation_form_dialog.dart';
import 'widgets/totals_card.dart';

class _DetailData {
  const _DetailData({
    required this.quotation,
    required this.details,
    required this.pledges,
    this.invoice,
  });

  final Quotation quotation;
  final List<QuotationDetail> details;
  final List<CashPledge> pledges;

  /// Invoice created from this quotation (via its first repair), if any.
  final Map<String, dynamic>? invoice;

  DocumentTotals get totals => DocumentTotals.fromLines(
        details.expand((d) => d.parts).map((p) => p.total),
        isVat: quotation.isVat,
        cashPledges: pledges.map((p) => p.amount),
      );
}

class QuotationDetailPage extends StatefulWidget {
  const QuotationDetailPage({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuotationDetailPage> createState() => _QuotationDetailPageState();
}

class _QuotationDetailPageState extends State<QuotationDetailPage> {
  late final QuotationsApi _api = QuotationsApi(context.read<ApiClient>());
  late Future<_DetailData> _future;
  _DetailData? _data;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final id = widget.quotationId;
    final results = await Future.wait([
      _api.findOne(id),
      _api.details(id),
      _api.cashPledges(id),
    ]);
    final quotation = results[0] as Quotation;
    Map<String, dynamic>? invoice;
    if (quotation.isApproved) {
      invoice = await _api.invoiceByRepair(quotation.repairs.first.id);
    }
    final data = _DetailData(
      quotation: quotation,
      details: results[1] as List<QuotationDetail>,
      pledges: results[2] as List<CashPledge>,
      invoice: invoice,
    );
    if (mounted) {
      // The app bar menu and approve button depend on the loaded data.
      setState(() => _data = data);
    }
    return data;
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

  /// Runs [action] with a progress dialog and reloads on success.
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

  Future<void> _toggleVat(Quotation q, bool on) {
    return _mutate(() => _api.update(q.id, {'isVat': on ? 1 : 0}));
  }

  Future<void> _deleteQuotation(Quotation q) async {
    final ok = await AppDialogs.confirmDelete(context, 'ใบเสนอราคา ${q.id}');
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(q.id);
      return true;
    });
    if (done == true && mounted) {
      AppDialogs.toast(context, 'ลบใบเสนอราคาแล้ว');
      context.pop();
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
    final ok = await AppDialogs.confirmDelete(
      context,
      'รายการ ${d.repairCategory ?? ''} ${d.presetName ?? ''}'.trim(),
    );
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

  Future<void> _addPledge(Quotation q) async {
    final input = await showCashPledgeDialog(context);
    if (input == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.addCashPledge(
        quotationId: q.id,
        title: input.title,
        amount: input.amount,
      ),
      toast: 'เพิ่มเงินมัดจำแล้ว',
    );
  }

  Future<void> _deletePledge(CashPledge p) async {
    final ok = await AppDialogs.confirmDelete(context, 'มัดจำ "${p.title}"');
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() => _api.deleteCashPledge(p.id), toast: 'ลบเงินมัดจำแล้ว');
  }

  // ---- PDF ----

  void _pdf(String id, {required bool group}) {
    final enc = Uri.encodeComponent(id);
    openServerPdf(
      context,
      group ? '/pdf/create-quotation-group/$enc' : '/pdf/create-quotation/$enc',
      group ? '$id-group.pdf' : '$id.pdf',
    );
  }

  // ---- Approve ----

  Future<void> _approve(_DetailData data) async {
    final q = data.quotation;
    final parts = data.details.expand((d) => d.parts).toList();
    if (data.details.isEmpty) {
      await AppDialogs.warn(context, 'กรุณาเพิ่มรายการซ่อมก่อนอนุมัติใบเสนอราคา');
      return;
    }
    final employeeId = context.read<AuthProvider>().employee?.id;
    if (employeeId == null) {
      await AppDialogs.warn(context, 'ไม่พบข้อมูลผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    // The server deducts stock for every part and rolls back with a generic
    // message when any part is short, so check up-front for a clear message.
    final need = <int, int>{};
    final byId = <int, QuotationPart>{};
    for (final p in parts) {
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
        'สินค้าคงคลังไม่เพียงพอ ไม่สามารถอนุมัติได้\n\n${short.join('\n')}',
      );
      return;
    }

    final car = await showCarPicker(context, api: _api, modelId: q.modelId);
    if (car == null || !mounted) {
      return;
    }
    final brandId = car.brandId ?? q.brandId;
    final modelId = car.modelId ?? q.modelId;
    if (car.customerId == null || brandId == null || modelId == null) {
      await AppDialogs.warn(context, 'ข้อมูลรถยนต์ไม่ครบถ้วน (ลูกค้า/ยี่ห้อ/รุ่น)');
      return;
    }
    final modelWarning = car.modelId != null && car.modelId != q.modelId
        ? '\n\n⚠ รุ่นรถที่เลือกไม่ตรงกับรุ่นในใบเสนอราคา'
        : '';
    final ok = await AppDialogs.confirm(
      context,
      title: 'อนุมัติใบเสนอราคา?',
      message: 'ระบบจะสร้างงานซ่อมและใบแจ้งหนี้ พร้อมตัดสต็อกอะไหล่\n\n'
          'รถ: ${car.plate}\n'
          'ลูกค้า: ${car.owner}\n'
          'ยอดรวมสุทธิ: ${formatMoney(data.totals.grandTotal)} บาท'
          '$modelWarning',
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
        carId: car.id,
        customerId: car.customerId!,
        employeeId: employeeId,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    AppDialogs.toast(context, 'อนุมัติใบเสนอราคาเรียบร้อยแล้ว');
    await _refresh();
    if (!mounted) {
      return;
    }
    if (result.invoiceId != null) {
      context.push('/invoices/${Uri.encodeComponent(result.invoiceId!)}');
    } else if (result.repairId != null) {
      context.push('/repairs/${result.repairId}');
    }
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
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'pdf':
                  _pdf(widget.quotationId, group: false);
                case 'pdf-group':
                  _pdf(widget.quotationId, group: true);
                case 'delete':
                  if (data != null) {
                    _deleteQuotation(data.quotation);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF ใบเสนอราคา'),
                ),
              ),
              const PopupMenuItem(
                value: 'pdf-group',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text('PDF แยกตามรายการ'),
                ),
              ),
              if (canManage && data != null && !data.quotation.isApproved)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('ลบใบเสนอราคา'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: AsyncBody<_DetailData>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, d) => _body(d),
      ),
      bottomNavigationBar: data == null || data.quotation.isApproved
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => _approve(data),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('อนุมัติ / สร้างงานซ่อมและใบแจ้งหนี้'),
                ),
              ),
            ),
    );
  }

  Widget _body(_DetailData d) {
    final q = d.quotation;
    final locked = q.isApproved;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (locked) _approvedCard(d),
        SectionCard(
          title: 'ข้อมูลใบเสนอราคา',
          trailing: locked
              ? null
              : IconButton(
                  tooltip: 'แก้ไขหมายเหตุ',
                  icon: const Icon(Icons.edit_note),
                  onPressed: () => _editComment(q),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow('เลขที่', q.id, bold: true),
              InfoRow('วันที่', formatThaiDateTime(q.date)),
              InfoRow('ยี่ห้อ / รุ่น', q.brandModel),
              InfoRow('ผู้เสนอราคา', q.employeeName),
              InfoRow('หมายเหตุ', q.comment),
            ],
          ),
        ),
        _itemsCard(d, locked),
        _pledgeCard(d, locked),
        TotalsCard(
          totals: d.totals,
          showPledge: true,
          vatSwitch: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('คิดภาษีมูลค่าเพิ่ม 7%'),
            value: q.isVat,
            onChanged: locked ? null : (v) => _toggleVat(q, v),
          ),
        ),
      ],
    );
  }

  Widget _approvedCard(_DetailData d) {
    final repair = d.quotation.repairs.first;
    final invoice = d.invoice;
    final invoiceId = asString(invoice?['InvoiceID']);
    final car = asMap(asMap(invoice?['repair'])?['car']) ?? repair.car;
    final customer = asMap(car?['customer']);
    return Card(
      color: Colors.green.withValues(alpha: 0.08),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.verified, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'อนุมัติแล้ว — แก้ไขใบเสนอราคาไม่ได้',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (customer != null) InfoRow('ลูกค้า', customerName(customer)),
            InfoRow('ทะเบียนรถ', carPlate(car)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in d.quotation.repairs)
                  ActionChip(
                    avatar: const Icon(Icons.car_repair, size: 18),
                    label: Text('งานซ่อม #${r.id}'),
                    onPressed: () => context.push('/repairs/${r.id}'),
                  ),
                if (invoiceId != null)
                  ActionChip(
                    avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(invoiceId),
                    onPressed: () async {
                      await context.push(
                        '/invoices/${Uri.encodeComponent(invoiceId)}',
                      );
                      if (mounted) {
                        _refresh();
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemsCard(_DetailData d, bool locked) {
    return SectionCard(
      title: 'รายการซ่อม (${d.details.length})',
      trailing: locked
          ? null
          : TextButton.icon(
              onPressed: () => _addItem(d.quotation),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มรายการ'),
            ),
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
                  _detailBlock(i + 1, d.details[i], locked),
              ],
            ),
    );
  }

  Widget _detailBlock(int no, QuotationDetail detail, bool locked) {
    final theme = Theme.of(context);
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
              '$no. ${detail.repairCategory ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('พรีเซ็ต: ${detail.presetName ?? '-'}'),
            trailing: locked
                ? Text(formatMoney(detail.total))
                : IconButton(
                    tooltip: 'ลบรายการ',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteItem(detail),
                  ),
          ),
          const Divider(height: 1),
          if (detail.parts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ไม่มีอะไหล่', style: TextStyle(color: Colors.grey)),
            ),
          for (final p in detail.parts)
            ListTile(
              dense: true,
              title: Text(p.name),
              subtitle: Text(
                '${p.quantity} ${p.part?.unitName ?? ''} × '
                '${formatMoney(p.pricePerUnit)}'
                ' + ค่าบริการ ${formatMoney(p.serviceFee)}',
              ),
              trailing: Text(
                formatMoney(p.total),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: locked ? null : () => _editPart(p),
              onLongPress: locked ? null : () => _deletePart(p),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                if (!locked)
                  const Expanded(
                    child: Text(
                      'แตะเพื่อแก้ไข · กดค้างเพื่อลบ',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
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

  Widget _pledgeCard(_DetailData d, bool locked) {
    return SectionCard(
      title: 'เงินมัดจำ',
      trailing: locked
          ? null
          : TextButton.icon(
              onPressed: () => _addPledge(d.quotation),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่ม'),
            ),
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
              children: [
                for (final p in d.pledges)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.savings_outlined),
                    title: Text(p.title),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${formatMoney(p.amount)} บาท'),
                        if (!locked)
                          IconButton(
                            tooltip: 'ลบ',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => _deletePledge(p),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
