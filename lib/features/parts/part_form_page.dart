import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import 'lookup_dropdown.dart';
import 'part_model.dart';

/// Create (part == null) or edit a part. Pops `true` after a successful save.
class PartFormPage extends StatefulWidget {
  const PartFormPage({super.key, this.part, this.existing = const []});

  final Part? part;

  /// Current list, used to warn about duplicated part numbers.
  final List<Part> existing;

  @override
  State<PartFormPage> createState() => _PartFormPageState();
}

class _PartFormPageState extends State<PartFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _nameTh;
  late final TextEditingController _nameEn;
  late final TextEditingController _amount;
  late final TextEditingController _price;
  late final TextEditingController _fee;
  int? _unitId;

  bool get _isEdit => widget.part != null;

  /// Seeded UnitID 1; the web form defaults to it too.
  static const _defaultUnitId = 1;

  @override
  void initState() {
    super.initState();
    final p = widget.part;
    _number = TextEditingController(text: p?.partNumber ?? '');
    _nameTh = TextEditingController(text: p?.nameTh ?? '');
    _nameEn = TextEditingController(text: p?.nameEn ?? '');
    _amount = TextEditingController(text: p == null ? '0' : '${p.stock}');
    _price = TextEditingController(
      text: p == null ? '' : _plain(p.pricePerUnit),
    );
    _fee = TextEditingController(text: p == null ? '0' : _plain(p.serviceFee));
    _unitId = p == null ? _defaultUnitId : p.unitId;
  }

  @override
  void dispose() {
    _number.dispose();
    _nameTh.dispose();
    _nameEn.dispose();
    _amount.dispose();
    _price.dispose();
    _fee.dispose();
    super.dispose();
  }

  /// 120.0 -> "120", 12.5 -> "12.5" (no thousands separators, for editing).
  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  String? _validateMoney(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n < 0) {
      return 'กรุณากรอกจำนวนเงินให้ถูกต้อง';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final number = _number.text.trim();
    final duplicated = widget.existing.any(
      (p) =>
          p.id != widget.part?.id &&
          (p.partNumber ?? '').toLowerCase() == number.toLowerCase(),
    );
    if (duplicated) {
      final ok = await AppDialogs.confirm(
        context,
        title: 'รหัสสินค้าซ้ำ',
        message: 'มีรหัสสินค้า "$number" อยู่แล้ว ต้องการบันทึกต่อ ใช่หรือไม่?',
      );
      if (!ok || !mounted) {
        return;
      }
    }

    final api = PartsApi(context.read<ApiClient>());
    final amount = int.parse(_amount.text.trim());
    final nameEn = _nameEn.text.trim();
    final body = <String, dynamic>{
      'PartNumber': number,
      'PartName_th': _nameTh.text.trim(),
      'PartName_en': nameEn.isEmpty ? null : nameEn,
      'PricePerUnit': double.parse(_price.text.trim()),
      'ServiceFee': double.parse(_fee.text.trim()),
      'UnitID': _unitId,
    };

    final part = widget.part;
    if (part == null) {
      body['PartAmount'] = amount;
    } else if (amount != part.stock) {
      // Stock also moves through receiving / sales / repairs. Only send
      // PartAmount when the user changed it, and check it against the
      // server first so a concurrent movement is not silently overwritten.
      final adjusted = await _confirmStockAdjustment(api, part, amount);
      if (!adjusted || !mounted) {
        return;
      }
      body['PartAmount'] = amount;
    } else {
      final ok = await AppDialogs.confirm(
        context,
        message: 'ท่านต้องการแก้ไขข้อมูลสินค้า ใช่หรือไม่?',
      );
      if (!ok || !mounted) {
        return;
      }
    }

    final ok = await runWithProgress(context, () async {
      if (part != null) {
        await api.update(part.id, body);
      } else {
        await api.create(body);
      }
      return true;
    });
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// Re-reads the part and asks the user to confirm the manual stock change.
  Future<bool> _confirmStockAdjustment(
    PartsApi api,
    Part part,
    int amount,
  ) async {
    final current = await runWithProgress(context, () => api.findOne(part.id));
    if (current == null || !mounted) {
      return false;
    }
    final unit = current.unitName ?? '';
    final changed = current.stock != part.stock;
    return AppDialogs.confirm(
      context,
      title: 'ยืนยันการปรับจำนวนคงเหลือ',
      message: [
        if (changed)
          'จำนวนคงเหลือในระบบถูกเปลี่ยนเป็น ${current.stock} $unit '
              'ระหว่างที่แก้ไข (เดิม ${part.stock})',
        'ปรับจำนวนคงเหลือจาก ${current.stock} เป็น $amount $unit ใช่หรือไม่?',
        'ปกติจำนวนคงเหลือจะถูกปรับอัตโนมัติจากการรับเข้า/ขาย/ใช้ในงานซ่อม',
      ].join('\n\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<Lookups>();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'แก้ไขสินค้า' : 'เพิ่มสินค้า')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'รหัสสินค้า *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกรหัสสินค้า' : null,
            ),
            gap,
            TextFormField(
              controller: _nameTh,
              decoration: const InputDecoration(
                labelText: 'ชื่อสินค้า (ไทย) *',
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อสินค้า' : null,
            ),
            gap,
            TextFormField(
              controller: _nameEn,
              decoration: const InputDecoration(
                labelText: 'ชื่อสินค้า (อังกฤษ)',
              ),
              textInputAction: TextInputAction.next,
            ),
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'จำนวนคงเหลือ *',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => int.tryParse((v ?? '').trim()) == null
                        ? 'กรุณากรอกจำนวนเต็มตั้งแต่ 0 ขึ้นไป'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LookupDropdown(
                    label: 'หน่วย',
                    required: true,
                    load: lookups.units,
                    value: _unitId,
                    onChanged: (o) => setState(() => _unitId = o?.id),
                  ),
                ),
              ],
            ),
            gap,
            TextFormField(
              controller: _price,
              decoration: const InputDecoration(
                labelText: 'ราคาต่อหน่วย (บาท) *',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: _validateMoney,
            ),
            gap,
            TextFormField(
              controller: _fee,
              decoration: const InputDecoration(labelText: 'ค่าบริการ (บาท) *'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: _validateMoney,
            ),
            if (_isEdit) ...[
              gap,
              Text(
                'ราคาเดิม ${formatMoney(widget.part!.pricePerUnit)} บาท · '
                'ค่าบริการเดิม ${formatMoney(widget.part!.serviceFee)} บาท',
                style: const TextStyle(color: Colors.grey),
              ),
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
