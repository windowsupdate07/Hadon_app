import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../repair_models.dart';
import '../repairs_api.dart';
import 'inline_error.dart';

/// Latest timeline entries (`GET /repair/logs/:id`) with a link to the full
/// timeline page.
class RepairTimelineSection extends StatefulWidget {
  const RepairTimelineSection({
    super.key,
    required this.api,
    required this.repairId,
    this.preview = 3,
  });

  final RepairsApi api;
  final int repairId;
  final int preview;

  @override
  State<RepairTimelineSection> createState() => _RepairTimelineSectionState();
}

class _RepairTimelineSectionState extends State<RepairTimelineSection> {
  late Future<List<RepairLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.logs(widget.repairId);
  }

  void _reload() {
    setState(() => _future = widget.api.logs(widget.repairId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RepairLog>>(
      future: _future,
      builder: (context, snap) {
        final logs = snap.data ?? const <RepairLog>[];
        Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError) {
          child = InlineError(error: snap.error!, onRetry: _reload);
        } else if (logs.isEmpty) {
          child = const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'ไม่พบประวัติการดำเนินการ',
              style: TextStyle(color: Colors.grey),
            ),
          );
        } else {
          child = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, log) in logs.take(widget.preview).indexed)
                RepairLogTile(
                  log: log,
                  isLast: i == widget.preview - 1 || i == logs.length - 1,
                ),
            ],
          );
        }
        return SectionCard(
          title: 'Timeline ดำเนินการ',
          trailing: snap.hasData && logs.isNotEmpty
              ? TextButton(
                  onPressed: () => openRepairTimeline(
                    context,
                    api: widget.api,
                    repairId: widget.repairId,
                  ),
                  child: Text('ดูทั้งหมด (${logs.length})'),
                )
              : null,
          child: child,
        );
      },
    );
  }
}

Future<void> openRepairTimeline(
  BuildContext context, {
  required RepairsApi api,
  required int repairId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RepairTimelinePage(api: api, repairId: repairId),
    ),
  );
}

/// Full history of a repair (and of its quotation, via ReferenceID).
class RepairTimelinePage extends StatefulWidget {
  const RepairTimelinePage({
    super.key,
    required this.api,
    required this.repairId,
  });

  final RepairsApi api;
  final int repairId;

  @override
  State<RepairTimelinePage> createState() => _RepairTimelinePageState();
}

class _RepairTimelinePageState extends State<RepairTimelinePage> {
  late Future<List<RepairLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.logs(widget.repairId);
  }

  Future<void> _refresh() async {
    final future = widget.api.logs(widget.repairId);
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Timeline งานซ่อม #${widget.repairId}')),
      body: AsyncBody<List<RepairLog>>(
        future: _future,
        onRefresh: _refresh,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'ไม่พบประวัติการดำเนินการ',
        builder: (context, logs) => ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: logs.length,
          itemBuilder: (context, i) =>
              RepairLogTile(log: logs[i], isLast: i == logs.length - 1),
        ),
      ),
    );
  }
}

/// One timeline entry: coloured dot + action/module, details, who and when.
class RepairLogTile extends StatelessWidget {
  const RepairLogTile({super.key, required this.log, this.isLast = false});

  final RepairLog log;
  final bool isLast;

  static (Color, IconData) _style(String action) {
    if (action.contains('สร้าง')) {
      return (Colors.green, Icons.add_circle);
    }
    if (action.contains('แก้ไข')) {
      return (Colors.orange, Icons.edit);
    }
    if (action.contains('ยกเลิก')) {
      return (Colors.red, Icons.cancel);
    }
    if (action.contains('ลบ')) {
      return (Colors.red, Icons.delete);
    }
    if (action.contains('สถานะ')) {
      return (Colors.blue, Icons.swap_horiz);
    }
    return (Colors.indigo, Icons.info);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = _style(log.action);
    final rows = log.jsonRows;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color,
                  child: Icon(icon, size: 14, color: Colors.white),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(StatusInfo(log.action, color)),
                      Text(
                        log.module,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (rows != null && rows.isNotEmpty)
                    _JsonRows(rows: rows)
                  else
                    Text(log.details ?? '-'),
                  const SizedBox(height: 4),
                  Text(
                    '${log.employeeName ?? 'ระบบอัตโนมัติ'} · '
                    '${formatThaiDateTime(log.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the `updates` array of a part edit, like the web's table.
class _JsonRows extends StatelessWidget {
  const _JsonRows({required this.rows});

  final List<Map<String, dynamic>> rows;

  static const _labels = {
    'NumOfUse': 'จำนวน',
    'PricePerUnit': 'ราคา/หน่วย',
    'ServiceFee': 'ค่าแรง',
    'Discount': 'ส่วนลด',
    'isDiscount': 'ประเภทส่วนลด',
    'ItemName': 'ชื่อรายการ',
  };

  static String _value(String key, dynamic v) {
    if (key == 'isDiscount') {
      return asInt(v) == 1 ? 'บาท' : 'เปอร์เซ็นต์';
    }
    if (key == 'PricePerUnit' || key == 'ServiceFee' || key == 'Discount') {
      return formatMoney(asDouble(v));
    }
    return v?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _name(r),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final e in _labels.entries)
                    if (r.containsKey(e.key) && e.key != 'ItemName')
                      TextSpan(
                        text: ' · ${e.value} ${_value(e.key, r[e.key])}',
                      ),
                ],
              ),
              style: small,
            ),
          ),
      ],
    );
  }

  static String _name(Map<String, dynamic> r) {
    final part = asMap(r['part']);
    return asString(part?['PartName_th']) ??
        asString(part?['PartName']) ??
        asString(r['ItemName']) ??
        (r['PartID'] != null
            ? 'อะไหล่ #${r['PartID']}'
            : 'รายการ #${r['RepairPartID'] ?? '-'}');
  }
}
