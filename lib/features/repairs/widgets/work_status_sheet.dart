import 'package:flutter/material.dart';

import '../../../core/constants/statuses.dart';

/// Bottom sheet listing every [WorkStatus]; returns the chosen id or null.
Future<int?> showWorkStatusSheet(BuildContext context, int? current) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'เปลี่ยนสถานะงานซ่อม',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final id in WorkStatus.all)
              ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 14,
                  color: WorkStatus.info(id).color,
                ),
                title: Text(WorkStatus.info(id).label),
                trailing: id == current
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.of(context).pop(id),
              ),
          ],
        ),
      ),
    ),
  );
}
