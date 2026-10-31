import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

class CustomerDetailPage extends StatelessWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ลูกค้า # $customerId')),
      body: const EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
