import 'package:flutter/material.dart';

import '../../core/data/lookups.dart';

/// Dropdown backed by a [Lookups] loader (units, positions, provinces ...).
///
/// The list is loaded once in [State.initState]. For cascading fields
/// (province -> district) give the child a key that depends on the parent id
/// so it is recreated (and reloaded) when the parent changes. Pass a null
/// [load] to render a disabled field (e.g. parent not chosen yet).
class LookupDropdown extends StatefulWidget {
  const LookupDropdown({
    super.key,
    required this.label,
    required this.load,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.hint,
  });

  final String label;
  final Future<List<Option>> Function()? load;
  final int? value;
  final ValueChanged<Option?> onChanged;
  final bool required;
  final String? hint;

  @override
  State<LookupDropdown> createState() => _LookupDropdownState();
}

class _LookupDropdownState extends State<LookupDropdown> {
  Future<List<Option>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load?.call();
  }

  void _retry() {
    setState(() {
      _future = widget.load?.call();
    });
  }

  String get _label => widget.required ? '${widget.label} *' : widget.label;

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return InputDecorator(
        decoration: InputDecoration(labelText: _label, enabled: false),
        child: Text(
          widget.hint ?? '-',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return FutureBuilder<List<Option>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return InputDecorator(
            decoration: InputDecoration(labelText: _label),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: _label,
              errorText: 'โหลดข้อมูลไม่สำเร็จ',
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _retry,
              ),
            ),
            child: const Text('-'),
          );
        }
        final options = snap.data ?? const <Option>[];
        final hasValue =
            widget.value != null && options.any((o) => o.id == widget.value);
        return DropdownButtonFormField<int>(
          initialValue: hasValue ? widget.value : null,
          isExpanded: true,
          menuMaxHeight: 420,
          decoration: InputDecoration(labelText: _label),
          hint: widget.hint == null ? null : Text(widget.hint!),
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o.id,
                child: Text(o.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          validator: (v) {
            if (widget.required && v == null) {
              return 'กรุณาเลือก${widget.label}';
            }
            return null;
          },
          onChanged: (id) {
            Option? selected;
            for (final o in options) {
              if (o.id == id) {
                selected = o;
                break;
              }
            }
            widget.onChanged(selected);
          },
        );
      },
    );
  }
}
