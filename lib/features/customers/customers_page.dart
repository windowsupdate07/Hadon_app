import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'customer_form_page.dart';
import 'customer_models.dart';
import 'customers_api.dart';
import 'widgets/customer_form_fields.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final CustomersApi _api = CustomersApi(context.read<ApiClient>());
  late Future<List<Customer>> _future = _api.findAll();
  String _query = '';
  int _page = 0;

  Future<void> _refresh() async {
    final future = _api.findAll();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  Future<void> _openDetail(int id) async {
    await context.push('/customers/$id');
    if (mounted) {
      _refresh();
    }
  }

  Future<void> _create() async {
    final id = await showCustomerForm(context);
    if (id == null || !mounted) {
      return;
    }
    if (id > 0) {
      await _openDetail(id);
    } else {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ข้อมูลลูกค้า',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add),
        label: const Text('เพิ่มลูกค้า'),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาชื่อ / เบอร์โทร / เลขบัตร / ทะเบียน / รุ่นรถ',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          Expanded(
            child: AsyncBody<List<Customer>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (list) => list.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลลูกค้า',
              builder: (context, all) {
                final list = _query.isEmpty
                    ? all
                    : all.where((c) => c.matches(_query)).toList();
                if (list.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyView(message: 'ไม่พบลูกค้าที่ค้นหา'),
                    ],
                  );
                }
                final pageCount = (list.length / PageBar.pageSize).ceil();
                final page = min(_page, pageCount - 1);
                final items = list
                    .skip(page * PageBar.pageSize)
                    .take(PageBar.pageSize)
                    .toList();
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'ทั้งหมด ${list.length} รายการ',
                              style: const TextStyle(color: Colors.grey),
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
                    final c = items[i];
                    return _CustomerTile(
                      customer: c,
                      onTap: () => _openDetail(c.id),
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

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final plates = c.cars.map((e) => e.plate).join(', ');
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.person, color: scheme.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          RatingDot(c.rating, size: 10),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(c.tel ?? '-'),
            ],
          ),
          if (plates.isNotEmpty)
            Text(plates, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: Badge(
        isLabelVisible: c.cars.isNotEmpty,
        label: Text('${c.cars.length}'),
        child: Icon(
          Icons.directions_car,
          color: c.cars.isEmpty ? Colors.grey.shade400 : scheme.primary,
        ),
      ),
    );
  }
}
