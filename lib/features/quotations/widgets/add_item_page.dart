import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../parts/part_picker.dart';
import '../quotation_models.dart';
import '../quotations_api.dart';
import 'part_line_dialog.dart';

/// Opens the "add item" screen. Returns true when an item was saved.
Future<bool> openAddQuotationItem(
  BuildContext context, {
  required QuotationsApi api,
  required Quotation quotation,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddQuotationItemPage(api: api, quotation: quotation),
    ),
  );
  return saved ?? false;
}

/// Adds a QuotationDetail (repair category + preset) with its parts through
/// `POST /quotation-detail/create-with-parts`. The server requires a preset.
class AddQuotationItemPage extends StatefulWidget {
  const AddQuotationItemPage({
    super.key,
    required this.api,
    required this.quotation,
  });

  final QuotationsApi api;
  final Quotation quotation;

  @override
  State<AddQuotationItemPage> createState() => _AddQuotationItemPageState();
}

class _AddQuotationItemPageState extends State<AddQuotationItemPage> {
  final _formKey = GlobalKey<FormState>();
  late Future<_InitData> _future;

  Option? _category;
  PresetOption? _preset;
  bool _showAllPresets = false;
  // Bumped to rebuild the preset dropdown when a selection is reverted.
  int _presetRev = 0;
  Future<List<PresetOption>>? _allPresets;
  final List<DraftPart> _parts = [];

  @override
  void initState() {
    super.initState();
    _future = _loadInit();
  }

  Future<_InitData> _loadInit() async {
    final lookups = context.read<Lookups>();
    final results = await Future.wait([
      lookups.repairCategories(),
      // Preset links are optional help; fall back to "all presets" on error.
      widget.api.presetRefs().catchError((_) => <PresetRef>[]),
    ]);
    return _InitData(
      categories: results[0] as List<Option>,
      refs: results[1] as List<PresetRef>,
    );
  }

  /// Presets linked to this quotation's car model and the chosen category.
  List<PresetOption> _linkedPresets(List<PresetRef> refs) {
    final seen = <int>{};
    final out = <PresetOption>[];
    for (final r in refs) {
      final p = r.preset;
      if (p == null ||
          !r.active ||
          r.modelId != widget.quotation.modelId ||
          r.repairCategoryId != _category?.id ||
          !seen.add(p.id)) {
        continue;
      }
      out.add(p);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<void> _selectPreset(PresetOption? preset) async {
    if (preset == _preset) {
      return;
    }
    if (_parts.isNotEmpty && preset != null) {
      final ok = await AppDialogs.confirm(
        context,
        title: 'ใช้อะไหล่จากพรีเซ็ต?',
        message: 'รายการอะไหล่ที่เลือกไว้จะถูกแทนที่ด้วยอะไหล่ของพรีเซ็ตนี้',
      );
      if (!ok || !mounted) {
        setState(() => _presetRev++);
        return;
      }
    }
    setState(() {
      _preset = preset;
      if (preset != null) {
        _parts
          ..clear()
          ..addAll(
            preset.parts.map(
              (pp) => DraftPart(
                part: pp.part,
                quantity: pp.quantity <= 0 ? 1 : pp.quantity,
                pricePerUnit: pp.part.pricePerUnit,
                serviceFee: pp.part.serviceFee,
              ),
            ),
          );
      }
    });
  }

  Future<void> _addPart() async {
    final picked = await showPartPicker(context, checkStock: false);
    if (picked == null || !mounted) {
      return;
    }
    final qty = picked.quantity.ceil();
    setState(() {
      final existing = _parts.where((p) => p.part.id == picked.part.id);
      if (existing.isNotEmpty) {
        existing.first.quantity += qty;
      } else {
        _parts.add(
          DraftPart(
            part: picked.part,
            quantity: qty <= 0 ? 1 : qty,
            pricePerUnit: picked.part.pricePerUnit,
            serviceFee: picked.part.serviceFee,
          ),
        );
      }
    });
  }

  Future<void> _editPart(DraftPart p) async {
    final v = await showPartLineDialog(
      context,
      title: p.part.displayName,
      initial: PartLineValues(
        quantity: p.quantity,
        pricePerUnit: p.pricePerUnit,
        serviceFee: p.serviceFee,
      ),
    );
    if (v == null) {
      return;
    }
    setState(() {
      p.quantity = v.quantity;
      p.pricePerUnit = v.pricePerUnit;
      p.serviceFee = v.serviceFee;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_parts.isEmpty) {
      final ok = await AppDialogs.confirm(
        context,
        message: 'รายการนี้ยังไม่มีอะไหล่ ต้องการบันทึกหรือไม่?',
      );
      if (!ok || !mounted) {
        return;
      }
    }
    final done = await runWithProgress(
      context,
      () async {
        await widget.api.createDetailWithParts(
          quotationId: widget.quotation.id,
          repairCategoryId: _category!.id,
          presetId: _preset!.id,
          parts: _parts,
        );
        return true;
      },
    );
    if (done == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _parts.fold<double>(0, (a, p) => a + p.total);
    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มรายการซ่อม'),
        actions: [
          TextButton(onPressed: _save, child: const Text('บันทึก')),
        ],
      ),
      body: FutureBuilder<_InitData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(
              error: snap.error!,
              onRetry: () => setState(() => _future = _loadInit()),
            );
          }
          final init = snap.data!;
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                SectionCard(
                  title: 'ประเภทงานซ่อม / พรีเซ็ต',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<Option>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'ประเภทงานซ่อม *'),
                        items: [
                          for (final c in init.categories)
                            DropdownMenuItem(value: c, child: Text(c.label)),
                        ],
                        validator: (v) =>
                            v == null ? 'กรุณาเลือกประเภทงานซ่อม' : null,
                        onChanged: (c) => setState(() {
                          _category = c;
                          _preset = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _presetField(init),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'อะไหล่ (${_parts.length})',
                  trailing: TextButton.icon(
                    onPressed: _addPart,
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มอะไหล่'),
                  ),
                  child: _parts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'ยังไม่มีอะไหล่ เลือกพรีเซ็ตหรือกด "เพิ่มอะไหล่"',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : Column(
                          children: [
                            for (final p in _parts)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(p.part.displayName),
                                subtitle: Text(
                                  '${p.quantity} ${p.part.unitName ?? ''} × '
                                  '${formatMoney(p.pricePerUnit)}'
                                  ' + ค่าบริการ ${formatMoney(p.serviceFee)}',
                                ),
                                onTap: () => _editPart(p),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatMoney(p.total)),
                                    IconButton(
                                      tooltip: 'ลบ',
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          setState(() => _parts.remove(p)),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(),
                            InfoRow('รวม', '${formatMoney(total)} บาท', bold: true),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text('บันทึกรายการ (${formatMoney(total)} บาท)'),
          ),
        ),
      ),
    );
  }

  Widget _presetField(_InitData init) {
    if (_category == null) {
      return DropdownButtonFormField<PresetOption>(
        items: const [],
        onChanged: null,
        decoration: const InputDecoration(
          labelText: 'พรีเซ็ต *',
          helperText: 'กรุณาเลือกประเภทงานซ่อมก่อน',
        ),
        validator: (_) => 'กรุณาเลือกพรีเซ็ต',
      );
    }
    final linked = _linkedPresets(init.refs);
    final useAll = _showAllPresets || linked.isEmpty;
    if (useAll) {
      _allPresets ??= widget.api.presets();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (useAll)
          FutureBuilder<List<PresetOption>>(
            future: _allPresets,
            builder: (context, snap) => _presetDropdown(
              snap.data ?? const [],
              loading: snap.connectionState != ConnectionState.done,
              error: snap.hasError,
              helper: linked.isEmpty
                  ? 'ไม่มีพรีเซ็ตที่ผูกกับรุ่นรถนี้ แสดงพรีเซ็ตทั้งหมด'
                  : null,
            ),
          )
        else
          _presetDropdown(linked),
        if (linked.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('แสดงพรีเซ็ตทั้งหมด'),
            value: _showAllPresets,
            onChanged: (v) => setState(() {
              _showAllPresets = v;
              if (!v && _preset != null && !linked.contains(_preset)) {
                _preset = null;
              }
            }),
          ),
      ],
    );
  }

  Widget _presetDropdown(
    List<PresetOption> presets, {
    bool loading = false,
    bool error = false,
    String? helper,
  }) {
    return DropdownButtonFormField<PresetOption>(
      key: ValueKey(
        'preset-${_category?.id}-$_showAllPresets-${presets.length}-$_presetRev',
      ),
      initialValue: presets.contains(_preset) ? _preset : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'พรีเซ็ต *',
        helperText: error
            ? 'โหลดพรีเซ็ตไม่สำเร็จ'
            : (loading ? 'กำลังโหลด...' : helper),
        helperMaxLines: 2,
      ),
      items: [
        for (final p in presets)
          DropdownMenuItem(
            value: p,
            child: Text('${p.name} (${p.parts.length} รายการ)'),
          ),
      ],
      validator: (v) => v == null ? 'กรุณาเลือกพรีเซ็ต' : null,
      onChanged: loading ? null : _selectPreset,
    );
  }
}

class _InitData {
  const _InitData({required this.categories, required this.refs});

  final List<Option> categories;
  final List<PresetRef> refs;
}
