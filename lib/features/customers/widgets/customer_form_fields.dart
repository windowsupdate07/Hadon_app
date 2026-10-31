import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../customer_models.dart';
import 'lookup_dropdown.dart';

/// Mutable state of the customer fields. Owned (and disposed) by the parent.
class CustomerFormData {
  CustomerFormData({
    this.titleId,
    String? name,
    String? surname,
    String? idNumber,
    String? tel,
  })  : name = TextEditingController(text: name),
        surname = TextEditingController(text: surname),
        idNumber = TextEditingController(text: idNumber),
        tel = TextEditingController(text: tel);

  factory CustomerFormData.fromCustomer(Customer c) => CustomerFormData(
        titleId: c.titleId,
        name: c.name,
        surname: c.surname,
        idNumber: c.idNumber,
        tel: c.tel,
      );

  int? titleId;
  final TextEditingController name;
  final TextEditingController surname;
  final TextEditingController idNumber;
  final TextEditingController tel;

  /// Customer columns for `POST/PUT /customers` and `/cars/with-customer`.
  Map<String, dynamic> toJson() {
    String? clean(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    return {
      'CustomerTitleID': titleId,
      'CustomerName': clean(name),
      'CustomerSurname': clean(surname),
      'IDNumber': clean(idNumber),
      'CustomerTel': clean(tel),
    };
  }

  void dispose() {
    name.dispose();
    surname.dispose();
    idNumber.dispose();
    tel.dispose();
  }
}

/// Title, name, surname, ID number and phone. Must be inside a [Form].
class CustomerFormFields extends StatefulWidget {
  const CustomerFormFields({super.key, required this.data});

  final CustomerFormData data;

  @override
  State<CustomerFormFields> createState() => _CustomerFormFieldsState();
}

class _CustomerFormFieldsState extends State<CustomerFormFields> {
  static const _gap = SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LookupDropdown(
          label: 'คำนำหน้า',
          load: context.read<Lookups>().customerTitles,
          sourceKey: 'customerTitle',
          value: d.titleId,
          required: true,
          onChanged: (o) => setState(() => d.titleId = o?.id),
        ),
        _gap,
        TextFormField(
          controller: d.name,
          decoration: const InputDecoration(labelText: 'ชื่อ'),
          textInputAction: TextInputAction.next,
          validator: (v) => (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อ' : null,
        ),
        _gap,
        TextFormField(
          controller: d.surname,
          decoration: const InputDecoration(labelText: 'นามสกุล'),
          textInputAction: TextInputAction.next,
        ),
        _gap,
        TextFormField(
          controller: d.tel,
          decoration: const InputDecoration(
            labelText: 'เบอร์โทรศัพท์',
            prefixIcon: Icon(Icons.phone),
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            LengthLimitingTextInputFormatter(12),
          ],
          textInputAction: TextInputAction.next,
          validator: (v) {
            final digits = (v ?? '').replaceAll('-', '');
            if (digits.isEmpty) {
              return 'กรุณากรอกเบอร์โทรศัพท์';
            }
            if (digits.length < 9 || digits.length > 10) {
              return 'เบอร์โทรศัพท์ไม่ถูกต้อง';
            }
            return null;
          },
        ),
        _gap,
        TextFormField(
          controller: d.idNumber,
          decoration: const InputDecoration(
            labelText: 'เลขประจำตัวประชาชน / เลขผู้เสียภาษี (ถ้ามี)',
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
      ],
    );
  }
}
