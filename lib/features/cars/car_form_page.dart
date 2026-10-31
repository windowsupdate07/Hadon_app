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
import 'car_repair_history.dart';
import 'cars_api.dart';

/// Opens the full-screen car form.
///
/// * [car] given: edit (and delete for managers). Brand / model are locked
///   once the car has repair jobs, like the web.
/// * [owner] given: create a car for that customer (owner is fixed).
/// * neither: create, choosing an existing customer or entering a new one
///   (`POST /cars/with-customer`, optionally with the customer's address).
///
/// Before creating, `POST /cars/check-existence` is used to catch a plate
/// that is already registered (offering an ownership transfer) and, for a
/// new customer, a customer that already exists (name + surname or ID
/// number).
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

/// Choice when a "new" customer matches an existing one.
enum _CustomerChoice { useExisting, createNew }

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
  late final _color = TextEditingController(text: widget.car?.color);
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
    _color.dispose();
    _newCustomer.dispose();
    _newAddress.dispose();
    super.dispose();
  }

  /// Brand / model cannot change once repairs reference the car.
  bool get _brandModelLocked => _isEdit && widget.car!.brandModelLocked;

  static String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Map<String, dynamic> _carJson({int? customerId}) => {
    'CustomerID': ?customerId,
    'BrandID': _brandId,
    'ModelID': _modelId,
    'CarTitle': _clean(_carTitle),
    'CarNumber': _clean(_carNumber),
    'ProvinceID': _provinceId,
    'VIN': _clean(_vin)?.toUpperCase(),
    'EC': _clean(_ec)?.toUpperCase(),
    'Color': _clean(_color),
  };

  /// Plate identity for the existence check. Brand / model are left out on
  /// purpose so the same plate under another model is still reported.
  Map<String, dynamic> _plateJson() => {
    'CarTitle': _clean(_carTitle),
    'CarNumber': _clean(_carNumber),
    'ProvinceID': _provinceId,
  };

  bool get _creatingCustomer =>
      _canCreateCustomer && _ownerMode == _OwnerMode.create;

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isEdit) {
      if (_plateChanged && !await _plateIsFree()) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _submit(
        (cars) => cars.update(widget.car!.id, _carJson(customerId: _owner!.id)),
      );
      return;
    }

    final client = context.read<ApiClient>();
    final check = await runWithProgress<CarExistence>(
      context,
      () => CarsApi(client).checkExistence(
        car: _plateJson(),
        customer: _creatingCustomer ? _newCustomer.toJson() : null,
      ),
    );
    if (check == null || !mounted) {
      return;
    }

    final existingCar = check.existingCar;
    if (existingCar != null) {
      await _onExistingCar(existingCar, check.existingCustomer);
      return;
    }

    if (!_creatingCustomer) {
      await _submit((cars) => cars.create(_carJson(customerId: _owner!.id)));
      return;
    }

    final existingCustomer = check.existingCustomer;
    if (existingCustomer != null) {
      final choice = await _askExistingCustomer(existingCustomer);
      if (choice == null || !mounted) {
        return;
      }
      if (choice == _CustomerChoice.useExisting) {
        await _submit(
          (cars) => cars.create(_carJson(customerId: existingCustomer.id)),
        );
        return;
      }
    }

    await _submit(
      (cars) => cars.createWithCustomer(
        _newCustomer.toJson(),
        _carJson(),
        address: _withAddress ? _newAddress.toJson() : null,
      ),
    );
  }

  bool get _plateChanged {
    final car = widget.car!;
    return _clean(_carTitle) != car.carTitle ||
        _clean(_carNumber) != car.carNumber ||
        _provinceId != car.provinceId;
  }

  /// Edit mode: the new plate must not belong to another car.
  Future<bool> _plateIsFree() async {
    final check = await runWithProgress<CarExistence>(
      context,
      () =>
          CarsApi(context.read<ApiClient>()).checkExistence(car: _plateJson()),
    );
    if (check == null || !mounted) {
      return false;
    }
    final other = check.existingCar;
    if (other != null && other.id != widget.car!.id) {
      await AppDialogs.warn(
        context,
        'ทะเบียน ${other.plateWithProvince} ซ้ำกับรถในระบบ '
        '(${other.brandModel}) ของ "${other.customer?.fullName ?? 'ไม่ระบุเจ้าของ'}"',
      );
      return false;
    }
    return true;
  }

  /// Runs [action] behind a progress dialog and closes the form on success.
  Future<void> _submit(Future<void> Function(CarsApi cars) action) async {
    final cars = CarsApi(context.read<ApiClient>());
    final ok = await runWithProgress<bool>(context, () async {
      await action(cars);
      return true;
    }, successMessage: 'บันทึกข้อมูลรถยนต์เรียบร้อยแล้ว');
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// The plate is already registered. If it already belongs to the target
  /// owner there is nothing to do; otherwise offer to transfer the car.
  Future<void> _onExistingCar(Car existing, Customer? matchedCustomer) async {
    // Target owner: the picked / fixed customer, or the existing customer
    // that matches the "new customer" input.
    final Customer? target = _creatingCustomer ? matchedCustomer : _owner;
    final currentOwner = existing.customer?.fullName ?? 'ไม่ระบุเจ้าของ';
    final carText = '${existing.plateWithProvince} (${existing.brandModel})';

    if (target != null && existing.customerId == target.id) {
      await AppDialogs.warn(
        context,
        'รถทะเบียน $carText เป็นของลูกค้า "${target.fullName}" อยู่แล้ว',
      );
      return;
    }

    final targetName = target?.fullName ?? _newCustomerName();
    final transfer = await AppDialogs.confirm(
      context,
      title: 'ข้อมูลรถยนต์ซ้ำ',
      message:
          'รถทะเบียน $carText มีในระบบแล้ว '
          'โดยเป็นของ "$currentOwner"\n\n'
          'ต้องการเปลี่ยนเจ้าของรถคันนี้เป็น "$targetName" หรือไม่?',
    );
    if (!transfer || !mounted) {
      return;
    }

    final client = context.read<ApiClient>();
    await _submit((cars) async {
      var ownerId = target?.id;
      if (ownerId == null) {
        // New customer: create it first (with address when given).
        final customers = CustomersApi(client);
        ownerId = _withAddress
            ? await customers.create(
                _newCustomer.toJson(),
                _newAddress.toJson(),
              )
            : await customers.createSimple(_newCustomer.toJson());
        if (ownerId == null) {
          throw Exception('ไม่สามารถสร้างข้อมูลลูกค้าได้');
        }
      }
      await cars.update(existing.id, {
        'CustomerID': ownerId,
        // Fill in details the stored car is missing.
        if (existing.color == null && _clean(_color) != null)
          'Color': _clean(_color),
        if (existing.vin == null && _clean(_vin) != null)
          'VIN': _clean(_vin)!.toUpperCase(),
        if (existing.ec == null && _clean(_ec) != null)
          'EC': _clean(_ec)!.toUpperCase(),
      });
    });
  }

  String _newCustomerName() {
    final n =
        '${_newCustomer.name.text.trim()} '
                '${_newCustomer.surname.text.trim()}'
            .trim();
    return n.isEmpty ? 'ลูกค้าใหม่' : n;
  }

  /// A customer with the same name + surname or ID number exists. Same ID
  /// number means the same person, so creating a duplicate is not offered.
  Future<_CustomerChoice?> _askExistingCustomer(Customer existing) {
    final sameId =
        existing.idNumber != null &&
        existing.idNumber == _newCustomer.idNumberValue;
    final detail = [
      existing.fullName,
      if (existing.tel != null) 'โทร ${existing.tel}',
      if (existing.idNumber != null) 'เลขประจำตัว ${existing.idNumber}',
    ].join('\n');
    return showDialog<_CustomerChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_search, color: Colors.blue, size: 40),
        title: Text(
          sameId ? 'พบข้อมูลลูกค้า (เลขประจำตัวซ้ำ)' : 'พบข้อมูลลูกค้า',
        ),
        content: Text(
          'มีข้อมูลลูกค้านี้ในระบบแล้ว\n\n$detail\n\n'
          'ต้องการเพิ่มรถยนต์คันนี้ให้กับลูกค้าท่านนี้หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ยกเลิก'),
          ),
          if (!sameId)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_CustomerChoice.createNew),
              child: const Text('สร้างลูกค้าใหม่'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_CustomerChoice.useExisting),
            child: const Text('ใช้ลูกค้าเดิม'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final car = widget.car!;
    if (car.hasRepairs) {
      await AppDialogs.warn(
        context,
        'ไม่สามารถลบรถทะเบียน ${car.plate} ได้ '
        'เนื่องจากมีประวัติงานซ่อม ${car.repairIds.length} รายการ',
      );
      return;
    }
    final confirmed = await AppDialogs.confirm(
      context,
      message: 'ท่านต้องการลบรถทะเบียน ${car.plate} ใช่หรือไม่?',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final ok = await runWithProgress<bool>(context, () async {
      await CarsApi(context.read<ApiClient>()).remove(car.id);
      return true;
    }, successMessage: 'ลบข้อมูลรถยนต์เรียบร้อยแล้ว');
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
          if (_isEdit)
            IconButton(
              tooltip: 'ประวัติการซ่อม',
              icon: const Icon(Icons.history),
              onPressed: () => showCarRepairHistory(context, widget.car!),
            ),
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
        enabled: !_brandModelLocked,
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
        enabled: !_brandModelLocked,
        helperText: _brandModelLocked
            ? 'แก้ไขยี่ห้อ/รุ่นไม่ได้ เนื่องจากรถคันนี้มีประวัติการซ่อมแล้ว'
            : null,
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
        controller: _color,
        decoration: const InputDecoration(
          labelText: 'สีรถยนต์',
          hintText: 'เช่น ขาว, ดำ, เทา',
        ),
        textInputAction: TextInputAction.next,
        validator: (v) => (v ?? '').trim().isEmpty ? 'กรุณากรอกสีรถยนต์' : null,
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
