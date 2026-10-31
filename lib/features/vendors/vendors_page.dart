import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import '../auth/auth_provider.dart';
import 'vendor_form_page.dart';
import 'vendor_models.dart';
import 'vendors_api.dart';

class VendorsPage extends StatefulWidget {
  const VendorsPage({super.key});

  @override
  State<VendorsPage> createState() => _VendorsPageState();
}

class _VendorsPageState extends State<VendorsPage> {
  late final VendorsApi _api;
  late Future<List<Vendor>> _future;
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _api = VendorsApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<List<Vendor>> _load() async {
    final list = await _api.findAll();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  Future<void> _openForm([Vendor? vendor]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VendorFormPage(vendor: vendor)),
    );
    if (saved == true && mounted) {
      AppDialogs.toast(context, 'บันทึกข้อมูลเรียบร้อยแล้ว');
      await _refresh();
    }
  }

  Future<void> _delete(Vendor vendor) async {
    final ok = await AppDialogs.confirmDelete(
      context,
      'คู่ค้า "${vendor.name}"',
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(vendor.id);
      return true;
    }, successMessage: 'ลบข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _showDetail(Vendor vendor) async {
    final canManage = context.read<AuthProvider>().employee?.canManage ?? false;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(vendor.name, style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              InfoRow('ประเภท', vendor.typeName),
              InfoRow('เลขประจำตัว', vendor.idNumber),
              InfoRow('เบอร์โทรศัพท์', vendor.tel),
              InfoRow('ที่อยู่', vendor.address?.fullText),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canManage) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.of(context).pop('delete'),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('ลบ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop('edit'),
                      icon: const Icon(Icons.edit),
                      label: const Text('แก้ไข'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (action == 'edit') {
      await _openForm(vendor);
    } else if (action == 'delete') {
      await _delete(vendor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ข้อมูลคู่ค้า',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'เพิ่มคู่ค้า',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาชื่อ / เบอร์โทร / เลขประจำตัว / ประเภท',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          Expanded(
            child: AsyncBody<List<Vendor>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลคู่ค้า',
              builder: (context, data) => _buildList(
                _query.isEmpty
                    ? data
                    : data.where((v) => v.matches(_query)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Vendor> vendors) {
    if (vendors.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 80), EmptyView()],
      );
    }
    final pageCount = (vendors.length / PageBar.pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final items = vendors
        .skip(page * PageBar.pageSize)
        .take(PageBar.pageSize)
        .toList();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'ทั้งหมด ${vendors.length} รายการ',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        if (i == items.length + 1) {
          return PageBar(
            page: page,
            pageCount: pageCount,
            onChanged: (p) => setState(() => _page = p),
          );
        }
        final v = items[i - 1];
        final juristic = v.typeId == 2;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            onTap: () => _showDetail(v),
            leading: CircleAvatar(
              child: Icon(juristic ? Icons.business : Icons.person),
            ),
            title: Text(v.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    v.typeName ?? '-',
                    if (v.tel != null) 'โทร ${v.tel}',
                  ].join(' · '),
                ),
                if (v.address != null)
                  Text(
                    v.address!.fullText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
