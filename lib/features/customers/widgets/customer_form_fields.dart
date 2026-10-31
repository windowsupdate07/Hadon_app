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
    String? ratingColor,
  })  : rating = CustomerRating.of(ratingColor),
        name = TextEditingController(text: name),
        surname = TextEditingController(text: surname),
        idNumber = TextEditingController(text: idNumber),
        tel = TextEditingController(text: tel);

  factory CustomerFormData.fromCustomer(Customer c) => CustomerFormData(
        titleId: c.titleId,
        name: c.name,
        surname: c.surname,
        idNumber: c.idNumber,
        tel: c.tel,
        ratingColor: c.ratingColor,
      );

  int? titleId;

  /// `RatingColor`, defaults to green like the web.
  CustomerRating rating;
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
      'RatingColor': rating.value,
    };
  }

  /// Trimmed ID number, or null when empty.
  String? get idNumberValue {
    final v = idNumber.text.trim();
    return v.isEmpty ? null : v;
  }

  void dispose() {
    name.dispose();
    surname.dispose();
    idNumber.dispose();
    tel.dispose();
  }
}

/// Title, name, surname, phone, ID number and rating. Must be inside a
/// [Form].
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
        _gap,
        DropdownButtonFormField<CustomerRating>(
          initialValue: d.rating,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ระดับลูกค้า'),
          items: [
            for (final r in CustomerRating.all)
              DropdownMenuItem(
                value: r,
                child: Row(
                  children: [
                    RatingDot(r),
                    const SizedBox(width: 8),
                    Text(r.label),
                  ],
                ),
              ),
          ],
          onChanged: (r) => setState(() => d.rating = r ?? d.rating),
        ),
      ],
    );
  }
}

/// Small coloured circle for [CustomerRating] (the web's `mdi-circle`).
class RatingDot extends StatelessWidget {
  const RatingDot(this.rating, {super.key, this.size = 12});

  final CustomerRating rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ระดับ: ${rating.label}',
      child: Icon(Icons.circle, size: size, color: rating.color),
    );
  }
}
