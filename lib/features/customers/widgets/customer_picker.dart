import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../customer_models.dart';
import '../customers_api.dart';

/// Bottom sheet to search and pick a customer (name / phone / ID / plate).
Future<Customer?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CustomerPickerSheet(),
  );
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  late Future<List<Customer>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = CustomersApi(context.read<ApiClient>()).findAll();
  }

  void _reload() {
    setState(() {
      _future = CustomersApi(context.read<ApiClient>()).findAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Text('เลือกลูกค้า', style: Theme.of(context).textTheme.titleMedium),
          SearchField(
            hint: 'ค้นหาชื่อ / เบอร์โทร / เลขบัตร / ทะเบียนรถ',
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(error: snap.error!, onRetry: _reload);
                }
                final list = snap.data!
                    .where((c) => _query.isEmpty || c.matches(_query))
                    .toList();
                if (list.isEmpty) {
                  return const EmptyView();
                }
                return ListView.separated(
                  controller: scroll,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final plates = c.cars.map((e) => e.plate).join(', ');
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.fullName),
                      subtitle: Text(
                        [
                          c.tel ?? '-',
                          if (plates.isNotEmpty) plates,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
