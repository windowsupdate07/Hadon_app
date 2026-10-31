import 'package:flutter/material.dart';

import '../../../core/data/lookups.dart';

/// Dropdown backed by an async [Option] list (see [Lookups]).
///
/// For cascading dropdowns pass `load: null` while the parent is not chosen
/// and change [sourceKey] whenever the parent changes; the options reload and
/// a spinner is shown in the field while fetching.
class LookupDropdown extends StatefulWidget {
  const LookupDropdown({
    super.key,
    required this.label,
    required this.load,
    required this.sourceKey,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.disabledHint,
    this.enabled = true,
    this.helperText,
  });

  final String label;

  /// Loads the options; null disables the field (parent not selected).
  final Future<List<Option>> Function()? load;

  /// Identifies the current option set, e.g. `'district-$provinceId'`.
  final Object sourceKey;

  final int? value;
  final ValueChanged<Option?> onChanged;
  final bool required;

  /// Hint shown while [load] is null, e.g. "เลือกจังหวัดก่อน".
  final String? disabledHint;

  /// False makes the field read-only (value still shown).
  final bool enabled;

  /// Shown under the field, e.g. why it is locked.
  final String? helperText;

  @override
  State<LookupDropdown> createState() => _LookupDropdownState();
}

class _LookupDropdownState extends State<LookupDropdown> {
  List<Option> _options = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant LookupDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey) {
      _fetch();
    }
  }

  /// Retry button handler.
  void _retry() => setState(_fetch);

  /// Resets the options synchronously (callers are initState,
  /// didUpdateWidget or a setState callback, which all rebuild afterwards),
  /// then loads them.
  void _fetch() {
    _options = const [];
    _error = null;
    _loading = widget.load != null;
    if (widget.load != null) {
      _load(widget.load!, widget.sourceKey);
    }
  }

  Future<void> _load(
    Future<List<Option>> Function() load,
    Object key,
  ) async {
    try {
      final options = await load();
      // Ignore stale responses after the parent selection changed.
      if (!mounted || key != widget.sourceKey) {
        return;
      }
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || key != widget.sourceKey) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _options.any((o) => o.id == widget.value);
    final selected = hasValue ? widget.value : null;
    final enabled = widget.enabled &&
        widget.load != null &&
        !_loading &&
        _error == null;

    Widget? suffix;
    if (_loading) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_error != null) {
      suffix = IconButton(
        tooltip: 'โหลดใหม่',
        icon: const Icon(Icons.refresh, color: Colors.red),
        onPressed: _retry,
      );
    }

    final hint = _loading
        ? 'กำลังโหลด...'
        : (widget.load == null ? (widget.disabledHint ?? '-') : 'เลือก${widget.label}');

    return DropdownButtonFormField<int>(
      // Rebuild the field state when the option set or the selection changes,
      // so a reset from the parent is reflected.
      key: ValueKey('${widget.sourceKey}|$selected|${_options.length}'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: suffix,
        helperText: _error != null
            ? 'โหลดข้อมูลไม่สำเร็จ แตะเพื่อลองใหม่'
            : widget.helperText,
        helperMaxLines: 2,
      ),
      hint: Text(hint),
      disabledHint: Text(
        selected == null
            ? hint
            : _options.firstWhere((o) => o.id == selected).label,
      ),
      items: [
        for (final o in _options)
          DropdownMenuItem(
            value: o.id,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (id) {
              Option? option;
              for (final o in _options) {
                if (o.id == id) {
                  option = o;
                }
              }
              widget.onChanged(option);
            }
          : null,
      validator: widget.required
          ? (v) => v == null ? 'กรุณาเลือก${widget.label}' : null
          : null,
    );
  }
}
