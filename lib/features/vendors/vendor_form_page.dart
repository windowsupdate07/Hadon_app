import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../parts/lookup_dropdown.dart';
import 'vendor_models.dart';
import 'vendors_api.dart';

/// Create (vendor == null) or edit a vendor and its address.
/// Pops `true` after a successful save.
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
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  int? _typeId;
  int? _provinceId;
  int? _districtId;
  int? _subDistrictId;
  String? _zipcode;

  bool get _isEdit => widget.vendor != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    final a = v?.address;
    _name = TextEditingController(text: v?.name ?? '');
    _idNumber = TextEditingController(text: v?.idNumber ?? '');
    _tel = TextEditingController(text: v?.tel ?? '');
    _line1 = TextEditingController(text: a?.line1 ?? '');
    _line2 = TextEditingController(text: a?.line2 ?? '');
    _typeId = v?.typeId;
    _provinceId = a?.provinceId;
    _districtId = a?.districtId;
    _subDistrictId = a?.subDistrictId;
    _zipcode = a?.zipcode;
  }

  @override
  void dispose() {
    _name.dispose();
    _idNumber.dispose();
    _tel.dispose();
    _line1.dispose();
    _line2.dispose();
    super.dispose();
  }

  bool get _hasAddressInput =>
      _line1.text.trim().isNotEmpty ||
      _line2.text.trim().isNotEmpty ||
      _provinceId != null;

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
    final needAddress = _hasAddressInput || widget.vendor?.address != null;
    if (needAddress &&
        (_provinceId == null ||
            _districtId == null ||
            _subDistrictId == null)) {
      await AppDialogs.warn(
        context,
        'กรุณาเลือกจังหวัด อำเภอ/เขต และตำบล/แขวง ให้ครบถ้วน',
      );
      return;
    }

    final vendor = <String, dynamic>{
      'VendorName': _name.text.trim(),
      'VendorTypeID': _typeId,
      'IDNumber': _nullIfEmpty(_idNumber),
      'VendorTel': _nullIfEmpty(_tel),
    };
    final address = needAddress
        ? <String, dynamic>{
            'Line1': _nullIfEmpty(_line1),
            'Line2': _nullIfEmpty(_line2),
            'ProvinceID': _provinceId,
            'DistrictID': _districtId,
            'SubDistrictID': _subDistrictId,
          }
        : null;

    final api = VendorsApi(context.read<ApiClient>());
    final ok = await runWithProgress(context, () async {
      if (_isEdit) {
        await api.update(
          widget.vendor!.id,
          vendor,
          addressId: widget.vendor!.address?.id,
          address: address,
        );
      } else {
        await api.create(vendor, address);
      }
      return true;
    });
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<Lookups>();
    const gap = SizedBox(height: 12);
    final provinceId = _provinceId;
    final districtId = _districtId;
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
            const SizedBox(height: 24),
            Text('ที่อยู่', style: Theme.of(context).textTheme.titleMedium),
            gap,
            TextFormField(
              controller: _line1,
              decoration: const InputDecoration(
                labelText: 'ที่อยู่ (บ้านเลขที่ หมู่ อาคาร)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            gap,
            TextFormField(
              controller: _line2,
              decoration: const InputDecoration(labelText: 'ถนน / ซอย'),
              onChanged: (_) => setState(() {}),
            ),
            gap,
            LookupDropdown(
              label: 'จังหวัด',
              load: lookups.provinces,
              value: _provinceId,
              onChanged: (o) => setState(() {
                if (o?.id != _provinceId) {
                  _provinceId = o?.id;
                  _districtId = null;
                  _subDistrictId = null;
                  _zipcode = null;
                }
              }),
            ),
            gap,
            LookupDropdown(
              key: ValueKey('district-$provinceId'),
              label: 'อำเภอ / เขต',
              hint: provinceId == null ? 'กรุณาเลือกจังหวัดก่อน' : null,
              load: provinceId == null
                  ? null
                  : () => lookups.districts(provinceId),
              value: _districtId,
              onChanged: (o) => setState(() {
                if (o?.id != _districtId) {
                  _districtId = o?.id;
                  _subDistrictId = null;
                  _zipcode = null;
                }
              }),
            ),
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: LookupDropdown(
                    key: ValueKey('sub-$provinceId-$districtId'),
                    label: 'ตำบล / แขวง',
                    hint: districtId == null ? 'กรุณาเลือกอำเภอก่อน' : null,
                    load: districtId == null
                        ? null
                        : () => lookups.subDistricts(districtId),
                    value: _subDistrictId,
                    onChanged: (o) => setState(() {
                      _subDistrictId = o?.id;
                      _zipcode = o?.raw['Zipcode']?.toString();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'รหัสไปรษณีย์',
                      enabled: false,
                    ),
                    child: Text(_zipcode ?? '-'),
                  ),
                ),
              ],
            ),
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
