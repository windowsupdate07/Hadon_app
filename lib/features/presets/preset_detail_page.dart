import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/statuses.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../parts/part_picker.dart';
import 'preset_dialogs.dart';
import 'preset_models.dart';
import 'presets_api.dart';

StatusInfo presetStatusInfo(Preset p) => p.isActive
    ? const StatusInfo('ใช้งาน', Colors.green)
    : const StatusInfo('ไม่ใช้งาน', Colors.grey);

/// Preset header + its parts. Pops `true` when the preset was deleted.
class PresetDetailPage extends StatefulWidget {
  const PresetDetailPage({super.key, required this.presetId});

  final int presetId;

  @override
  State<PresetDetailPage> createState() => _PresetDetailPageState();
}

class _PresetDetailPageState extends State<PresetDetailPage> {
  late final PresetsApi _api;
  late Future<Preset> _future;
  Preset? _preset;

  @override
  void initState() {
    super.initState();
    _api = PresetsApi(context.read<ApiClient>());
    _future = _load();
  }

  Future<Preset> _load() async {
    final p = await _api.findOne(widget.presetId);
    if (mounted) {
      // App bar actions and FAB depend on the loaded preset.
      setState(() => _preset = p);
    }
    return p;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  /// Runs a mutation behind a progress dialog, then reloads.
  Future<void> _mutate(Future<void> Function() action, String message) async {
    final ok = await runWithProgress(context, () async {
      await action();
      return true;
    }, successMessage: message);
    if (ok == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _edit(Preset preset) async {
    final input = await showPresetFormDialog(context, preset: preset);
    if (input == null || !mounted) {
      return;
    }
    await _mutate(
      () => _api.update(preset.id, input.name, input.status),
      'บันทึกข้อมูลเรียบร้อยแล้ว',
    );
  }

  Future<void> _delete(Preset preset) async {
    final refs = preset.refCount > 0
        ? '\nพรีเซ็ตนี้ถูกอ้างอิงอยู่ ${preset.refCount} รายการ ซึ่งจะถูกลบไปด้วย'
        : '';
    final ok = await AppDialogs.confirm(
      context,
      message: 'ท่านต้องการลบพรีเซ็ต "${preset.name}" ใช่หรือไม่?$refs',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.remove(preset);
      return true;
    }, successMessage: 'ลบข้อมูลเรียบร้อยแล้ว');
    if (done == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _addPart(Preset preset) async {
    final picked = await showPartPicker(context, checkStock: false);
    if (picked == null || !mounted) {
      return;
    }
    final qty = picked.quantity;
    if (qty != qty.roundToDouble() || qty <= 0) {
      await AppDialogs.warn(context, 'จำนวนที่ใช้ต้องเป็นจำนวนเต็ม');
      return;
    }
    final n = qty.round();
    PresetDetail? existing;
    for (final d in preset.details) {
      if (d.partId == picked.part.id) {
        existing = d;
        break;
      }
    }
    if (existing != null) {
      final merge = await AppDialogs.confirm(
        context,
        title: 'มีอะไหล่นี้อยู่แล้ว',
        message:
            '"${picked.part.displayName}" อยู่ในพรีเซ็ตแล้ว '
            '(${existing.numOfUse}) ต้องการเพิ่มจำนวนเป็น '
            '${existing.numOfUse + n} ใช่หรือไม่?',
      );
      if (!merge || !mounted) {
        return;
      }
      final detail = existing;
      await _mutate(
        () => _api.updateDetail(detail.id, detail.numOfUse + n),
        'บันทึกข้อมูลเรียบร้อยแล้ว',
      );
      return;
    }
    await _mutate(
      () => _api.addDetail(preset.id, picked.part.id, n),
      'เพิ่มอะไหล่เรียบร้อยแล้ว',
    );
  }

  Future<void> _editQty(PresetDetail d) async {
    final n = await showQuantityDialog(
      context,
      title: d.partName,
      initial: d.numOfUse,
    );
    if (n == null || n == d.numOfUse || !mounted) {
      return;
    }
    await _mutate(
      () => _api.updateDetail(d.id, n),
      'บันทึกข้อมูลเรียบร้อยแล้ว',
    );
  }

  Future<void> _removePart(PresetDetail d) async {
    final ok = await AppDialogs.confirmDelete(
      context,
      '"${d.partName}" ออกจากพรีเซ็ต',
    );
    if (!ok || !mounted) {
      return;
    }
    await _mutate(() => _api.removeDetail(d.id), 'ลบข้อมูลเรียบร้อยแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        context.watch<AuthProvider>().employee?.canManage ?? false;
    final preset = _preset;
    return Scaffold(
      appBar: AppBar(
        title: Text(preset?.name ?? 'พรีเซ็ต'),
        actions: [
          if (preset != null) ...[
            IconButton(
              tooltip: 'แก้ไข',
              icon: const Icon(Icons.edit),
              onPressed: () => _edit(preset),
            ),
            if (canManage)
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(preset),
              ),
          ],
        ],
      ),
      floatingActionButton: preset == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addPart(preset),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มอะไหล่'),
            ),
      body: AsyncBody<Preset>(
        future: _future,
        onRefresh: _refresh,
        builder: (context, p) => _buildBody(p),
      ),
    );
  }

  Widget _buildBody(Preset p) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 88),
      children: [
        SectionCard(
          title: p.name,
          trailing: StatusChip(presetStatusInfo(p)),
          child: Column(
            children: [
              InfoRow('จำนวนอะไหล่', '${p.details.length} รายการ'),
              InfoRow('ราคารวมโดยประมาณ', '${formatMoney(p.totalPrice)} บาท'),
              InfoRow('ใช้ในการอ้างอิง', '${p.refCount} รายการ'),
            ],
          ),
        ),
        SectionCard(
          title: 'รายการอะไหล่',
          child: p.details.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: EmptyView(message: 'ยังไม่มีอะไหล่ในพรีเซ็ตนี้'),
                )
              : Column(children: [for (final d in p.details) _detailTile(d)]),
        ),
      ],
    );
  }

  Widget _detailTile(PresetDetail d) {
    final part = d.part;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _editQty(d),
      title: Text(
        d.partName,
        style: part == null ? const TextStyle(color: Colors.red) : null,
      ),
      subtitle: part == null
          ? null
          : Text(
              '${part.partNumber ?? '-'} · '
              '${formatMoney(part.pricePerUnit)} บาท/หน่วย',
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '× ${d.numOfUse}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'qty') {
                _editQty(d);
              } else if (v == 'remove') {
                _removePart(d);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'qty', child: Text('แก้ไขจำนวน')),
              PopupMenuItem(
                value: 'remove',
                child: Text('ลบออก', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
