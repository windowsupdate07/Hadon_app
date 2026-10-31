import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import '../auth/auth_provider.dart';
import 'part_form_page.dart';
import 'part_model.dart';

enum _PartSort {
  partName('ชื่อสินค้า'),
  number('รหัสสินค้า'),
  stockAsc('คงเหลือ น้อย → มาก'),
  stockDesc('คงเหลือ มาก → น้อย'),
  priceDesc('ราคา สูง → ต่ำ');

  const _PartSort(this.label);

  final String label;
}

enum _StockFilter { all, outOfStock, inStock }

class PartsPage extends StatefulWidget {
  const PartsPage({super.key});

  @override
  State<PartsPage> createState() => _PartsPageState();
}

class _PartsPageState extends State<PartsPage> {
  late final PartsApi _api;
  late Future<List<Part>> _future;
  List<Part> _parts = const [];
  String _query = '';
  int _page = 0;
  _PartSort _sort = _PartSort.partName;
  _StockFilter _filter = _StockFilter.all;

  @override
  void initState() {
    super.initState();
    _api = PartsApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<List<Part>> _load() async {
    final list = await _api.findAll();
    _parts = list;
    return list;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  List<Part> _apply(List<Part> all) {
    final list = all.where((p) {
      if (_query.isNotEmpty && !p.matches(_query)) {
        return false;
      }
      switch (_filter) {
        case _StockFilter.outOfStock:
          return p.amount <= 0;
        case _StockFilter.inStock:
          return p.amount > 0;
        case _StockFilter.all:
          return true;
      }
    }).toList();
    int byName(Part a, Part b) => a.displayName.compareTo(b.displayName);
    switch (_sort) {
      case _PartSort.partName:
        list.sort(byName);
      case _PartSort.number:
        list.sort((a, b) => (a.partNumber ?? '').compareTo(b.partNumber ?? ''));
      case _PartSort.stockAsc:
        list.sort((a, b) {
          final c = a.amount.compareTo(b.amount);
          return c != 0 ? c : byName(a, b);
        });
      case _PartSort.stockDesc:
        list.sort((a, b) {
          final c = b.amount.compareTo(a.amount);
          return c != 0 ? c : byName(a, b);
        });
      case _PartSort.priceDesc:
        list.sort((a, b) => b.pricePerUnit.compareTo(a.pricePerUnit));
    }
    return list;
  }

  Future<void> _openForm([Part? part]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartFormPage(part: part, existing: _parts),
      ),
    );
    if (saved == true && mounted) {
      AppDialogs.toast(context, 'บันทึกข้อมูลเรียบร้อยแล้ว');
      await _refresh();
    }
  }

  Future<void> _delete(Part part) async {
    final ok = await AppDialogs.confirmDelete(
      context,
      'สินค้า "${part.displayName}"',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(part.id);
      return true;
    }, successMessage: 'ลบข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _showDetail(Part part) async {
    final canManage = context.read<AuthProvider>().employee?.canManage ?? false;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                part.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Divider(),
              InfoRow('รหัสสินค้า', part.partNumber),
              InfoRow('ชื่อ (ไทย)', part.nameTh),
              InfoRow('ชื่อ (อังกฤษ)', part.nameEn),
              InfoRow(
                'คงเหลือ',
                '${formatNumber(part.amount)} ${part.unitName ?? ''}',
                bold: true,
              ),
              InfoRow('ราคาต่อหน่วย', '${formatMoney(part.pricePerUnit)} บาท'),
              InfoRow('ค่าบริการ', '${formatMoney(part.serviceFee)} บาท'),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canManage) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.of(context).pop('delete'),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('ลบ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop('edit'),
                      icon: const Icon(Icons.edit),
                      label: const Text('แก้ไข'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (action == 'edit') {
      await _openForm(part);
    } else if (action == 'delete') {
      await _delete(part);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'สินค้าคงคลัง',
      actions: [
        PopupMenuButton<_PartSort>(
          icon: const Icon(Icons.sort),
          tooltip: 'เรียงลำดับ',
          initialValue: _sort,
          onSelected: (s) => setState(() {
            _sort = s;
            _page = 0;
          }),
          itemBuilder: (_) => [
            for (final s in _PartSort.values)
              PopupMenuItem(value: s, child: Text(s.label)),
          ],
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'เพิ่มสินค้า',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหารหัส / ชื่อสินค้า (ไทย/อังกฤษ)',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip('ทั้งหมด', _StockFilter.all),
                _filterChip('สินค้าหมด', _StockFilter.outOfStock),
                _filterChip('มีสินค้า', _StockFilter.inStock),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Part>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลสินค้า',
              builder: (context, data) => _buildList(_apply(data)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _StockFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() {
          _filter = value;
          _page = 0;
        }),
      ),
    );
  }

  Widget _buildList(List<Part> parts) {
    if (parts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 80), EmptyView()],
      );
    }
    final pageCount = (parts.length / PageBar.pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final start = page * PageBar.pageSize;
    final items = parts.skip(start).take(PageBar.pageSize).toList();
    final outCount = parts.where((p) => p.amount <= 0).length;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'ทั้งหมด ${parts.length} รายการ'
              '${outCount > 0 ? ' · สินค้าหมด $outCount รายการ' : ''}',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        if (i == items.length + 1) {
          return PageBar(
            page: page,
            pageCount: pageCount,
            onChanged: (p) => setState(() => _page = p),
          );
        }
        return _PartTile(
          part: items[i - 1],
          onTap: () => _showDetail(items[i - 1]),
        );
      },
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.part, required this.onTap});

  final Part part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = part.amount <= 0;
    final stockColor = out ? Colors.red : Colors.green.shade700;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: out ? Colors.red.shade50 : null,
      child: ListTile(
        onTap: onTap,
        title: Text(
          part.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                part.partNumber ?? '-',
                if (part.nameEn != null && part.nameEn != part.displayName)
                  part.nameEn!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'ราคา ${formatMoney(part.pricePerUnit)} · '
              'ค่าบริการ ${formatMoney(part.serviceFee)}',
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatNumber(part.amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: stockColor,
              ),
            ),
            Text(
              out ? 'สินค้าหมด' : (part.unitName ?? 'คงเหลือ'),
              style: TextStyle(fontSize: 12, color: stockColor),
            ),
          ],
        ),
      ),
    );
  }
}
