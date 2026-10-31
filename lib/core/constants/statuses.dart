import 'package:flutter/material.dart';

/// Status label + colour pair used by [StatusChip].
class StatusInfo {
  const StatusInfo(this.label, this.color);

  final String label;
  final Color color;
}

/// Values mirror `honda-ntp-antigravity/backend/seeders/data/workstatus.json`.
class WorkStatus {
  WorkStatus._();

  static const checking = 1;
  static const checked = 2;
  static const invoice = 3;
  static const allocating = 4;
  static const repairing = 5;
  static const repaired = 6;
  static const success = 7;
  static const purchasing = 8;
  static const allocateMore = 9;
  static const cancel = 99;

  static const all = [
    checking, checked, invoice, allocating, repairing, //
    allocateMore, repaired, success, purchasing, cancel,
  ];

  static StatusInfo info(int? id) {
    switch (id) {
      case checking:
        return const StatusInfo('กำลังตรวจสอบรถ', Colors.blueGrey);
      case checked:
        return const StatusInfo('ตรวจสอบรถแล้ว', Colors.indigo);
      case invoice:
        return const StatusInfo('สร้างใบแจ้งหนี้', Colors.purple);
      case allocating:
        return const StatusInfo('รอจัดสรรอุปกรณ์', Colors.orange);
      case repairing:
        return const StatusInfo('อยู่ระหว่างซ่อม', Colors.blue);
      case repaired:
        return const StatusInfo('ซ่อมเสร็จแล้ว', Colors.teal);
      case success:
        return const StatusInfo('เสร็จสิ้น', Colors.green);
      case purchasing:
        return const StatusInfo('อยู่ระหว่างการจัดซื้ออุปกรณ์', Colors.brown);
      case allocateMore:
        return const StatusInfo(
          'อยู่ระหว่างซ่อม (จัดสรรอุปกรณ์เพิ่มเติม)',
          Colors.deepOrange,
        );
      case cancel:
        return const StatusInfo('ยกเลิกการซ่อม', Colors.red);
      default:
        return const StatusInfo('-', Colors.grey);
    }
  }
}

/// Values mirror `honda-ntp-antigravity/backend/seeders/data/invoiceStatus.json`.
class InvoiceStatus {
  InvoiceStatus._();

  static const pendingConfirm = 1;
  static const pendingPayment = 2;
  static const paid = 3;
  static const cancelled = 99;

  static StatusInfo info(int? id) {
    switch (id) {
      case pendingConfirm:
        return const StatusInfo('รอยืนยันใบแจ้งหนี้', Colors.orange);
      case pendingPayment:
        return const StatusInfo('รอชำระเงิน', Colors.blue);
      case paid:
        return const StatusInfo('ชำระเงินแล้ว', Colors.green);
      case cancelled:
      case 4: // older ntp-api used 4
        return const StatusInfo('ยกเลิกใบแจ้งหนี้', Colors.red);
      default:
        return const StatusInfo('-', Colors.grey);
    }
  }
}

/// Values mirror `ntp-api/seeders/data/partstatus.json`.
class PartStatus {
  PartStatus._();

  static const locked = 1;
  static const used = 2;
  static const purchasing = 3;

  static StatusInfo info(int? id) {
    switch (id) {
      case locked:
        return const StatusInfo('ล็อค', Colors.orange);
      case used:
        return const StatusInfo('ใช้งานแล้ว', Colors.green);
      case purchasing:
        return const StatusInfo('อยู่ระหว่างจัดซื้อ', Colors.brown);
      default:
        return const StatusInfo('-', Colors.grey);
    }
  }
}

/// Values mirror `ntp-api/seeders/data/positions.json`.
class Position {
  Position._();

  static const admin = 1;
  static const manager = 2;
  static const accountant = 3;
  static const receptionist = 4;
  static const technician = 5;
}

const vatRate = 0.07;
