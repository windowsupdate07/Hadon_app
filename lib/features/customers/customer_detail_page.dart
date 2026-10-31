import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../cars/car_form_page.dart';
import '../cars/car_models.dart';
import '../cars/car_repair_history.dart';
import '../cars/cars_api.dart';
import 'customer_form_page.dart';
import 'customer_models.dart';
import 'customers_api.dart';
import 'widgets/address_form_fields.dart';
import 'widgets/customer_form_fields.dart';

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late final CustomersApi _api = CustomersApi(context.read<ApiClient>());
  late final CarsApi _carsApi = CarsApi(context.read<ApiClient>());
  late Future<Customer> _future = _load();

  /// Last loaded customer, used by the app bar actions.
  Customer? _customer;

  /// Customer + addresses from `/customers/:id`, cars from
  /// `/cars/by-customer/:id` (which, unlike the nested cars, include repair
  /// ids). Falls back to the nested cars if the second call fails.
  Future<Customer> _load() async {
    final carsFuture = _carsApi
        .findByCustomer(widget.customerId)
        .then<List<Car>?>((v) => v, onError: (_) => null);
    var c = await _api.findOne(widget.customerId);
    final cars = await carsFuture;
    if (cars != null) {
      c = c.withCars(cars);
    }
    if (mounted) {
      setState(() => _customer = c);
    }
    return c;
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

  Future<void> _edit() async {
    final c = _customer;
    if (c == null) {
      return;
    }
    final id = await showCustomerForm(context, customer: c);
    if (id != null && mounted) {
      _refresh();
    }
  }

  Future<void> _delete() async {
    final c = _customer;
    if (c == null) {
      return;
    }
    final extra = c.cars.isEmpty
        ? ''
        : '\n(ลูกค้ารายนี้มีรถยนต์ ${c.cars.length} คัน ข้อมูลรถจะไม่ถูกลบ)';
    final confirmed = await AppDialogs.confirm(
      context,
      message: 'ท่านต้องการลบลูกค้า ${c.fullName} ใช่หรือไม่?$extra',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final ok = await runWithProgress<bool>(
      context,
      () async {
        await _api.remove(c.id);
        return true;
      },
      successMessage: 'ลบข้อมูลลูกค้าเรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      context.pop();
    }
  }

  // ---------------------------------------------------------------- address

  Future<void> _addAddress(Customer c) async {
    final res = await showAddressDialog(
      context,
      showDefaultOption: c.addresses.isNotEmpty,
    );
    if (res == null || !mounted) {
      return;
    }
    final previousDefault = c.defaultAddress;
    final ok = await runWithProgress<bool>(
      context,
      () async {
        // The server always makes the new address the default one.
        await _api.addAddress(c.id, res.json);
        if (!res.makeDefault && previousDefault != null) {
          await _api.setDefaultAddress(previousDefault.id);
        }
        return true;
      },
      successMessage: 'เพิ่มที่อยู่เรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      _refresh();
    }
  }

  Future<void> _editAddress(Address a) async {
    final res = await showAddressDialog(context, address: a);
    if (res == null || !mounted) {
      return;
    }
    final ok = await runWithProgress<bool>(
      context,
      () async {
        await _api.updateAddress(a.id, res.json);
        return true;
      },
      successMessage: 'แก้ไขที่อยู่เรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      _refresh();
    }
  }

  Future<void> _setDefault(Address a) async {
    final ok = await runWithProgress<bool>(
      context,
      () async {
        await _api.setDefaultAddress(a.id);
        return true;
      },
      successMessage: 'ตั้งเป็นที่อยู่หลักเรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      _refresh();
    }
  }

  Future<void> _deleteAddress(Customer c, Address a) async {
    final confirmed = await AppDialogs.confirmDelete(context, 'ที่อยู่นี้');
    if (!confirmed || !mounted) {
      return;
    }
    final others = c.addresses.where((e) => e.id != a.id).toList();
    final ok = await runWithProgress<bool>(
      context,
      () async {
        await _api.removeAddress(a.id);
        // Keep one default address (used by invoices) when possible.
        if (a.isDefault && others.isNotEmpty) {
          await _api.setDefaultAddress(others.first.id);
        }
        return true;
      },
      successMessage: 'ลบที่อยู่เรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      _refresh();
    }
  }

  // -------------------------------------------------------------------- car

  Future<void> _openCar(Customer c, {Car? car}) async {
    final changed = await showCarForm(context, car: car, owner: c);
    if (changed == true && mounted) {
      _refresh();
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer?.fullName ?? 'ข้อมูลลูกค้า'),
        actions: [
          if (_customer != null) ...[
            IconButton(
              tooltip: 'แก้ไข',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            if (canManage)
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ],
      ),
      body: AsyncBody<Customer>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, c) => ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            SectionCard(
              title: 'ข้อมูลลูกค้า',
              child: Column(
                children: [
                  InfoRow('ชื่อ-นามสกุล', c.fullName, bold: true),
                  InfoRow('เบอร์โทรศัพท์', c.tel),
                  InfoRow('เลขประจำตัว', c.idNumber),
                  _RatingRow(c.rating),
                ],
              ),
            ),
            _addressSection(c),
            _carSection(c),
          ],
        ),
      ),
    );
  }

  Widget _addressSection(Customer c) {
    return SectionCard(
      title: 'ที่อยู่ (${c.addresses.length})',
      trailing: TextButton.icon(
        onPressed: () => _addAddress(c),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่ม'),
      ),
      child: c.addresses.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ยังไม่มีที่อยู่',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              children: [
                for (final a in c.addresses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.isDefault ? Icons.home : Icons.home_outlined,
                      color: a.isDefault
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    title: Text(
                      a.fullText,
                      style: a.isDefault
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                    subtitle: a.isDefault
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: _Tag('ที่อยู่หลัก'),
                          )
                        : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'default':
                            _setDefault(a);
                          case 'edit':
                            _editAddress(a);
                          case 'delete':
                            _deleteAddress(c, a);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!a.isDefault)
                          const PopupMenuItem(
                            value: 'default',
                            child: ListTile(
                              leading: Icon(Icons.star_outline),
                              title: Text('ตั้งเป็นที่อยู่หลัก'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('แก้ไข'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('ลบ', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _carSection(Customer c) {
    return SectionCard(
      title: 'รถยนต์ (${c.cars.length})',
      trailing: TextButton.icon(
        onPressed: () => _openCar(c),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่ม'),
      ),
      child: c.cars.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ยังไม่มีรถยนต์',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              children: [
                for (final car in c.cars)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.directions_car),
                    title: Text(
                      car.plateWithProvince,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        car.brandModelColor,
                        if (car.vin != null) 'VIN ${car.vin}',
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'ประวัติการซ่อม',
                      onPressed: () => showCarRepairHistory(context, car),
                      icon: Badge(
                        isLabelVisible: car.hasRepairs,
                        label: Text('${car.repairIds.length}'),
                        child: const Icon(Icons.history),
                      ),
                    ),
                    onTap: () => _openCar(c, car: car),
                  ),
              ],
            ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow(this.rating);

  final CustomerRating rating;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(
            width: 120,
            child: Text('ระดับ', style: TextStyle(color: Colors.grey)),
          ),
          RatingDot(rating),
          const SizedBox(width: 6),
          Text(rating.label),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
