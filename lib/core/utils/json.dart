// Lenient JSON readers. MySQL DECIMAL/DOUBLE columns may arrive as strings,
// and booleans may arrive as 0/1, so models parse through these helpers.

int? asInt(dynamic v) {
  if (v == null) {
    return null;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse(v.toString());
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) {
    return fallback;
  }
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse(v.toString()) ?? fallback;
}

String? asString(dynamic v) {
  if (v == null) {
    return null;
  }
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool asBool(dynamic v) {
  if (v is bool) {
    return v;
  }
  if (v is num) {
    return v != 0;
  }
  if (v is String) {
    return v == '1' || v.toLowerCase() == 'true';
  }
  return false;
}

DateTime? asDate(dynamic v) {
  if (v == null) {
    return null;
  }
  return DateTime.tryParse(v.toString())?.toLocal();
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return null;
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) {
    return const [];
  }
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
