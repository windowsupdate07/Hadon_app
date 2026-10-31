import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../parts/lookup_dropdown.dart';
import 'vendor_address_fields.dart';
import 'vendor_models.dart';
import 'vendors_api.dart';

/// Create (vendor == null) or edit a vendor. On create the first address is
/// entered here (required by `POST /vendors`); afterwards addresses are
/// managed on the vendor detail page. Pops `true` after a successful save.
class VendorFormPage extends StatefulWidget {
  const VendorFormPage({super.key, this.vendor});

  final Vendor? vendor;

  @override
  State<VendorFormPage> createState() => _VendorFormPageState();
}

class _VendorFormPageState extends State<VendorFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _idNumber;
  late final TextEditingController _tel;
  final _address = VendorAddressInput();
  int? _typeId;
  late VendorRating _rating;

  bool get _isEdit => widget.vendor != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    _name = TextEditingController(text: v?.name ?? '');
    _idNumber = TextEditingController(text: v?.idNumber ?? '');
    _tel = TextEditingController(text: v?.tel ?? '');
    _typeId = v?.typeId;
    _rating = v?.rating ?? VendorRating.green;
  }

  @override
  void dispose() {
    _name.dispose();
    _idNumber.dispose();
    _tel.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController c) {
    final s = c.text.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_typeId == null) {
      await AppDialogs.warn(context, 'กรุณาเลือกประเภทคู่ค้า');
      return;
    }
    if (!_isEdit && !_address.isComplete) {
      await AppDialogs.warn(
        context,
        'กรุณากรอกที่อยู่ และเลือกจังหวัด อำเภอ/เขต ตำบล/แขวง ให้ครบถ้วน',
      );
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      message: _isEdit
          ? 'ท่านต้องการแก้ไขข้อมูล ใช่หรือไม่?'
          : 'ท่านต้องการเพิ่มข้อมูล ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }

    final vendor = <String, dynamic>{
      'VendorName': _name.text.trim(),
      'VendorTypeID': _typeId,
      'IDNumber': _nullIfEmpty(_idNumber),
      'VendorTel': _nullIfEmpty(_tel),
      'RatingColor': _rating.value,
    };

    final api = VendorsApi(context.read<ApiClient>());
    final saved = await runWithProgress(context, () async {
      if (_isEdit) {
        await api.update(widget.vendor!.id, vendor);
      } else {
        await api.create(vendor, _address.toJson());
      }
      return true;
    });
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<Lookups>();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขข้อมูลคู่ค้า' : 'เพิ่มคู่ค้า'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'ข้อมูลคู่ค้า',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            gap,
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'ชื่อคู่ค้า *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อคู่ค้า' : null,
            ),
            gap,
            LookupDropdown(
              label: 'ประเภทคู่ค้า',
              required: true,
              load: lookups.vendorTypes,
              value: _typeId,
              onChanged: (o) => setState(() => _typeId = o?.id),
            ),
            gap,
            TextFormField(
              controller: _idNumber,
              decoration: const InputDecoration(
                labelText: 'เลขประจำตัวผู้เสียภาษี / เลขบัตรประชาชน',
                counterText: '',
              ),
              keyboardType: TextInputType.number,
              maxLength: 13,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isNotEmpty && s.length != 13) {
                  return 'กรุณากรอกให้ครบ 13 หลัก';
                }
                return null;
              },
            ),
            gap,
            TextFormField(
              controller: _tel,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทรศัพท์',
                counterText: '',
              ),
              keyboardType: TextInputType.phone,
              maxLength: 20,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+, ]')),
              ],
            ),
            gap,
            DropdownButtonFormField<VendorRating>(
              initialValue: _rating,
              decoration: const InputDecoration(labelText: 'ระดับ'),
              items: [
                for (final r in VendorRating.values)
                  DropdownMenuItem(
                    value: r,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 14, color: r.color),
                        const SizedBox(width: 8),
                        Text(r.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (r) => setState(() => _rating = r ?? _rating),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 24),
              Text('ที่อยู่', style: Theme.of(context).textTheme.titleMedium),
              gap,
              VendorAddressFields(data: _address),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
