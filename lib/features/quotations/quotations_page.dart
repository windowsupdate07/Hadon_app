import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'quotation_models.dart';
import 'quotations_api.dart';
import 'widgets/quotation_form_dialog.dart';

enum _Filter { all, pending, approved }

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key});

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  late final QuotationsApi _api = QuotationsApi(context.read<ApiClient>());
  late Future<List<Quotation>> _future;
  String _query = '';
  _Filter _filter = _Filter.all;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Quotation>> _load() async {
    final list = await _api.findAll();
    // Newest first: by date, then by the running number in the ID.
    list.sort((a, b) {
      final da = a.date ?? DateTime(0);
      final db = b.date ?? DateTime(0);
      final c = db.compareTo(da);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return list;
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

  Future<void> _create() async {
    final input = await showCreateQuotationDialog(context);
    if (input == null || !mounted) {
      return;
    }
    final id = await runWithProgress(
      context,
      () => _api.create(
        brandId: input.brandId,
        modelId: input.modelId,
        comment: input.comment,
      ),
    );
    if (id == null || !mounted) {
      return;
    }
    await context.push('/quotations/${Uri.encodeComponent(id)}');
    if (mounted) {
      _refresh();
    }
  }

  List<Quotation> _filtered(List<Quotation> all) {
    return all.where((q) {
      if (_filter == _Filter.pending && q.isApproved) {
        return false;
      }
      if (_filter == _Filter.approved && !q.isApproved) {
        return false;
      }
      return _query.isEmpty || q.matches(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ใบเสนอราคา',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('สร้างใบเสนอราคา'),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาเลขที่ / ยี่ห้อ-รุ่น / ทะเบียน',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.all => 'ทั้งหมด',
                      _Filter.pending => 'รออนุมัติ',
                      _Filter.approved => 'อนุมัติแล้ว',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() {
                      _filter = f;
                      _page = 0;
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Quotation>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => _filtered(d).isEmpty,
              emptyMessage: 'ไม่พบใบเสนอราคา',
              builder: (context, data) {
                final list = _filtered(data);
                final pageCount = (list.length / PageBar.pageSize).ceil();
                final page = _page.clamp(0, pageCount - 1);
                final items = list
                    .skip(page * PageBar.pageSize)
                    .take(PageBar.pageSize)
                    .toList();
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return PageBar(
                        page: page,
                        pageCount: pageCount,
                        onChanged: (p) => setState(() => _page = p),
                      );
                    }
                    return _QuotationTile(
                      quotation: items[i],
                      onTap: () async {
                        await context.push(
                          '/quotations/${Uri.encodeComponent(items[i].id)}',
                        );
                        if (mounted) {
                          _refresh();
                        }
                      },
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

class _QuotationTile extends StatelessWidget {
  const _QuotationTile({required this.quotation, required this.onTap});

  final Quotation quotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = quotation;
    final plates = q.repairs.map((r) => r.plate).where((p) => p.isNotEmpty);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
        title: Text(q.id, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.brandModel.isEmpty ? '-' : q.brandModel),
            if (plates.isNotEmpty) Text('ทะเบียน ${plates.join(', ')}'),
            Text(
              '${formatThaiDate(q.date)} · ${q.employeeName ?? '-'}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: q.isApproved
            ? const StatusChip(StatusInfo('อนุมัติแล้ว', Colors.green))
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
