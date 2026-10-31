import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../cars/car_form_page.dart';
import '../quotations/quotation_models.dart';
import '../quotations/quotations_api.dart';
import '../quotations/widgets/quotation_form_dialog.dart';

/// Vehicle intake ("รับรถเข้า"). In this system a car is received by opening
/// a quotation (printed as "ใบรับรถ"), taking the standard photos and then
/// sending it to repair from the quotation page. This page is the fast path:
/// find the car (or register a new one) → vehicle details → open the
/// quotation and continue on its detail page.
class IntakePage extends StatefulWidget {
  const IntakePage({super.key});

  @override
  State<IntakePage> createState() => _IntakePageState();
}

class _IntakeData {
  const _IntakeData(this.cars, this.openRepairs);

  final List<CarOption> cars;

  /// CarID → RepairID of a job that is neither finished nor cancelled.
  final Map<int, int> openRepairs;
}

class _IntakePageState extends State<IntakePage> {
  late final _api = QuotationsApi(context.read<ApiClient>());
  late Future<_IntakeData> _future = _load();
  String _query = '';

  Future<_IntakeData> _load() async {
    final results = await Future.wait([
      _api.allCars(),
      context.read<ApiClient>().get('/repair'),
    ]);
    final cars = results[0] as List<CarOption>
      // Newest first so a car registered a moment ago is at the top.
      ..sort((a, b) => b.id.compareTo(a.id));
    final open = <int, int>{};
    for (final r in asMapList(results[1])) {
      final carId = asInt(r['CarID']);
      final status = asInt(r['WorkStatusID']);
      final repairId = asInt(r['RepairID']);
      if (carId == null || repairId == null) {
        continue;
      }
      if (status != WorkStatus.success && status != WorkStatus.cancel) {
        open[carId] = repairId;
      }
    }
    return _IntakeData(cars, open);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _newCar() async {
    final saved = await showCarForm(context);
    if (saved == true && mounted) {
      await _refresh();
      if (mounted) {
        AppDialogs.toast(
          context,
          'เพิ่มรถแล้ว — เลือกรถคันใหม่ด้านบนเพื่อรับรถ',
        );
      }
    }
  }

  Future<void> _receive(CarOption car, int? openRepairId) async {
    if (openRepairId != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 40,
          ),
          title: const Text('รถคันนี้มีงานซ่อมค้างอยู่'),
          content: Text(
            'ใบรับรถ #$openRepairId ยังไม่เสร็จสิ้น ต้องการดูงานเดิมหรือรับรถเข้าใหม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ดูงานเดิม'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('รับรถเข้าใหม่'),
            ),
          ],
        ),
      );
      if (!mounted || proceed == null) {
        return;
      }
      if (!proceed) {
        context.push('/repairs/$openRepairId');
        return;
      }
    }
    final input = await openCreateQuotationForm(
      context,
      api: _api,
      title: 'รับรถเข้า',
      submitLabel: 'บันทึกรับรถ',
      initialCar: car,
    );
    if (input == null || !mounted) {
      return;
    }
    final id = await runWithProgress(context, () => _api.create(input));
    if (id == null || !mounted) {
      return;
    }
    AppDialogs.toast(
      context,
      'รับรถแล้ว — ถ่ายรูปรถ เพิ่มรายการ แล้วกดส่งซ่อม',
    );
    // Replace the intake page so "back" from the quotation returns home.
    context.pushReplacement('/quotations/${Uri.encodeComponent(id)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('รับรถเข้า')),
      body: Column(
        children: [
          const _StepsBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _newCar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('รถใหม่ / ลูกค้าใหม่'),
              ),
            ),
          ),
          SearchField(
            hint: 'ค้นหาทะเบียน / ชื่อลูกค้า / เบอร์โทร',
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: AsyncBody<_IntakeData>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => d.cars.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลรถ — กด "รถใหม่ / ลูกค้าใหม่"',
              builder: (context, data) {
                final cars = data.cars
                    .where((c) => _query.isEmpty || c.matches(_query))
                    .take(50)
                    .toList();
                if (cars.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyView(
                        message: 'ไม่พบรถที่ค้นหา — เพิ่มเป็นรถใหม่ได้',
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: cars.length,
                  itemBuilder: (context, i) {
                    final car = cars[i];
                    final openRepair = data.openRepairs[car.id];
                    return _CarTile(
                      car: car,
                      openRepairId: openRepair,
                      onTap: () => _receive(car, openRepair),
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
  const _CarTile({required this.car, required this.onTap, this.openRepairId});

  final CarOption car;
  final int? openRepairId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      car.brandModel,
      car.color,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.directions_car, color: theme.colorScheme.primary),
        ),
        title: Text(
          car.plate,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details),
            Text(
              '${car.owner}${car.ownerTel == null ? '' : ' · ${car.ownerTel}'}',
            ),
            if (openRepairId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StatusChip(
                  StatusInfo('มีงานซ่อมค้าง #$openRepairId', Colors.orange),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// "1 เลือกรถ → 2 ข้อมูลรถ → 3 ถ่ายรูป & ส่งซ่อม" guide strip.
class _StepsBar extends StatelessWidget {
  const _StepsBar();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    Widget step(String n, String label, {bool active = false}) {
      return Expanded(
        child: Column(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: active ? color : Colors.grey.shade300,
              child: Text(
                n,
                style: TextStyle(color: active ? Colors.white : Colors.black54),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: active ? color : Colors.black54,
                fontWeight: active ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          step('1', 'เลือกรถ', active: true),
          step('2', 'เลขไมล์ / ข้อมูลรถ'),
          step('3', 'ถ่ายรูป & ส่งซ่อม'),
        ],
      ),
    );
  }
}
