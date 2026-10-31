import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/pdf.dart';
import '../../../core/widgets/state_views.dart';
import '../quotation_models.dart';
import '../quotations_api.dart';

// ---------------------------------------------------------------- timeline

/// Bottom sheet with `GET /quotation/logs/:id` (web RepairTimelineDialog).
Future<void> showQuotationTimeline(
  BuildContext context, {
  required QuotationsApi api,
  required String quotationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TimelineSheet(api: api, quotationId: quotationId),
  );
}

class _TimelineSheet extends StatefulWidget {
  const _TimelineSheet({required this.api, required this.quotationId});

  final QuotationsApi api;
  final String quotationId;

  @override
  State<_TimelineSheet> createState() => _TimelineSheetState();
}

class _TimelineSheetState extends State<_TimelineSheet> {
  late Future<List<QuotationLog>> _future = widget.api.logs(widget.quotationId);

  static Color _color(String? action) => switch (action) {
        'สร้าง' => Colors.green,
        'แก้ไข' => Colors.orange,
        'ลบ' || 'ยกเลิก' => Colors.red,
        'คัดลอก' => Colors.purple,
        _ => Colors.blue,
      };

  static IconData _icon(String? action) => switch (action) {
        'สร้าง' => Icons.add_circle_outline,
        'แก้ไข' => Icons.edit_outlined,
        'ลบ' || 'ยกเลิก' => Icons.delete_outline,
        'คัดลอก' => Icons.copy_all_outlined,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'ประวัติการดำเนินการ ${widget.quotationId}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<QuotationLog>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(
                    error: snap.error!,
                    onRetry: () => setState(
                      () => _future = widget.api.logs(widget.quotationId),
                    ),
                  );
                }
                final logs = snap.data!;
                if (logs.isEmpty) {
                  return const EmptyView(message: 'ยังไม่มีประวัติ');
                }
                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final color = _color(log.action);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(_icon(log.action), color: color, size: 20),
                      ),
                      title: Text(
                        [log.action, log.module].whereType<String>().join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((log.details ?? '').isNotEmpty) Text(log.details!),
                          Text(
                            '${formatThaiDateTime(log.createdAt)} · '
                            '${log.employeeName ?? 'ระบบอัตโนมัติ'}'
                            '${log.repairId == null ? '' : ' · งานซ่อม #${log.repairId}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- copy

/// Choice from [showCopyQuotationDialog].
class CopyRequest {
  const CopyRequest({required this.detailIds, required this.useExisting});

  final List<int> detailIds;

  /// true: server creates the new quotation with the same car/customer and
  /// copies the photos. false: the user fills a new quotation first.
  final bool useExisting;
}

/// Web CopyQuotationDialog: pick items (presets) and whether to reuse the
/// car/customer data.
Future<CopyRequest?> showCopyQuotationDialog(
  BuildContext context, {
  required List<QuotationDetail> details,
}) {
  return showDialog<CopyRequest>(
    context: context,
    builder: (_) => _CopyDialog(details: details),
  );
}

class _CopyDialog extends StatefulWidget {
  const _CopyDialog({required this.details});

  final List<QuotationDetail> details;

  @override
  State<_CopyDialog> createState() => _CopyDialogState();
}

class _CopyDialogState extends State<_CopyDialog> {
  final _selected = <int>{};
  bool _useExisting = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('คัดลอกรายการไปยังใบเสนอราคาใหม่'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              '1. เลือกชุดอุปกรณ์ที่ต้องการคัดลอก',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (widget.details.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('ไม่มีรายการให้คัดลอก', style: TextStyle(color: Colors.grey)),
              ),
            for (final d in widget.details)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _selected.contains(d.id),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(d.id);
                  } else {
                    _selected.remove(d.id);
                  }
                }),
                title: Text(d.title),
                subtitle: Text(
                  '${d.parts.length} รายการย่อย · ${formatMoney(d.total)} บาท'
                  '${d.copiedToQuotationId == null ? '' : '\nคัดลอกไป ${d.copiedToQuotationId} แล้ว'}',
                ),
              ),
            const Divider(),
            const Text(
              '2. ข้อมูลรายละเอียดรถยนต์',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<bool>(
              groupValue: _useExisting,
              onChanged: (v) => setState(() => _useExisting = v ?? true),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: true,
                    title: Text(
                      'ใช้ข้อมูลรถยนต์และลูกค้าเดิม '
                      '(คัดลอกรูปภาพและรายละเอียดรถทั้งหมดไปใบใหม่)',
                    ),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: false,
                    title: Text('กรอกข้อมูลลูกค้าและรถยนต์ใหม่ (รูปภาพอัปโหลดภายหลัง)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    CopyRequest(
                      detailIds: _selected.toList(),
                      useExisting: _useExisting,
                    ),
                  ),
          child: Text('คัดลอก (${_selected.length})'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ receive type

/// How the customer gets the car back (`ReceiveType`).
class ReceiveChoice {
  const ReceiveChoice.wait() : type = 1, appointment = null;

  const ReceiveChoice.appointment(DateTime this.appointment) : type = 2;

  /// 1 = ลูกค้ารอรับ, 2 = ลูกค้านัดรับ.
  final int type;
  final DateTime? appointment;

  String get label => type == 1
      ? 'ลูกค้ารอรับ'
      : 'ลูกค้านัดรับ (${formatThaiDateTime(appointment)})';
}

Future<ReceiveChoice?> showReceiveTypeDialog(BuildContext context) {
  return showDialog<ReceiveChoice>(
    context: context,
    builder: (_) => const _ReceiveTypeDialog(),
  );
}

class _ReceiveTypeDialog extends StatefulWidget {
  const _ReceiveTypeDialog();

  @override
  State<_ReceiveTypeDialog> createState() => _ReceiveTypeDialogState();
}

class _ReceiveTypeDialogState extends State<_ReceiveTypeDialog> {
  int _type = 1;
  DateTime? _date;
  TimeOfDay? _time;

  DateTime? get _appointment => _date == null
      ? null
      : DateTime(
          _date!.year,
          _date!.month,
          _date!.day,
          _time?.hour ?? 0,
          _time?.minute ?? 0,
        );

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'วันที่นัดรับรถ',
    );
    if (d == null || !mounted) {
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 17, minute: 0),
      helpText: 'เวลานัดรับรถ',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _date = d;
      _time = t ?? _time;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appointment = _appointment;
    return AlertDialog(
      title: const Text('รูปแบบการรับรถ'),
      content: RadioGroup<int>(
        groupValue: _type,
        onChanged: (v) => setState(() => _type = v ?? 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: 1,
              title: Text('ลูกค้ารอรับ'),
            ),
            const RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: 2,
              title: Text('ลูกค้านัดรับ'),
            ),
            if (_type == 2)
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.event),
                label: Text(
                  appointment == null
                      ? 'เลือกวันและเวลานัดรับ'
                      : formatThaiDateTime(appointment),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _type == 2 && appointment == null
              ? null
              : () => Navigator.of(context).pop(
                    _type == 1
                        ? const ReceiveChoice.wait()
                        : ReceiveChoice.appointment(appointment!),
                  ),
          child: const Text('ตกลง'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- PDF

/// Header options of the quotation PDFs (`?docTitle=`), as on the web.
const quotationDocTitles = ['ใบเสนอราคา', 'ใบงาน', 'ใบรับรถ'];

/// Opens `/pdf/create-quotation[-group]/:id` after asking for the header
/// title (and, for the grouped layout, whether to print the totals).
Future<void> openQuotationPdf(
  BuildContext context, {
  required String quotationId,
  required bool grouped,
}) async {
  var title = quotationDocTitles.first;
  var showTotal = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('ตั้งค่าการแสดงผล'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: title,
              decoration: const InputDecoration(labelText: 'หัวกระดาษ'),
              items: [
                for (final t in quotationDocTitles)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => title = v ?? title),
            ),
            if (grouped)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('แสดงยอดรวมท้ายเอกสาร'),
                value: showTotal,
                onChanged: (v) => setState(() => showTotal = v),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ปิด'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) {
    return;
  }
  final enc = Uri.encodeComponent(quotationId);
  final query = 'docTitle=${Uri.encodeQueryComponent(title)}'
      '${grouped ? '&showTotal=$showTotal' : ''}';
  await openServerPdf(
    context,
    grouped
        ? '/pdf/create-quotation-group/$enc?$query'
        : '/pdf/create-quotation/$enc?$query',
    grouped ? '$quotationId-group.pdf' : '$quotationId.pdf',
  );
}

/// Invoice / receipt PDFs: when VAT is off the web asks whether to print the
/// customer's address and tax ID (`?hideAddress=true|false`).
Future<void> openBillingPdf(
  BuildContext context, {
  required String path,
  required String fileName,
  required bool isVat,
}) async {
  var query = '';
  if (!isVat) {
    final show = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตั้งค่าการแสดงผล'),
        content: const Text('ต้องการให้แสดงที่อยู่และเลขประจำตัวผู้เสียภาษีหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ไม่แสดง'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('แสดง'),
          ),
        ],
      ),
    );
    if (show == null) {
      return;
    }
    query = '?hideAddress=${!show}';
  }
  if (!context.mounted) {
    return;
  }
  await openServerPdf(context, '$path$query', fileName);
}
