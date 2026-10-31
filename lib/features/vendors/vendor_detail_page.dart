import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import 'vendor_address_fields.dart';
import 'vendor_form_page.dart';
import 'vendor_models.dart';
import 'vendors_api.dart';

/// Vendor info + address list (add / edit / set default / delete).
/// Pops `true` when the vendor was deleted.
class VendorDetailPage extends StatefulWidget {
  const VendorDetailPage({super.key, required this.vendorId});

  final int vendorId;

  @override
  State<VendorDetailPage> createState() => _VendorDetailPageState();
}

class _VendorDetailPageState extends State<VendorDetailPage> {
  late final VendorsApi _api;
  late Future<Vendor> _future;
  Vendor? _vendor;

  @override
  void initState() {
    super.initState();
    _api = VendorsApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<Vendor> _load() async {
    final v = await _api.findOne(widget.vendorId);
    if (mounted) {
      setState(() => _vendor = v);
    }
    return v;
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

  Future<void> _mutate(Future<void> Function() action, String message) async {
    final ok = await runWithProgress(context, () async {
      await action();
      return true;
    }, successMessage: message);
    if (ok == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _edit(Vendor v) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => VendorFormPage(vendor: v)));
    if (saved == true && mounted) {
      AppDialogs.toast(context, 'บันทึกข้อมูลเรียบร้อยแล้ว');
      await _refresh();
    }
  }

  Future<void> _delete(Vendor v) async {
    final ok = await AppDialogs.confirmDelete(context, 'คู่ค้า "${v.name}"');
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(v.id);
      return true;
    }, successMessage: 'ลบข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _addAddress(Vendor v) async {
    final json = await showVendorAddressDialog(context);
    if (json == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.addAddress(v.id, json),
      'เพิ่มที่อยู่เรียบร้อยแล้ว',
    );
  }

  Future<void> _editAddress(VendorAddress a) async {
    final json = await showVendorAddressDialog(context, address: a);
    if (json == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.updateAddress(a.id, json),
      'บันทึกข้อมูลเรียบร้อยแล้ว',
    );
  }

  Future<void> _setDefault(VendorAddress a) async {
    final ok = await AppDialogs.confirm(
      context,
      message: 'ตั้งที่อยู่นี้เป็นค่าเริ่มต้น ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(
      () => _api.setDefaultAddress(a.id),
      'ตั้งที่อยู่นี้เป็นค่าเริ่มต้นแล้ว',
    );
  }

  Future<void> _deleteAddress(Vendor v, VendorAddress a) async {
    final others = v.addresses.where((e) => e.id != a.id).toList();
    final ok = await AppDialogs.confirm(
      context,
      message: others.isEmpty
          ? 'นี่คือที่อยู่เดียวของคู่ค้ารายนี้ ท่านต้องการลบ ใช่หรือไม่?'
          : 'ท่านต้องการลบที่อยู่นี้ ใช่หรือไม่?',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() async {
      await _api.removeAddress(a.id);
      // Keep a default address (used by sale documents) when possible.
      if (a.isDefault && others.isNotEmpty) {
        await _api.setDefaultAddress(others.first.id);
      }
    }, 'ลบข้อมูลเรียบร้อยแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    final vendor = _vendor;
    return Scaffold(
      appBar: AppBar(
        title: Text(vendor?.name ?? 'ข้อมูลคู่ค้า'),
        actions: [
          if (vendor != null) ...[
            IconButton(
              tooltip: 'แก้ไข',
              icon: const Icon(Icons.edit),
              onPressed: () => _edit(vendor),
            ),
            if (canManage)
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(vendor),
              ),
          ],
        ],
      ),
      body: AsyncBody<Vendor>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, v) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            SectionCard(
              title: v.name,
              trailing: VendorRatingDot(v.rating, showLabel: true),
              child: Column(
                children: [
                  InfoRow('ประเภท', v.typeName),
                  InfoRow('เลขประจำตัว', v.idNumber),
                  InfoRow('เบอร์โทรศัพท์', v.tel),
                ],
              ),
            ),
            _addressSection(v),
          ],
        ),
      ),
    );
  }

  Widget _addressSection(Vendor v) {
    return SectionCard(
      title: 'ที่อยู่ (${v.addresses.length})',
      trailing: TextButton.icon(
        onPressed: () => _addAddress(v),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มที่อยู่'),
      ),
      child: v.addresses.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: EmptyView(message: 'ยังไม่มีที่อยู่'),
            )
          : Column(
              children: [
                for (final a in v.addresses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.isDefault ? Icons.star : Icons.place_outlined,
                      color: a.isDefault ? Colors.amber : null,
                    ),
                    title: Text(a.fullText.isEmpty ? '-' : a.fullText),
                    subtitle: a.isDefault ? const Text('ค่าเริ่มต้น') : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            _editAddress(a);
                          case 'default':
                            _setDefault(a);
                          case 'delete':
                            _deleteAddress(v, a);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('แก้ไข'),
                        ),
                        if (!a.isDefault)
                          const PopupMenuItem(
                            value: 'default',
                            child: Text('ตั้งเป็นค่าเริ่มต้น'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'ลบ',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Coloured dot for `RatingColor`, optionally with its Thai label.
class VendorRatingDot extends StatelessWidget {
  const VendorRatingDot(this.rating, {super.key, this.showLabel = false});

  final VendorRating rating;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final dot = Icon(Icons.circle, size: 14, color: rating.color);
    if (!showLabel) {
      return dot;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [dot, const SizedBox(width: 4), Text(rating.label)],
    );
  }
}
