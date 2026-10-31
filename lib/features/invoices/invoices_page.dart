import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'invoice_models.dart';
import 'invoices_api.dart';

const _statuses = [
  InvoiceStatus.pendingConfirm,
  InvoiceStatus.pendingPayment,
  InvoiceStatus.paid,
  InvoiceStatus.cancelled,
];

/// Normalises the newer backend's 99 (cancelled) to 4.
int? _statusKey(int? id) => id == 99 ? InvoiceStatus.cancelled : id;

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  late final InvoicesApi _api = InvoicesApi(context.read<ApiClient>());
  late Future<List<Invoice>> _future;
  String _query = '';
  int? _status;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Invoice>> _load() async {
    final list = await _api.findAll();
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

  List<Invoice> _searched(List<Invoice> all) =>
      all.where((i) => _query.isEmpty || i.matches(_query)).toList();

  List<Invoice> _filtered(List<Invoice> all) => _searched(all)
      .where((i) => _status == null || _statusKey(i.statusId) == _status)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ใบแจ้งหนี้',
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาเลขที่ / งานซ่อม / ลูกค้า / ทะเบียน',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          FutureBuilder<List<Invoice>>(
            future: _future,
            builder: (context, snap) {
              final searched = _searched(snap.data ?? const []);
              int count(int? s) => s == null
                  ? searched.length
                  : searched.where((i) => _statusKey(i.statusId) == s).length;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final s in <int?>[null, ..._statuses])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${s == null ? 'ทั้งหมด' : InvoiceStatus.info(s).label}'
                            ' (${count(s)})',
                          ),
                          selected: _status == s,
                          onSelected: (_) => setState(() {
                            _status = s;
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
            child: AsyncBody<List<Invoice>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => _filtered(d).isEmpty,
              emptyMessage: 'ไม่พบใบแจ้งหนี้',
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
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return PageBar(
                        page: page,
                        pageCount: pageCount,
                        onChanged: (p) => setState(() => _page = p),
                      );
                    }
                    final inv = items[i];
                    return _InvoiceTile(
                      invoice: inv,
                      onTap: () async {
                        await context.push(
                          '/invoices/${Uri.encodeComponent(inv.id)}',
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

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.onTap});

  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
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
                      inv.id,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  StatusChip(InvoiceStatus.info(inv.statusId)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                inv.customerDisplayName.isEmpty ? '-' : inv.customerDisplayName,
              ),
              Text(
                [inv.plate, inv.brandModel].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatThaiDate(inv.date)} · งานซ่อม #${inv.repairId ?? '-'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${formatMoney(inv.totals.grandTotal)} บาท',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
