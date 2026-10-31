import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

class QuotationDetailPage extends StatelessWidget {
  const QuotationDetailPage({super.key, required this.quotationId});

  final String quotationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ใบเสนอราคา $quotationId')),
      body: const EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
