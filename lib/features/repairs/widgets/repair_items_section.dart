import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../parts/part_picker.dart';
import '../repair_models.dart';
import '../repairs_api.dart';
import 'add_repair_item_sheet.dart';
import 'edit_repair_part_dialog.dart';
import 'inline_error.dart';

/// Repair items (RepairDetail) with their parts, plus add / edit / delete.
class RepairItemsSection extends StatefulWidget {
  const RepairItemsSection({
    super.key,
    required this.api,
    required this.repair,
    required this.editable,
    required this.canDelete,
  });

  final RepairsApi api;
  final Repair repair;

  /// False once the job is finished or cancelled.
  final bool editable;

  /// Deleting items / parts is limited to admin & manager.
  final bool canDelete;

  @override
  State<RepairItemsSection> createState() => _RepairItemsSectionState();
}

class _RepairItemsSectionState extends State<RepairItemsSection> {
  late Future<List<RepairItem>> _future;

  RepairsApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _future = _api.items(widget.repair.id);
  }

  void _reload() {
    setState(() => _future = _api.items(widget.repair.id));
  }

  Future<void> _addItem() async {
    final created = await showAddRepairItemSheet(
      context,
      api: _api,
      repair: widget.repair,
    );
    if (created && mounted) {
      _reload();
    }
  }

  Future<void> _deleteItem(RepairItem item) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการลบ?',
      message:
          'ท่านต้องการลบรายการซ่อม "${item.categoryName ?? '-'}" '
          'และอะไหล่ทั้งหมด ${item.parts.length} รายการ ใช่หรือไม่?\n'
          '(จำนวนอะไหล่จะถูกคืนเข้าสต๊อก)',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.deleteItem(item.id);
      return true;
    }, successMessage: 'ลบรายการซ่อมเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  Future<void> _addPart(RepairItem item) async {
    final picked = await showPartPicker(context);
    if (picked == null || !mounted) {
      return;
    }
    final qty = picked.quantity.round();
    if (qty <= 0) {
      await AppDialogs.warn(context, 'จำนวนต้องเป็นจำนวนเต็มที่มากกว่า 0');
      return;
    }
    if (!mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.addPart(
        item.id,
        NewRepairPart(part: picked.part, numOfUse: qty),
      );
      return true;
    }, successMessage: 'เพิ่มอะไหล่เรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  Future<void> _editPart(RepairPartLine line) async {
    final fields = await showEditRepairPartDialog(context, line);
    if (fields == null || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.updatePart(line.id, fields);
      return true;
    }, successMessage: 'บันทึกข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  Future<void> _deletePart(RepairPartLine line) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'ยืนยันการลบ?',
      message:
          'ท่านต้องการลบอะไหล่ "${line.displayName}" ใช่หรือไม่?\n'
          '(จำนวนอะไหล่จะถูกคืนเข้าสต๊อก)',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.deletePart(line.id);
      return true;
    }, successMessage: 'ลบอะไหล่เรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'รายการซ่อม',
      trailing: widget.editable
          ? TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มรายการ'),
            )
          : null,
      child: FutureBuilder<List<RepairItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return InlineError(error: snap.error!, onRetry: _reload);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'ยังไม่มีรายการซ่อม',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          final grandTotal = items.fold<double>(0, (s, i) => s + i.total);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) _itemCard(item),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'รวมทั้งสิ้น (ก่อน VAT)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${formatMoney(grandTotal)} บาท',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _itemCard(RepairItem item) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.categoryName ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (item.presetName != null)
                        Text(
                          'พรีเซ็ต: ${item.presetName}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (widget.editable)
                  IconButton(
                    tooltip: 'เพิ่มอะไหล่',
                    onPressed: () => _addPart(item),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                if (widget.editable && widget.canDelete)
                  IconButton(
                    tooltip: 'ลบรายการซ่อม',
                    onPressed: () => _deleteItem(item),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
              ],
            ),
            if (item.parts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'ไม่มีอะไหล่',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (final p in item.parts) _partRow(p),
            const Divider(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('รวมรายการ')),
                  Text(
                    formatMoney(item.total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partRow(RepairPartLine p) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final details = <String>[
      '${formatNumber(p.numOfUse)} ${p.unitName ?? ''} × ${formatMoney(p.pricePerUnit)}',
      if (p.serviceFee > 0) 'ค่าบริการ ${formatMoney(p.serviceFee)}',
      if (p.discount > 0)
        p.discountIsBaht
            ? 'ส่วนลด ${formatMoney(p.discount)} ฿'
            : 'ส่วนลด ${formatNumber(p.discount)}%',
    ];
    return InkWell(
      onTap: widget.editable ? () => _editPart(p) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.displayName),
                  if (p.partNumber != null) Text(p.partNumber!, style: small),
                  Text(details.join(' · '), style: small),
                  const SizedBox(height: 4),
                  StatusChip(PartStatus.info(p.partStatusId)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                formatMoney(p.total),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.editable)
              PopupMenuButton<String>(
                tooltip: 'ตัวเลือก',
                onSelected: (v) {
                  if (v == 'edit') {
                    _editPart(p);
                  } else if (v == 'delete') {
                    _deletePart(p);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                  if (widget.canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('ลบ', style: TextStyle(color: Colors.red)),
                    ),
                ],
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
