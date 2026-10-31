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
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  List<Invoice> _searched(List<Invoice> all) =>
      all.where((i) => _query.isEmpty || i.matches(_query)).toList();

  List<Invoice> _filtered(List<Invoice> all) => _searched(
    all,
  ).where((i) => _status == null || i.statusId == _status).toList();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ใบแจ้งหนี้',
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาเลขที่ / ใบเสนอราคา / ลูกค้า / ทะเบียน',
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
                  : searched.where((i) => i.statusId == s).length;
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

  /// Saved `Amount` (net total, set when confirmed / paid / cancelled). A
  /// draft has no amount yet: show the computed grand total before the
  /// pledge deduction (the list response has no pledges).
  static String _amountText(Invoice inv) {
    final amount = inv.amount;
    if (inv.statusId != InvoiceStatus.pendingConfirm &&
        amount != null &&
        amount > 0) {
      return '${formatMoney(amount)} บาท';
    }
    if (inv.isDeposit) {
      return '${formatMoney(amount)} บาท';
    }
    return '~${formatMoney(inv.totals().grandTotal)} บาท';
  }

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
                [
                  inv.plate,
                  inv.brandModel,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        formatThaiDate(inv.date),
                        if (inv.isDeposit) 'เงินมัดจำ',
                        if (inv.repairId != null) 'งานซ่อม #${inv.repairId}',
                        ?inv.quotationId,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    _amountText(inv),
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
