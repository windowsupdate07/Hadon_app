import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/utils/json.dart';
import '../parts/lookup_dropdown.dart';
import 'vendor_models.dart';

/// Mutable state of a vendor address form. Owned (and disposed) by the
/// widget that creates it.
class VendorAddressInput {
  VendorAddressInput([VendorAddress? a])
    : line1 = TextEditingController(text: a?.line1 ?? ''),
      line2 = TextEditingController(text: a?.line2 ?? ''),
      provinceId = a?.provinceId,
      districtId = a?.districtId,
      subDistrictId = a?.subDistrictId,
      zipcode = a?.zipcode;

  final TextEditingController line1;
  final TextEditingController line2;
  int? provinceId;
  int? districtId;
  int? subDistrictId;

  /// Display only; the server derives it from the sub-district.
  String? zipcode;

  /// Dropdowns that are still loading (or failed) have no validator, so
  /// callers check this after `Form.validate()`.
  bool get isComplete =>
      line1.text.trim().isNotEmpty &&
      provinceId != null &&
      districtId != null &&
      subDistrictId != null;

  /// `Addresses` columns (without OwnerID / AddressTypeID / IsDefault).
  Map<String, dynamic> toJson() {
    final l2 = line2.text.trim();
    return {
      'Line1': line1.text.trim(),
      'Line2': l2.isEmpty ? null : l2,
      'ProvinceID': provinceId,
      'DistrictID': districtId,
      'SubDistrictID': subDistrictId,
    };
  }

  void dispose() {
    line1.dispose();
    line2.dispose();
  }
}

/// Line1 / Line2 + cascading Province → District → Sub-district dropdowns,
/// all required like the web form. Must be placed inside a [Form].
class VendorAddressFields extends StatefulWidget {
  const VendorAddressFields({super.key, required this.data});

  final VendorAddressInput data;

  @override
  State<VendorAddressFields> createState() => _VendorAddressFieldsState();
}

class _VendorAddressFieldsState extends State<VendorAddressFields> {
  static const _gap = SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<Lookups>();
    final d = widget.data;
    final provinceId = d.provinceId;
    final districtId = d.districtId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: d.line1,
          decoration: const InputDecoration(
            labelText: 'ที่อยู่ *',
            hintText: 'บ้านเลขที่ หมู่ อาคาร',
          ),
          textInputAction: TextInputAction.next,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'กรุณากรอกที่อยู่' : null,
        ),
        _gap,
        TextFormField(
          controller: d.line2,
          decoration: const InputDecoration(labelText: 'ถนน / ซอย'),
        ),
        _gap,
        LookupDropdown(
          label: 'จังหวัด',
          required: true,
          load: lookups.provinces,
          value: provinceId,
          onChanged: (o) {
            if (o?.id == d.provinceId) {
              return;
            }
            setState(() {
              d.provinceId = o?.id;
              d.districtId = null;
              d.subDistrictId = null;
              d.zipcode = null;
            });
          },
        ),
        _gap,
        LookupDropdown(
          key: ValueKey('district-$provinceId'),
          label: 'อำเภอ / เขต',
          required: true,
          hint: provinceId == null ? 'กรุณาเลือกจังหวัดก่อน' : null,
          load: provinceId == null ? null : () => lookups.districts(provinceId),
          value: districtId,
          onChanged: (o) {
            if (o?.id == d.districtId) {
              return;
            }
            setState(() {
              d.districtId = o?.id;
              d.subDistrictId = null;
              d.zipcode = null;
            });
          },
        ),
        _gap,
        LookupDropdown(
          key: ValueKey('sub-$provinceId-$districtId'),
          label: 'ตำบล / แขวง',
          required: true,
          hint: districtId == null ? 'กรุณาเลือกอำเภอก่อน' : null,
          load: districtId == null
              ? null
              : () => lookups.subDistricts(districtId),
          value: d.subDistrictId,
          onChanged: (o) => setState(() {
            d.subDistrictId = o?.id;
            d.zipcode = asString(o?.raw['Zipcode']);
          }),
        ),
        _gap,
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'รหัสไปรษณีย์',
            enabled: false,
          ),
          child: Text(d.zipcode ?? '-'),
        ),
      ],
    );
  }
}

/// Add / edit address dialog. Returns the address columns or null.
Future<Map<String, dynamic>?> showVendorAddressDialog(
  BuildContext context, {
  VendorAddress? address,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VendorAddressDialog(address: address),
  );
}

class _VendorAddressDialog extends StatefulWidget {
  const _VendorAddressDialog({this.address});

  final VendorAddress? address;

  @override
  State<_VendorAddressDialog> createState() => _VendorAddressDialogState();
}

class _VendorAddressDialogState extends State<_VendorAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late final VendorAddressInput _data = VendorAddressInput(widget.address);

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate() && _data.isComplete) {
      Navigator.of(context).pop(_data.toJson());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.address == null ? 'เพิ่มที่อยู่' : 'แก้ไขที่อยู่'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              VendorAddressFields(data: _data),
              if (widget.address == null) ...[
                const SizedBox(height: 12),
                const Text(
                  'ที่อยู่ใหม่จะถูกตั้งเป็นที่อยู่หลัก',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}
