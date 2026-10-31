import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

class RepairDetailPage extends StatelessWidget {
  const RepairDetailPage({super.key, required this.repairId});

  final int repairId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ใบรับรถ # $repairId')),
      body: const EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
