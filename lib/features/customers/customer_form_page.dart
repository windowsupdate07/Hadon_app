import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import 'customer_models.dart';
import 'customers_api.dart';
import 'widgets/address_form_fields.dart';
import 'widgets/customer_form_fields.dart';

/// Opens the full-screen customer form.
///
/// Create mode (no [customer]): also asks for the first address and returns
/// the new CustomerID (or 0 if the server did not echo it). If the ID number
/// already exists the user may jump to that customer instead; their id is
/// returned.
/// Edit mode: returns the customer's id after a successful update.
/// Returns null when cancelled.
Future<int?> showCustomerForm(BuildContext context, {Customer? customer}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CustomerFormPage(customer: customer),
    ),
  );
}

class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({super.key, this.customer});

  final Customer? customer;

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final CustomerFormData _customer = widget.customer == null
      ? CustomerFormData()
      : CustomerFormData.fromCustomer(widget.customer!);
  final AddressFormData _address = AddressFormData();

  bool get _isEdit => widget.customer != null;

  @override
  void dispose() {
    _customer.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final api = CustomersApi(context.read<ApiClient>());

    // Duplicate ID number check (only when it is new or changed).
    final idNumber = _customer.idNumberValue;
    if (idNumber != null && idNumber != widget.customer?.idNumber) {
      final found = await runWithProgress<Customer?>(
        context,
        () => api.findByIdNumber(idNumber),
      );
      if (!mounted) {
        return;
      }
      // runWithProgress returns null both for "not found" and for errors;
      // errors were already shown, so only a hit stops here.
      if (found != null && found.id != widget.customer?.id) {
        await _onDuplicateIdNumber(found);
        return;
      }
    }

    if (!mounted) {
      return;
    }
    final id = await runWithProgress<int>(
      context,
      () async {
        if (_isEdit) {
          final id = widget.customer!.id;
          await api.update(id, _customer.toJson());
          return id;
        }
        return await api.create(_customer.toJson(), _address.toJson()) ?? 0;
      },
      successMessage: 'บันทึกข้อมูลลูกค้าเรียบร้อยแล้ว',
    );
    if (id != null && mounted) {
      Navigator.of(context).pop(id);
    }
  }

  /// The ID number already belongs to [other]. In create mode offer to open
  /// that customer instead (the page pops with their id).
  Future<void> _onDuplicateIdNumber(Customer other) async {
    final message = 'เลขประจำตัว ${other.idNumber ?? ''} '
        'เป็นของลูกค้า "${other.fullName}" (รหัส #${other.id}) อยู่แล้ว';
    if (_isEdit) {
      await AppDialogs.warn(context, message);
      return;
    }
    final open = await AppDialogs.confirm(
      context,
      title: 'พบข้อมูลลูกค้าในระบบแล้ว',
      message: '$message\nต้องการเปิดข้อมูลลูกค้ารายนี้แทนหรือไม่?',
    );
    if (open && mounted) {
      Navigator.of(context).pop(other.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขข้อมูลลูกค้า' : 'เพิ่มลูกค้า'),
        actions: [
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
                    const _Header('ข้อมูลลูกค้า'),
                    CustomerFormFields(data: _customer),
                    if (!_isEdit) ...[
                      const SizedBox(height: 24),
                      const _Header('ที่อยู่'),
                      AddressFormFields(data: _address),
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
            ),
          ],
        ),
      ),
    );
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
