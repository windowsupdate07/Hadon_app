import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../quotation_models.dart';
import '../quotations_api.dart';
import 'car_picker.dart';

/// Full-screen form for a new quotation (web DialogCreateQuotation): pick the
/// customer's car, then enter mileage (required), tax-plate expiry (or
/// "ไม่ระบุ"), gas installation, tyre type and a comment.
Future<NewQuotation?> openCreateQuotationForm(
  BuildContext context, {
  required QuotationsApi api,
  String title = 'สร้างใบเสนอราคา',
  String? defaultComment,
  CarOption? initialCar,
  String? submitLabel,
}) {
  return Navigator.of(context).push<NewQuotation>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CreateQuotationPage(
        api: api,
        title: title,
        defaultComment: defaultComment,
        initialCar: initialCar,
        submitLabel: submitLabel,
      ),
    ),
  );
}

class _CreateQuotationPage extends StatefulWidget {
  const _CreateQuotationPage({
    required this.api,
    required this.title,
    this.defaultComment,
    this.initialCar,
    this.submitLabel,
  });

  final QuotationsApi api;
  final String title;
  final String? defaultComment;
  final CarOption? initialCar;
  final String? submitLabel;

  @override
  State<_CreateQuotationPage> createState() => _CreateQuotationPageState();
}

class _CreateQuotationPageState extends State<_CreateQuotationPage> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleKey = GlobalKey<_VehicleFieldsState>();
  late final _comment = TextEditingController(text: widget.defaultComment ?? '');
  late CarOption? _car = widget.initialCar;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickCar() async {
    final car = await showCarPicker(context, api: widget.api);
    if (car != null && mounted) {
      setState(() => _car = car);
    }
  }

  Future<void> _submit() async {
    final car = _car;
    if (car == null) {
      await AppDialogs.warn(context, 'กรุณาเลือกรถยนต์');
      return;
    }
    if (car.customerId == null || car.brandId == null || car.modelId == null) {
      await AppDialogs.warn(context, 'ข้อมูลรถยนต์ไม่ครบถ้วน (ลูกค้า/ยี่ห้อ/รุ่น)');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final v = _vehicleKey.currentState!.read();
    if (v == null) {
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      message: 'ท่านต้องการ${widget.submitLabel ?? widget.title} ใช่หรือไม่?',
    );
    if (!ok || !mounted) {
      return;
    }
    Navigator.of(context).pop(
      NewQuotation(
        car: car,
        mileage: v.mileage,
        taxDate: v.taxDate,
        gasInstallation: v.gasInstallation,
        tireType: v.tireType,
        comment: _comment.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final car = _car;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SectionCard(
              title: 'รถยนต์ / ลูกค้า',
              trailing: car == null
                  ? null
                  : TextButton(onPressed: _pickCar, child: const Text('เปลี่ยนคัน')),
              child: car == null
                  ? OutlinedButton.icon(
                      onPressed: _pickCar,
                      icon: const Icon(Icons.directions_car_outlined),
                      label: const Text('เลือกรถยนต์ (ทะเบียน / ชื่อลูกค้า / เบอร์โทร)'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoRow('ทะเบียน', car.plate, bold: true),
                        InfoRow('ยี่ห้อ / รุ่น', car.brandModel),
                        InfoRow('สี', car.color),
                        InfoRow('เจ้าของ', car.owner),
                        InfoRow('เบอร์โทร', car.ownerTel),
                      ],
                    ),
            ),
            SectionCard(
              title: 'ข้อมูลรถยนต์',
              child: VehicleFields(key: _vehicleKey),
            ),
            SectionCard(
              title: 'หมายเหตุ',
              child: TextFormField(
                controller: _comment,
                maxLines: 3,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save),
            label: Text(widget.submitLabel ?? widget.title),
          ),
        ),
      ),
    );
  }
}

/// Mileage / tax date / gas / tyre inputs shared by the create page and the
/// edit dialog. Must be placed inside a [Form]; call [_VehicleFieldsState.read] after
/// validating.
class VehicleFields extends StatefulWidget {
  const VehicleFields({super.key, this.initial});

  final VehicleDetails? initial;

  @override
  State<VehicleFields> createState() => _VehicleFieldsState();
}

class _VehicleFieldsState extends State<VehicleFields> {
  late final _mileage = TextEditingController(
    text: widget.initial?.mileage == null ? '' : '${widget.initial!.mileage}',
  );
  late DateTime? _taxDate = widget.initial?.taxDate;

  /// "ไม่ระบุป้ายภาษี" — for an edit, preset when the stored date is null.
  late bool _noTaxPlate = widget.initial != null && widget.initial!.taxDate == null;
  late int _gas = widget.initial?.gasInstallation ?? 0;
  late int _tire = widget.initial?.tireType ?? 0;
  bool _taxError = false;

  @override
  void dispose() {
    _mileage.dispose();
    super.dispose();
  }

  /// Null when the tax date is missing (shows an error).
  VehicleDetails? read() {
    if (!_noTaxPlate && _taxDate == null) {
      setState(() => _taxError = true);
      return null;
    }
    return VehicleDetails(
      mileage: int.parse(_mileage.text),
      taxDate: _noTaxPlate ? null : _taxDate,
      gasInstallation: _gas,
      tireType: _tire,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _taxDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20, 12, 31),
      helpText: 'วันหมดอายุป้ายภาษี',
    );
    if (picked != null && mounted) {
      setState(() {
        _taxDate = picked;
        _taxError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _mileage,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'เลขไมล์ (กม.) *'),
          validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) <= 0
              ? 'กรุณากรอกเลขไมล์ (กม.)'
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'วันหมดอายุป้ายภาษี *',
                  errorText: _taxError
                      ? 'กรุณาระบุวันหมดอายุป้ายภาษี หรือเลือก "ไม่ระบุป้ายภาษี"'
                      : null,
                  errorMaxLines: 2,
                  enabled: !_noTaxPlate,
                ),
                child: InkWell(
                  onTap: _noTaxPlate ? null : _pickDate,
                  child: Text(
                    _noTaxPlate
                        ? 'ไม่ระบุป้ายภาษี'
                        : (_taxDate == null ? 'แตะเพื่อเลือกวันที่' : formatThaiDate(_taxDate)),
                    style: _noTaxPlate || _taxDate == null
                        ? TextStyle(color: theme.hintColor)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('ไม่ระบุป้ายภาษี'),
          value: _noTaxPlate,
          onChanged: (v) => setState(() {
            _noTaxPlate = v ?? false;
            _taxError = false;
          }),
        ),
        const SizedBox(height: 4),
        Text('การติดตั้งแก๊ส', style: theme.textTheme.labelLarge),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('ไม่ติดแก๊ส')),
            ButtonSegment(value: 1, label: Text('ติดแก๊ส')),
          ],
          selected: {_gas},
          onSelectionChanged: (s) => setState(() => _gas = s.first),
        ),
        const SizedBox(height: 12),
        Text('ประเภทลมยาง', style: theme.textTheme.labelLarge),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('ลมยางธรรมดา')),
            ButtonSegment(value: 1, label: Text('ลมยางไนโตรเจน')),
          ],
          selected: {_tire},
          onSelectionChanged: (s) => setState(() => _tire = s.first),
        ),
      ],
    );
  }
}

/// Dialog editing the vehicle info of a quotation. Returns the new values.
Future<VehicleDetails?> showEditVehicleDialog(
  BuildContext context,
  Quotation q,
) {
  return showDialog<VehicleDetails>(
    context: context,
    builder: (_) => _EditVehicleDialog(quotation: q),
  );
}

class _EditVehicleDialog extends StatefulWidget {
  const _EditVehicleDialog({required this.quotation});

  final Quotation quotation;

  @override
  State<_EditVehicleDialog> createState() => _EditVehicleDialogState();
}

class _EditVehicleDialogState extends State<_EditVehicleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fieldsKey = GlobalKey<_VehicleFieldsState>();

  @override
  Widget build(BuildContext context) {
    final q = widget.quotation;
    return AlertDialog(
      title: const Text('แก้ไขข้อมูลรถยนต์'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: VehicleFields(
            key: _fieldsKey,
            initial: VehicleDetails(
              mileage: q.mileage ?? 0,
              taxDate: q.taxDate,
              gasInstallation: q.gasInstallation,
              tireType: q.tireType,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            final v = _fieldsKey.currentState!.read();
            if (v != null) {
              Navigator.of(context).pop(v);
            }
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}

/// Dialog to edit the quotation comment. Returns the new text.
Future<String?> showEditCommentDialog(BuildContext context, String? current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditCommentDialog(current: current),
  );
}

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({this.current});

  final String? current;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _controller = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขหมายเหตุ'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        maxLength: 255,
        decoration: const InputDecoration(labelText: 'หมายเหตุ'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
