import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../repair_models.dart';
import '../repairs_api.dart';

/// Shows the invoice created for this repair (if any) with a link to it.
/// Invoices are normally created together with the repair from a quotation
/// (`POST /invoices/create-with-repair`); cancelling the repair cancels it.
class InvoiceLinkCard extends StatefulWidget {
  const InvoiceLinkCard({super.key, required this.api, required this.repairId});

  final RepairsApi api;
  final int repairId;

  @override
  State<InvoiceLinkCard> createState() => _InvoiceLinkCardState();
}

class _InvoiceLinkCardState extends State<InvoiceLinkCard> {
  late Future<RepairInvoice?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.invoice(widget.repairId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RepairInvoice?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snap.hasError) {
          return SectionCard(
            title: 'ใบแจ้งหนี้',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    snap.error.toString(),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _future = widget.api.invoice(widget.repairId);
                  }),
                  child: const Text('ลองใหม่'),
                ),
              ],
            ),
          );
        }
        final inv = snap.data;
        if (inv == null) {
          return const SizedBox.shrink();
        }
        final status = InvoiceStatus.info(inv.statusId);
        return SectionCard(
          title: 'ใบแจ้งหนี้',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              inv.invoiceId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(formatThaiDate(inv.invoiceDate)),
                  if (inv.amount != null && inv.amount! > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${formatMoney(inv.amount)} บาท',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Flexible(
                    child: StatusChip(
                      inv.statusTitle == null || status.label != '-'
                          ? status
                          : StatusInfo(inv.statusTitle!, Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.push('/invoices/${Uri.encodeComponent(inv.invoiceId)}'),
          ),
        );
      },
    );
  }
}
