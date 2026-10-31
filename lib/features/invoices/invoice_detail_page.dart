import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

class InvoiceDetailPage extends StatelessWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ใบแจ้งหนี้ $invoiceId')),
      body: const EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
