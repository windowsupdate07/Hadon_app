import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import 'car_models.dart';
import 'cars_api.dart';

/// Shows the repair history of [car] (`GET /repair/by-car/:id`) in a bottom
/// sheet. Tapping a job closes the sheet and opens `/repairs/:id`.
Future<void> showCarRepairHistory(BuildContext context, Car car) async {
  final repairId = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RepairHistorySheet(car: car),
  );
  if (repairId != null && context.mounted) {
    await context.push('/repairs/$repairId');
  }
}

class _RepairHistorySheet extends StatefulWidget {
  const _RepairHistorySheet({required this.car});

  final Car car;

  @override
  State<_RepairHistorySheet> createState() => _RepairHistorySheetState();
}

class _RepairHistorySheetState extends State<_RepairHistorySheet> {
  late final CarsApi _api = CarsApi(context.read<ApiClient>());
  late Future<List<CarRepairRecord>> _future =
      _api.repairHistory(widget.car.id);

  Future<void> _refresh() async {
    final future = _api.repairHistory(widget.car.id);
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ประวัติการซ่อม',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.car.plateWithProvince,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncBody<List<CarRepairRecord>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (list) => list.isEmpty,
              emptyMessage: 'ยังไม่มีประวัติการซ่อมสำหรับรถคันนี้',
              builder: (context, list) => ListView.separated(
                controller: scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _RepairTile(
                  record: list[i],
                  onTap: () => Navigator.of(context).pop(list[i].id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepairTile extends StatelessWidget {
  const _RepairTile({required this.record, required this.onTap});

  final CarRepairRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final status = WorkStatus.info(r.workStatusId);
    final label = r.workStatusLabel ?? status.label;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'งานซ่อม #${r.id} · ${formatThaiDate(r.date)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          StatusChip(StatusInfo(label, status.color)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (r.presets.isEmpty)
            const Text(
              'ไม่มีข้อมูลรายการ',
              style: TextStyle(color: Colors.grey),
            )
          else
            Text(
              r.presets.map((p) => '• $p').join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.speed, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                r.mileage == null ? '-' : '${formatNumber(r.mileage)} กม.',
              ),
              const Spacer(),
              Text(
                'ชำระแล้ว ฿${formatMoney(r.paidAmount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
