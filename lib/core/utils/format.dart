import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.00', 'en_US');
final _number = NumberFormat('#,##0.##', 'en_US');

const _thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', //
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// 1234.5 -> "1,234.50"
String formatMoney(num? value) => _money.format(value ?? 0);

/// 1234.5 -> "1,234.5", 3 -> "3"
String formatNumber(num? value) => _number.format(value ?? 0);

/// Thai short date with Buddhist year, e.g. "5 มี.ค. 2569".
String formatThaiDate(DateTime? date) {
  if (date == null) {
    return '-';
  }
  return '${date.day} ${_thaiMonthsShort[date.month - 1]} ${date.year + 543}';
}

/// Thai date + 24h time, e.g. "5 มี.ค. 2569 14:05".
String formatThaiDateTime(DateTime? date) {
  if (date == null) {
    return '-';
  }
  final time = DateFormat('HH:mm').format(date);
  return '${formatThaiDate(date)} $time';
}

/// Date sent to the API (yyyy-MM-dd).
String formatApiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
