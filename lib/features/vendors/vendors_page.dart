import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'vendor_detail_page.dart';
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

  Future<void> _create() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VendorFormPage()));
    if (saved == true && mounted) {
      AppDialogs.toast(context, 'บันทึกข้อมูลเรียบร้อยแล้ว');
      await _refresh();
    }
  }

  Future<void> _openDetail(Vendor vendor) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VendorDetailPage(vendorId: vendor.id)),
    );
    // Vendor / addresses may have changed inside the detail page.
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ข้อมูลคู่ค้า',
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
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
            onTap: () => _openDetail(v),
            leading: CircleAvatar(
              child: Icon(juristic ? Icons.business : Icons.person),
            ),
            title: Row(
              children: [
                Expanded(child: Text(v.name)),
                VendorRatingDot(v.rating),
              ],
            ),
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
