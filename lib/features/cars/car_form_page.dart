import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/lookups.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../auth/auth_provider.dart';
import '../customers/customer_models.dart';
import '../customers/customers_api.dart';
import '../customers/widgets/address_form_fields.dart';
import '../customers/widgets/customer_form_fields.dart';
import '../customers/widgets/customer_picker.dart';
import '../customers/widgets/lookup_dropdown.dart';
import 'car_models.dart';
import 'cars_api.dart';

/// Opens the full-screen car form.
///
/// * [car] given: edit (and delete for managers).
/// * [owner] given: create a car for that customer (owner is fixed).
/// * neither: create, choosing an existing customer or entering a new one
///   (`POST /cars/with-customer`).
///
/// Returns true when something was saved or deleted.
Future<bool?> showCarForm(BuildContext context, {Car? car, Customer? owner}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CarFormPage(car: car, owner: owner),
    ),
  );
}

enum _OwnerMode { existing, create }

class CarFormPage extends StatefulWidget {
  const CarFormPage({super.key, this.car, this.owner});

  final Car? car;
  final Customer? owner;

  @override
  State<CarFormPage> createState() => _CarFormPageState();
}

class _CarFormPageState extends State<CarFormPage> {
  static const _gap = SizedBox(height: 12);

  final _formKey = GlobalKey<FormState>();
  late final _carTitle = TextEditingController(text: widget.car?.carTitle);
  late final _carNumber = TextEditingController(text: widget.car?.carNumber);
  late final _vin = TextEditingController(text: widget.car?.vin);
  late final _ec = TextEditingController(text: widget.car?.ec);
  late int? _brandId = widget.car?.brandId;
  late int? _modelId = widget.car?.modelId;
  late int? _provinceId = widget.car?.provinceId;

  late Customer? _owner = widget.owner ?? widget.car?.customer;
  _OwnerMode _ownerMode = _OwnerMode.existing;
  final CustomerFormData _newCustomer = CustomerFormData();
  final AddressFormData _newAddress = AddressFormData();
  bool _withAddress = false;

  bool get _isEdit => widget.car != null;

  /// Owner can only be switched to "new customer" when creating without a
  /// preset owner.
  bool get _canCreateCustomer => !_isEdit && widget.owner == null;

  @override
  void dispose() {
    _carTitle.dispose();
    _carNumber.dispose();
    _vin.dispose();
    _ec.dispose();
    _newCustomer.dispose();
    _newAddress.dispose();
    super.dispose();
  }

  Map<String, dynamic> _carJson({int? customerId}) {
    String? clean(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    return {
      'CustomerID': ?customerId,
      'BrandID': _brandId,
      'ModelID': _modelId,
      'CarTitle': clean(_carTitle),
      'CarNumber': clean(_carNumber),
      'ProvinceID': _provinceId,
      'VIN': clean(_vin)?.toUpperCase(),
      'EC': clean(_ec)?.toUpperCase(),
    };
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final client = context.read<ApiClient>();
    final cars = CarsApi(client);
    final ok = await runWithProgress<bool>(
      context,
      () async {
        if (_isEdit) {
          await cars.update(widget.car!.id, _carJson(customerId: _owner!.id));
        } else if (_ownerMode == _OwnerMode.create && _canCreateCustomer) {
          final customerId = await cars.createWithCustomer(
            _newCustomer.toJson(),
            _carJson(),
          );
          // with-customer does not create an address; add it separately.
          if (_withAddress && customerId != null) {
            await CustomersApi(client)
                .addAddress(customerId, _newAddress.toJson());
          }
        } else {
          await cars.create(_carJson(customerId: _owner!.id));
        }
        return true;
      },
      successMessage: 'บันทึกข้อมูลรถยนต์เรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final car = widget.car!;
    final extra = car.repairIds.isEmpty
        ? ''
        : '\n(รถคันนี้มีประวัติงานซ่อม ${car.repairIds.length} รายการ)';
    final confirmed = await AppDialogs.confirm(
      context,
      message: 'ท่านต้องการลบรถทะเบียน ${car.plate} ใช่หรือไม่?$extra',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final ok = await runWithProgress<bool>(
      context,
      () async {
        await CarsApi(context.read<ApiClient>()).remove(car.id);
        return true;
      },
      successMessage: 'ลบข้อมูลรถยนต์เรียบร้อยแล้ว',
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickOwner(FormFieldState<Customer> field) async {
    final c = await showCustomerPicker(context);
    if (c != null && mounted) {
      setState(() => _owner = c);
      field.didChange(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขข้อมูลรถยนต์' : 'เพิ่มรถยนต์'),
        actions: [
          if (_isEdit && canManage)
            IconButton(
              tooltip: 'ลบ',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(onPressed: _save, child: const Text('บันทึก')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header('เจ้าของรถ'),
                    ..._ownerSection(),
                    const SizedBox(height: 24),
                    const _Header('ข้อมูลรถยนต์'),
                    ..._carSection(),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('บันทึก'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _ownerSection() {
    if (widget.owner != null) {
      return [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'ลูกค้า',
            prefixIcon: Icon(Icons.person),
          ),
          child: Text(widget.owner!.fullName),
        ),
      ];
    }
    return [
      if (_canCreateCustomer) ...[
        SegmentedButton<_OwnerMode>(
          segments: const [
            ButtonSegment(
              value: _OwnerMode.existing,
              icon: Icon(Icons.person_search),
              label: Text('ลูกค้าเดิม'),
            ),
            ButtonSegment(
              value: _OwnerMode.create,
              icon: Icon(Icons.person_add),
              label: Text('ลูกค้าใหม่'),
            ),
          ],
          selected: {_ownerMode},
          onSelectionChanged: (s) => setState(() => _ownerMode = s.first),
        ),
        _gap,
      ],
      if (_ownerMode == _OwnerMode.existing || !_canCreateCustomer)
        FormField<Customer>(
          initialValue: _owner,
          validator: (v) => v == null ? 'กรุณาเลือกลูกค้า' : null,
          builder: (field) => InkWell(
            onTap: () => _pickOwner(field),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'ลูกค้า',
                prefixIcon: const Icon(Icons.person),
                suffixIcon: const Icon(Icons.arrow_drop_down),
                errorText: field.errorText,
              ),
              child: Text(
                _owner == null
                    ? 'แตะเพื่อเลือกลูกค้า'
                    : [_owner!.fullName, ?_owner!.tel].join(' · '),
                style: _owner == null
                    ? const TextStyle(color: Colors.grey)
                    : null,
              ),
            ),
          ),
        )
      else ...[
        CustomerFormFields(data: _newCustomer),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('ระบุที่อยู่ลูกค้า'),
          value: _withAddress,
          onChanged: (v) => setState(() => _withAddress = v ?? false),
        ),
        if (_withAddress) AddressFormFields(data: _newAddress),
      ],
    ];
  }

  List<Widget> _carSection() {
    final lookups = context.read<Lookups>();
    final brandId = _brandId;
    return [
      LookupDropdown(
        label: 'ยี่ห้อ',
        load: lookups.brands,
        sourceKey: 'brand',
        value: brandId,
        required: true,
        onChanged: (o) {
          if (o?.id == _brandId) {
            return;
          }
          setState(() {
            _brandId = o?.id;
            _modelId = null;
          });
        },
      ),
      _gap,
      LookupDropdown(
        label: 'รุ่น',
        load: brandId == null ? null : () => lookups.carModels(brandId),
        sourceKey: 'model-$brandId',
        value: _modelId,
        required: true,
        disabledHint: 'เลือกยี่ห้อก่อน',
        onChanged: (o) => setState(() => _modelId = o?.id),
      ),
      _gap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _carTitle,
              decoration: const InputDecoration(
                labelText: 'หมวดทะเบียน',
                hintText: 'เช่น 1กข',
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกหมวด' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _carNumber,
              decoration: const InputDecoration(
                labelText: 'เลขทะเบียน',
                hintText: 'เช่น 1234',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'กรุณากรอกเลขทะเบียน' : null,
            ),
          ),
        ],
      ),
      _gap,
      LookupDropdown(
        label: 'จังหวัดทะเบียน',
        load: lookups.provinces,
        sourceKey: 'province',
        value: _provinceId,
        required: true,
        onChanged: (o) => setState(() => _provinceId = o?.id),
      ),
      _gap,
      TextFormField(
        controller: _vin,
        decoration: const InputDecoration(labelText: 'เลขตัวถัง (VIN)'),
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
      ),
      _gap,
      TextFormField(
        controller: _ec,
        decoration: const InputDecoration(labelText: 'เลขเครื่องยนต์'),
        textCapitalization: TextCapitalization.characters,
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
