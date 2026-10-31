import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'repair_models.dart';
import 'repairs_api.dart';
import 'widgets/repair_header_card.dart';

class RepairsPage extends StatefulWidget {
  const RepairsPage({super.key});

  @override
  State<RepairsPage> createState() => _RepairsPageState();
}

class _RepairsPageState extends State<RepairsPage> {
  late final RepairsApi _api;
  late Future<List<Repair>> _future;

  /// null = all statuses.
  int? _status;
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _api = RepairsApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<List<Repair>> _load() async {
    final list = await _api.findAll();
    // Newest first.
    list.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da != null && db != null && da != db) {
        return db.compareTo(da);
      }
      return b.id.compareTo(a.id);
    });
    return list;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  Future<void> _open(Repair r) async {
    await context.push('/repairs/${r.id}');
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ซ่อมรถยนต์',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/intake');
          if (mounted) {
            _refresh();
          }
        },
        icon: const Icon(Icons.garage_rounded),
        label: const Text('รับรถเข้า'),
      ),
      actions: [
        IconButton(
          tooltip: 'รีเฟรช',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาทะเบียนรถ / ชื่อลูกค้า / เลขที่งานซ่อม / ใบเสนอราคา',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          Expanded(
            child: AsyncBody<List<Repair>>(
              future: _future,
              onRefresh: _refresh,
              builder: _buildList,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Repair> all) {
    final searched = _query.isEmpty
        ? all
        : all.where((r) => r.matches(_query)).toList();

    final counts = <int, int>{};
    for (final r in searched) {
      final s = r.workStatusId ?? 0;
      counts[s] = (counts[s] ?? 0) + 1;
    }

    final filtered = _status == null
        ? searched
        : searched.where((r) => r.workStatusId == _status).toList();

    const pageSize = PageBar.pageSize;
    final pageCount = math.max(1, (filtered.length / pageSize).ceil());
    final page = math.min(_page, pageCount - 1);
    final pageItems = filtered.skip(page * pageSize).take(pageSize).toList();

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _chip('ทั้งหมด', searched.length, null),
              for (final s in WorkStatus.all)
                _chip(WorkStatus.info(s).label, counts[s] ?? 0, s),
            ],
          ),
        ),
        Expanded(
          child: pageItems.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    EmptyView(message: 'ไม่พบงานซ่อม'),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: pageItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _RepairTile(
                    repair: pageItems[i],
                    onTap: () => _open(pageItems[i]),
                  ),
                ),
        ),
        PageBar(
          page: page,
          pageCount: pageCount,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }

  Widget _chip(String label, int count, int? status) {
    final selected = _status == status;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => setState(() {
          _status = status;
          _page = 0;
        }),
      ),
    );
  }
}

class _RepairTile extends StatelessWidget {
  const _RepairTile({required this.repair, required this.onTap});

  final Repair repair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = repair;
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: const Icon(Icons.directions_car),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${r.plate}${r.provinceName == null ? '' : ' ${r.provinceName}'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '#${r.id}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.brandModel} · ${r.customerName ?? '-'}',
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(formatThaiDate(r.date)),
              if (r.receiveType == ReceiveType.appointment &&
                  r.receiveAppointmentDate != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.event, size: 14, color: Colors.blue),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    'นัดรับ ${formatThaiDateTime(r.receiveAppointmentDate)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                    ),
                  ),
                ),
              ] else if (r.receiveType == ReceiveType.wait) ...[
                const SizedBox(width: 6),
                Text(
                  'รอรับ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Spacer(),
              StatusChip(workStatusInfo(r)),
            ],
          ),
        ],
      ),
    );
  }
}
