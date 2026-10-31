import 'package:flutter/material.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../quotation_models.dart';
import '../quotations_api.dart';

/// Bottom sheet listing cars (with owner) for a quotation.
/// Shows cars of [modelId] first (`GET /cars/by-model/:id`), with a switch to
/// list every car (`GET /cars`).
Future<CarOption?> showCarPicker(
  BuildContext context, {
  required QuotationsApi api,
  int? modelId,
}) {
  return showModalBottomSheet<CarOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CarPickerSheet(api: api, modelId: modelId),
  );
}

class _CarPickerSheet extends StatefulWidget {
  const _CarPickerSheet({required this.api, this.modelId});

  final QuotationsApi api;
  final int? modelId;

  @override
  State<_CarPickerSheet> createState() => _CarPickerSheetState();
}

class _CarPickerSheetState extends State<_CarPickerSheet> {
  late bool _all = widget.modelId == null;
  late Future<List<CarOption>> _future = _load();
  String _query = '';

  Future<List<CarOption>> _load() => _all || widget.modelId == null
      ? widget.api.allCars()
      : widget.api.carsByModel(widget.modelId!);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'เลือกรถยนต์ของลูกค้า',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SearchField(
            hint: 'ค้นหาทะเบียน / ชื่อลูกค้า / เบอร์โทร / VIN',
            onChanged: (v) => setState(() => _query = v),
          ),
          if (widget.modelId != null)
            SwitchListTile(
              dense: true,
              title: const Text('แสดงรถทุกรุ่น'),
              value: _all,
              onChanged: (v) => setState(() {
                _all = v;
                _future = _load();
              }),
            ),
          Expanded(
            child: FutureBuilder<List<CarOption>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(
                    error: snap.error!,
                    onRetry: () => setState(() {
                      _future = _load();
                    }),
                  );
                }
                final cars = snap.data!
                    .where((c) => _query.isEmpty || c.matches(_query))
                    .toList();
                if (cars.isEmpty) {
                  return EmptyView(
                    message: _all
                        ? 'ไม่พบข้อมูลรถยนต์'
                        : 'ไม่พบรถยนต์รุ่นนี้ ลองเปิด "แสดงรถทุกรุ่น"',
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  itemCount: cars.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = cars[i];
                    final noOwner = c.customerId == null;
                    return ListTile(
                      enabled: !noOwner,
                      leading: const Icon(Icons.directions_car_outlined),
                      title: Text(c.plate.isEmpty ? 'รถ #${c.id}' : c.plate),
                      subtitle: Text(
                        '${c.brandModel}\n'
                        '${noOwner ? 'ไม่มีข้อมูลเจ้าของ' : c.owner}'
                        '${c.ownerTel == null ? '' : ' · โทร. ${c.ownerTel}'}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.of(context).pop(c),
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
