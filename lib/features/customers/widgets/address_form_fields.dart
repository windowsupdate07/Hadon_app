import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../../../core/utils/json.dart';
import '../customer_models.dart';
import 'lookup_dropdown.dart';

/// Mutable state of an address form. Owned (and disposed) by the parent.
class AddressFormData {
  AddressFormData({
    String? line1,
    String? line2,
    this.provinceId,
    this.districtId,
    this.subDistrictId,
    this.zipcode,
  })  : line1 = TextEditingController(text: line1),
        line2 = TextEditingController(text: line2);

  factory AddressFormData.fromAddress(Address a) => AddressFormData(
        line1: a.line1,
        line2: a.line2,
        provinceId: a.provinceId,
        districtId: a.districtId,
        subDistrictId: a.subDistrictId,
        zipcode: a.zipcode,
      );

  final TextEditingController line1;
  final TextEditingController line2;
  int? provinceId;
  int? districtId;
  int? subDistrictId;

  /// Display only; the API derives it from the sub-district.
  String? zipcode;

  /// Address columns (without OwnerID / AddressTypeID / IsDefault).
  Map<String, dynamic> toJson() => {
        'Line1': line1.text.trim(),
        'Line2': line2.text.trim(),
        'ProvinceID': provinceId,
        'DistrictID': districtId,
        'SubDistrictID': subDistrictId,
      };

  void dispose() {
    line1.dispose();
    line2.dispose();
  }
}

/// Line1 / Line2 and cascading Province → District → Sub-district dropdowns
/// with the zipcode filled from the chosen sub-district. Must be placed
/// inside a [Form].
class AddressFormFields extends StatefulWidget {
  const AddressFormFields({super.key, required this.data});

  final AddressFormData data;

  @override
  State<AddressFormFields> createState() => _AddressFormFieldsState();
}

class _AddressFormFieldsState extends State<AddressFormFields> {
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
            labelText: 'ที่อยู่',
            hintText: 'บ้านเลขที่ หมู่ หมู่บ้าน ซอย',
          ),
          textInputAction: TextInputAction.next,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'กรุณากรอกที่อยู่' : null,
        ),
        _gap,
        TextFormField(
          controller: d.line2,
          decoration: const InputDecoration(
            labelText: 'ที่อยู่ (ต่อ)',
            hintText: 'ถนน / อื่น ๆ',
          ),
        ),
        _gap,
        LookupDropdown(
          label: 'จังหวัด',
          load: lookups.provinces,
          sourceKey: 'province',
          value: provinceId,
          required: true,
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
          label: 'อำเภอ/เขต',
          load: provinceId == null ? null : () => lookups.districts(provinceId),
          sourceKey: 'district-$provinceId',
          value: districtId,
          required: true,
          disabledHint: 'เลือกจังหวัดก่อน',
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
          label: 'ตำบล/แขวง',
          load: districtId == null
              ? null
              : () => lookups.subDistricts(districtId),
          sourceKey: 'subDistrict-$districtId',
          value: d.subDistrictId,
          required: true,
          disabledHint: 'เลือกอำเภอ/เขตก่อน',
          onChanged: (o) {
            setState(() {
              d.subDistrictId = o?.id;
              d.zipcode = asString(o?.raw['Zipcode']);
            });
          },
        ),
        _gap,
        InputDecorator(
          decoration: const InputDecoration(labelText: 'รหัสไปรษณีย์'),
          child: Text(d.zipcode ?? '-'),
        ),
      ],
    );
  }
}

/// Result of [showAddressDialog].
class AddressDialogResult {
  const AddressDialogResult(this.json, {this.makeDefault = true});

  /// Address columns, see [AddressFormData.toJson].
  final Map<String, dynamic> json;

  /// Whether the user wants this to be the default address.
  final bool makeDefault;
}

/// Add / edit address dialog. When [showDefaultOption] is true (adding to a
/// customer that already has addresses) a "set as default" switch is shown.
Future<AddressDialogResult?> showAddressDialog(
  BuildContext context, {
  Address? address,
  bool showDefaultOption = false,
}) {
  return showDialog<AddressDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddressDialog(
      address: address,
      showDefaultOption: showDefaultOption,
    ),
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({this.address, required this.showDefaultOption});

  final Address? address;
  final bool showDefaultOption;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late final AddressFormData _data = widget.address == null
      ? AddressFormData()
      : AddressFormData.fromAddress(widget.address!);
  bool _makeDefault = true;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      AddressDialogResult(_data.toJson(), makeDefault: _makeDefault),
    );
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
              AddressFormFields(data: _data),
              if (widget.address == null && widget.showDefaultOption)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ตั้งเป็นที่อยู่หลัก'),
                  value: _makeDefault,
                  onChanged: (v) => setState(() => _makeDefault = v),
                ),
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
