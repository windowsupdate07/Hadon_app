import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'car_form_page.dart';
import 'car_models.dart';
import 'cars_api.dart';

class CarsPage extends StatefulWidget {
  const CarsPage({super.key});

  @override
  State<CarsPage> createState() => _CarsPageState();
}

class _CarsPageState extends State<CarsPage> {
  late final CarsApi _api = CarsApi(context.read<ApiClient>());
  late Future<List<Car>> _future = _api.findAll();
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

  Future<void> _openForm({Car? car}) async {
    final changed = await showCarForm(context, car: car);
    if (changed == true && mounted) {
      _refresh();
    }
  }

  Future<void> _openCustomer(int id) async {
    await context.push('/customers/$id');
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ข้อมูลรถยนต์',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรถยนต์'),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาทะเบียน / จังหวัด / ยี่ห้อ / รุ่น / เจ้าของ / VIN',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          Expanded(
            child: AsyncBody<List<Car>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (list) => list.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลรถยนต์',
              builder: (context, all) {
                final list = _query.isEmpty
                    ? all
                    : all.where((c) => c.matches(_query)).toList();
                if (list.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyView(message: 'ไม่พบรถยนต์ที่ค้นหา'),
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
                    final car = items[i];
                    return _CarTile(
                      car: car,
                      onTap: () => _openForm(car: car),
                      onOpenCustomer: car.customerId == null
                          ? null
                          : () => _openCustomer(car.customerId!),
                      onOpenRepair: (id) => context.push('/repairs/$id'),
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

class _CarTile extends StatelessWidget {
  const _CarTile({
    required this.car,
    required this.onTap,
    required this.onOpenCustomer,
    required this.onOpenRepair,
  });

  /// Max repair jobs listed in the menu.
  static const _maxRepairs = 5;

  final Car car;
  final VoidCallback onTap;
  final VoidCallback? onOpenCustomer;
  final ValueChanged<int> onOpenRepair;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final owner = car.customer;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Icon(Icons.directions_car, color: scheme.onSecondaryContainer),
      ),
      title: Text(
        car.plateWithProvince,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(car.brandModel),
          Row(
            children: [
              const Icon(Icons.person, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  owner == null
                      ? 'ไม่พบข้อมูลเจ้าของ'
                      : [owner.fullName, ?owner.tel].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<int>(
        icon: Badge(
          isLabelVisible: car.repairIds.isNotEmpty,
          label: Text('${car.repairIds.length}'),
          child: const Icon(Icons.more_vert),
        ),
        onSelected: (v) {
          if (v == -1) {
            onTap();
          } else if (v == 0) {
            onOpenCustomer?.call();
          } else {
            onOpenRepair(v);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: -1,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('แก้ไขข้อมูลรถ'),
            ),
          ),
          PopupMenuItem(
            value: 0,
            enabled: onOpenCustomer != null,
            child: const ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('ข้อมูลเจ้าของรถ'),
            ),
          ),
          if (car.repairIds.isNotEmpty) const PopupMenuDivider(),
          for (final id in car.repairIds.take(_maxRepairs))
            PopupMenuItem(
              value: id,
              child: ListTile(
                leading: const Icon(Icons.car_repair),
                title: Text('งานซ่อม #$id'),
              ),
            ),
        ],
      ),
    );
  }
}
