import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/auth_provider.dart';
import '../../parts/part_model.dart';
import '../../parts/part_picker.dart';
import '../repair_models.dart';
import '../repairs_api.dart';

/// Full-screen form to add a repair item (RepairDetail) with parts,
/// prefilled from a preset. Returns true when an item was created.
///
/// A preset and at least one part are required, like the web (its repair
/// detail page renders `item.preset.Preset` and would break on a null
/// preset).
Future<bool> showAddRepairItemSheet(
  BuildContext context, {
  required RepairsApi api,
  required Repair repair,
}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AddRepairItemPage(api: api, repair: repair),
    ),
  );
  return created ?? false;
}

class _Line {
  _Line(this.part, this.qty);

  final Part part;
  int qty;
}

class _AddRepairItemPage extends StatefulWidget {
  const _AddRepairItemPage({required this.api, required this.repair});

  final RepairsApi api;
  final Repair repair;

  @override
  State<_AddRepairItemPage> createState() => _AddRepairItemPageState();
}

class _AddRepairItemPageState extends State<_AddRepairItemPage> {
  final _formKey = GlobalKey<FormState>();
  late Future<(List<Option>, List<Preset>)> _future;

  int? _categoryId;
  int? _presetId;
  bool _showAllPresets = false;
  final List<_Line> _lines = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Option>, List<Preset>)> _load() async {
    final lookups = context.read<Lookups>();
    final results = await Future.wait([
      lookups.repairCategories(),
      widget.api.presets(),
    ]);
    final presets = (results[1] as List<Preset>)
        .where((p) => p.isActive)
        .toList();
    return (results[0] as List<Option>, presets);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  List<Preset> _presetsFor(List<Preset> all) {
    final cat = _categoryId;
    if (cat == null) {
      return const [];
    }
    if (_showAllPresets) {
      return all;
    }
    final r = widget.repair;
    final forCar = all
        .where((p) => p.appliesToCar(cat, r.brandId, r.modelId))
        .toList();
    if (forCar.isNotEmpty) {
      return forCar;
    }
    return all.where((p) => p.appliesToCategory(cat)).toList();
  }

  void _selectPreset(Preset? preset) {
    setState(() {
      _presetId = preset?.id;
      _lines
        ..clear()
        ..addAll([
          for (final pp in preset?.parts ?? const <PresetPart>[])
            _Line(pp.part, pp.numOfUse <= 0 ? 1 : pp.numOfUse),
        ]);
    });
  }

  Future<void> _addPart() async {
    final picked = await showPartPicker(context);
    if (picked == null || !mounted) {
      return;
    }
    final qty = picked.quantity.round();
    if (qty <= 0) {
      return;
    }
    setState(() {
      final existing = _lines
          .where((l) => l.part.id == picked.part.id)
          .firstOrNull;
      if (existing != null) {
        existing.qty += qty;
      } else {
        _lines.add(_Line(picked.part, qty));
      }
    });
  }

  Future<void> _editQty(_Line line) async {
    final controller = TextEditingController(text: '${line.qty}');
    final key = GlobalKey<FormState>();
    final qty = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.part.displayName),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'จำนวน',
              helperText:
                  'คงเหลือ ${formatNumber(line.part.amount)} ${line.part.unitName ?? ''}',
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n <= 0) {
                return 'กรุณากรอกจำนวนเต็มที่มากกว่า 0';
              }
              if (n > line.part.amount) {
                return 'สินค้าคงเหลือไม่เพียงพอ';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.of(context).pop(int.parse(controller.text));
              }
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (qty != null && mounted) {
      setState(() => line.qty = qty);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final short = _lines.where((l) => l.qty > l.part.amount).toList();
    if (short.isNotEmpty) {
      await AppDialogs.warn(
        context,
        'สินค้าคงเหลือไม่เพียงพอ: '
        '${short.map((l) => l.part.displayName).join(', ')}',
      );
      return;
    }
    if (_lines.isEmpty) {
      await AppDialogs.warn(context, 'กรุณาเลือกอะไหล่อย่างน้อย 1 รายการ');
      return;
    }
    if (!mounted) {
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      message:
          'ท่านต้องการเพิ่มรายการอุปกรณ์ ${_lines.length} รายการ ใช่หรือไม่?\n'
          '(จำนวนอะไหล่จะถูกตัดออกจากสต๊อก)',
    );
    if (!ok || !mounted) {
      return;
    }
    final employeeId = context.read<AuthProvider>().employee?.id;
    final result = await runWithProgress(context, () async {
      await widget.api.createItem(
        repairId: widget.repair.id,
        repairCategoryId: _categoryId!,
        presetId: _presetId!,
        employeeId: employeeId,
        parts: [
          for (final l in _lines) NewRepairPart(part: l.part, numOfUse: l.qty),
        ],
      );
      return true;
    }, successMessage: 'เพิ่มรายการซ่อมเรียบร้อยแล้ว');
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มรายการซ่อม'),
        actions: [TextButton(onPressed: _save, child: const Text('บันทึก'))],
      ),
      body: FutureBuilder<(List<Option>, List<Preset>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: _retry);
          }
          final (categories, allPresets) = snap.data!;
          return _buildForm(categories, allPresets);
        },
      ),
    );
  }

  Widget _buildForm(List<Option> categories, List<Preset> allPresets) {
    final presets = _presetsFor(allPresets);
    // Keep the dropdown value valid when the filter changes.
    final presetValue = presets.any((p) => p.id == _presetId)
        ? _presetId
        : null;
    final total = _lines.fold<double>(
      0,
      (s, l) => s + l.qty * l.part.pricePerUnit + l.part.serviceFee,
    );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'หมวดหมู่การซ่อม *',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            validator: (v) => v == null ? 'กรุณาเลือกหมวดหมู่การซ่อม' : null,
            onChanged: (v) {
              setState(() => _categoryId = v);
              _selectPreset(null);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            key: ValueKey('preset-$_categoryId-$_showAllPresets'),
            initialValue: presetValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'พรีเซ็ต *',
              border: const OutlineInputBorder(),
              helperText: _categoryId == null
                  ? 'เลือกหมวดหมู่ก่อน'
                  : presets.isEmpty
                  ? 'ไม่มีพรีเซ็ตสำหรับหมวดหมู่นี้'
                  : null,
            ),
            validator: (v) => v == null ? 'กรุณาเลือกพรีเซ็ต' : null,
            items: [
              for (final p in presets)
                DropdownMenuItem<int?>(
                  value: p.id,
                  child: Text(
                    '${p.name} (${p.parts.length} รายการ)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _categoryId == null
                ? null
                : (v) => _selectPreset(
                    allPresets.where((p) => p.id == v).firstOrNull,
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('แสดงพรีเซ็ตทั้งหมด'),
            value: _showAllPresets,
            onChanged: (v) => setState(() => _showAllPresets = v),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  'อะไหล่ (${_lines.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _addPart,
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มอะไหล่'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'ยังไม่มีอะไหล่',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          for (final l in _lines) _lineTile(l),
          if (_lines.isNotEmpty) ...[
            const Divider(),
            InfoRow('รวมโดยประมาณ', '${formatMoney(total)} บาท', bold: true),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('บันทึกรายการซ่อม'),
          ),
        ],
      ),
    );
  }

  Widget _lineTile(_Line l) {
    final short = l.qty > l.part.amount;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text(l.part.displayName),
        subtitle: Text(
          '${formatNumber(l.qty)} ${l.part.unitName ?? ''} × '
          '${formatMoney(l.part.pricePerUnit)}'
          '${l.part.serviceFee > 0 ? ' + ค่าบริการ ${formatMoney(l.part.serviceFee)}' : ''}'
          '\nคงเหลือ ${formatNumber(l.part.amount)}',
          style: short ? const TextStyle(color: Colors.red) : null,
        ),
        isThreeLine: true,
        onTap: () => _editQty(l),
        trailing: IconButton(
          tooltip: 'นำออก',
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: () => setState(() => _lines.remove(l)),
        ),
      ),
    );
  }
}
