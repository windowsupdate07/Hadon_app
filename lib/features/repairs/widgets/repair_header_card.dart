import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../repair_models.dart';

/// Customer / car / job summary at the top of the repair detail page.
/// Tapping the status opens the timeline (same as the web).
class RepairHeaderCard extends StatelessWidget {
  const RepairHeaderCard({
    super.key,
    required this.repair,
    required this.onTapStatus,
    this.onEditReceiveType,
  });

  final Repair repair;
  final VoidCallback onTapStatus;

  /// Null hides the edit button.
  final VoidCallback? onEditReceiveType;

  @override
  Widget build(BuildContext context) {
    final r = repair;
    final plate = [r.plate, ?r.provinceName].join(' ');
    return SectionCard(
      title: 'ข้อมูลงานซ่อม #${r.id}',
      trailing: InkWell(
        onTap: onTapStatus,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: StatusChip(workStatusInfo(r))),
            const Icon(Icons.history, size: 18),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('ลูกค้า', r.customerName),
          InfoRow('เบอร์โทร', r.customerTel),
          InfoRow('เลขผู้เสียภาษี', r.customerIdNumber),
          InfoRow('ที่อยู่', r.customerAddress),
          const Divider(),
          InfoRow('ทะเบียนรถ', plate, bold: true),
          InfoRow('ยี่ห้อ / รุ่น', r.brandModel),
          if (r.carColor != null) InfoRow('สีรถ', r.carColor),
          InfoRow('เลขตัวถัง (VIN)', r.vin),
          InfoRow('เลขเครื่องยนต์', r.ec),
          if (r.quotationId != null) ...[
            InfoRow(
              'เลขไมล์ (กม.)',
              r.mileage == null ? null : formatNumber(r.mileage),
            ),
            InfoRow(
              'แก๊ส / ลมยาง',
              '${r.gasInstallation == 1 ? 'ติดแก๊ส' : 'ไม่ติดแก๊ส'} / '
                  '${r.tireType == 1 ? 'ลมยางไนโตรเจน' : 'ลมยางธรรมดา'}',
            ),
            InfoRow(
              'ป้ายภาษีหมดอายุ',
              r.taxDate == null ? null : formatThaiDate(r.taxDate),
            ),
          ],
          const Divider(),
          InfoRow('วันที่รับรถ', formatThaiDate(r.date)),
          InfoRow('สร้างเมื่อ', formatThaiDateTime(r.createdAt)),
          InfoRow('พนักงานรับรถ', r.employeeName),
          _receiveRow(context),
          if (r.quotationId != null) _quotationRow(context, r.quotationId!),
        ],
      ),
    );
  }

  Widget _receiveRow(BuildContext context) {
    final r = repair;
    final String text;
    if (r.receiveType == ReceiveType.wait) {
      text = 'ลูกค้ารอรับ';
    } else if (r.receiveType == ReceiveType.appointment &&
        r.receiveAppointmentDate != null) {
      text = 'นัดรับ ${formatThaiDateTime(r.receiveAppointmentDate)} น.';
    } else {
      text = 'ไม่ระบุ';
    }
    return Row(
      children: [
        Expanded(child: InfoRow('รอรับ / นัดรับ', text, bold: true)),
        if (onEditReceiveType != null)
          IconButton(
            tooltip: 'แก้ไขรูปแบบการรับรถ',
            visualDensity: VisualDensity.compact,
            onPressed: onEditReceiveType,
            icon: const Icon(Icons.edit_calendar_outlined, size: 20),
          ),
      ],
    );
  }

  Widget _quotationRow(BuildContext context, String id) {
    return InkWell(
      onTap: () => context.push('/quotations/${Uri.encodeComponent(id)}'),
      child: Row(
        children: [
          Expanded(child: InfoRow('ใบเสนอราคา', id)),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

/// [WorkStatus.info] with the server's label as fallback for unknown ids.
StatusInfo workStatusInfo(Repair r) {
  final info = WorkStatus.info(r.workStatusId);
  if (info.label == '-' && r.workStatusLabel != null) {
    return StatusInfo(r.workStatusLabel!, Colors.grey);
  }
  return info;
}
