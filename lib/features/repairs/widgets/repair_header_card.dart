import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../repair_models.dart';

/// Customer / car / job summary at the top of the repair detail page.
class RepairHeaderCard extends StatelessWidget {
  const RepairHeaderCard({
    super.key,
    required this.repair,
    required this.onChangeStatus,
  });

  final Repair repair;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final r = repair;
    final plate = [r.plate, ?r.provinceName].join(' ');
    return SectionCard(
      title: 'ข้อมูลงานซ่อม #${r.id}',
      trailing: InkWell(
        onTap: onChangeStatus,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(WorkStatus.info(r.workStatusId)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('ลูกค้า', r.customerName),
          InfoRow('เบอร์โทร', r.customerTel),
          const Divider(),
          InfoRow('ทะเบียนรถ', plate, bold: true),
          InfoRow('ยี่ห้อ / รุ่น', r.brandModel),
          InfoRow('เลขตัวถัง (VIN)', r.vin),
          InfoRow('ซีซี (EC)', r.ec),
          const Divider(),
          InfoRow('วันที่รับรถ', formatThaiDate(r.date)),
          InfoRow('พนักงานรับรถ', r.employeeName),
          if (r.quotationId != null) InfoRow('ใบเสนอราคา', r.quotationId),
        ],
      ),
    );
  }
}
