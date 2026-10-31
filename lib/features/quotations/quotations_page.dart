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

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key});

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  late final QuotationsApi _api = QuotationsApi(context.read<ApiClient>());
  late Future<List<Quotation>> _future;
  String _query = '';

  /// null = ทั้งหมด.
  QuotationStage? _stage;
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
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  Future<void> _create() async {
    final input = await openCreateQuotationForm(context, api: _api);
    if (input == null || !mounted) {
      return;
    }
    final id = await runWithProgress(context, () => _api.create(input));
    if (id == null || !mounted) {
      return;
    }
    await context.push('/quotations/${Uri.encodeComponent(id)}');
    if (mounted) {
      _refresh();
    }
  }

  List<Quotation> _searched(List<Quotation> all) =>
      all.where((q) => _query.isEmpty || q.matches(_query)).toList();

  List<Quotation> _filtered(List<Quotation> all) =>
      _searched(all).where((q) => _stage == null || q.stage == _stage).toList();

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
            hint: 'ค้นหาเลขที่ / ทะเบียน / ลูกค้า / เบอร์โทร',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          FutureBuilder<List<Quotation>>(
            future: _future,
            builder: (context, snap) {
              final searched = _searched(snap.data ?? const []);
              int count(QuotationStage? s) => s == null
                  ? searched.length
                  : searched.where((q) => q.stage == s).length;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final s in <QuotationStage?>[
                      null,
                      ...QuotationStage.values,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${s?.label ?? 'ทั้งหมด'} (${count(s)})'),
                          selected: _stage == s,
                          onSelected: (_) => setState(() {
                            _stage = s;
                            _page = 0;
                          }),
                        ),
                      ),
                  ],
                ),
              );
            },
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

  static Color _color(QuotationStage s) => switch (s) {
    QuotationStage.pending => Colors.blueGrey,
    QuotationStage.waitingRepair => Colors.blue,
    QuotationStage.waitingParts => Colors.orange,
    QuotationStage.sent => Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    final q = quotation;
    final stage = q.isCancelledRepair
        ? const StatusInfo('ยกเลิกการซ่อม', Colors.red)
        : StatusInfo(q.stage.label, _color(q.stage));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      q.id,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  StatusChip(stage),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [q.plate, q.brandModel].where((s) => s.isNotEmpty).join(' · '),
              ),
              if (q.customerDisplayName.isNotEmpty)
                Text(
                  q.customerDisplayName,
                  style: const TextStyle(color: Colors.grey),
                ),
              const SizedBox(height: 4),
              Text(
                '${formatThaiDate(q.date)} · ${q.employeeName ?? '-'}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
