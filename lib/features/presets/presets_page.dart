import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_dialogs.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';
import 'preset_detail_page.dart';
import 'preset_dialogs.dart';
import 'preset_models.dart';
import 'presets_api.dart';

enum _StatusFilter { all, active, inactive }

class PresetsPage extends StatefulWidget {
  const PresetsPage({super.key});

  @override
  State<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends State<PresetsPage> {
  late final PresetsApi _api;
  late Future<List<Preset>> _future;
  String _query = '';
  int _page = 0;
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _api = PresetsApi(context.read<ApiClient>());
    _future = _api.findAll();
  }

  Future<void> _refresh() async {
    final future = _api.findAll();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // Shown by AsyncBody.
    }
  }

  List<Preset> _apply(List<Preset> all) {
    return all.where((p) {
      if (_query.isNotEmpty && !p.matches(_query)) {
        return false;
      }
      switch (_filter) {
        case _StatusFilter.active:
          return p.isActive;
        case _StatusFilter.inactive:
          return !p.isActive;
        case _StatusFilter.all:
          return true;
      }
    }).toList();
  }

  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PresetDetailPage(presetId: id)),
    );
    // Parts / name / status may have changed inside the detail page.
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _create() async {
    final input = await showPresetFormDialog(context);
    if (input == null || !mounted) {
      return;
    }
    final result = await runWithProgress(
      context,
      () async => (await _api.create(input.name, input.status)) ?? 0,
      successMessage: 'บันทึกข้อมูลเรียบร้อยแล้ว',
    );
    if (result == null || !mounted) {
      return;
    }
    await _refresh();
    // Continue straight to adding parts to the new preset.
    if (result > 0 && mounted) {
      await _openDetail(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'พรีเซ็ตข้อมูล',
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'เพิ่มพรีเซ็ต',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SearchField(
            hint: 'ค้นหาชื่อพรีเซ็ต / อะไหล่',
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip('ทั้งหมด', _StatusFilter.all),
                _filterChip('ใช้งาน', _StatusFilter.active),
                _filterChip('ไม่ใช้งาน', _StatusFilter.inactive),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Preset>>(
              future: _future,
              onRefresh: _refresh,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'ยังไม่มีข้อมูลพรีเซ็ต',
              builder: (context, data) => _buildList(_apply(data)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _StatusFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() {
          _filter = value;
          _page = 0;
        }),
      ),
    );
  }

  Widget _buildList(List<Preset> list) {
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 80), EmptyView()],
      );
    }
    final pageCount = (list.length / PageBar.pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final items = list
        .skip(page * PageBar.pageSize)
        .take(PageBar.pageSize)
        .toList();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'ทั้งหมด ${list.length} รายการ',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        if (i == items.length + 1) {
          return PageBar(
            page: page,
            pageCount: pageCount,
            onChanged: (p) => setState(() => _page = p),
          );
        }
        final p = items[i - 1];
        final names = p.details.map((d) => d.partName).join(', ');
        return Opacity(
          opacity: p.isActive ? 1 : 0.6,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              onTap: () => _openDetail(p.id),
              leading: CircleAvatar(child: Text('${p.details.length}')),
              title: Text(p.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusChip(presetStatusInfo(p)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'อะไหล่ ${p.details.length} รายการ · '
                          '${formatMoney(p.totalPrice)} บาท',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (names.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        );
      },
    );
  }
}
