import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';

/// Spare part (`Parts` table). `PartAmount` is the quantity in stock.
class Part {
  const Part({
    required this.id,
    this.partNumber,
    this.nameTh,
    this.nameEn,
    this.amount = 0,
    this.pricePerUnit = 0,
    this.serviceFee = 0,
    this.unitId,
    this.unitName,
  });

  factory Part.fromJson(Map<String, dynamic> j) {
    final unit = asMap(j['unit'] ?? j['Unit']);
    return Part(
      id: asInt(j['PartID']) ?? 0,
      partNumber: asString(j['PartNumber']),
      nameTh: asString(j['PartName_th']),
      nameEn: asString(j['PartName_en']),
      amount: asDouble(j['PartAmount']),
      pricePerUnit: asDouble(j['PricePerUnit']),
      serviceFee: asDouble(j['ServiceFee']),
      unitId: asInt(j['UnitID']),
      unitName: asString(unit?['Unit']),
    );
  }

  final int id;
  final String? partNumber;
  final String? nameTh;
  final String? nameEn;
  final double amount;
  final double pricePerUnit;
  final double serviceFee;
  final int? unitId;
  final String? unitName;

  String get displayName => nameTh ?? nameEn ?? partNumber ?? '#$id';

  Map<String, dynamic> toJson() => {
        'PartNumber': partNumber,
        'PartName_th': nameTh,
        'PartName_en': nameEn,
        'PartAmount': amount,
        'PricePerUnit': pricePerUnit,
        'ServiceFee': serviceFee,
        'UnitID': unitId,
      };

  bool matches(String q) {
    final s = q.toLowerCase();
    return (partNumber ?? '').toLowerCase().contains(s) ||
        (nameTh ?? '').toLowerCase().contains(s) ||
        (nameEn ?? '').toLowerCase().contains(s);
  }
}

class PartsApi {
  PartsApi(this._api);

  final ApiClient _api;

  Future<List<Part>> findAll() => _api.getList('/parts', Part.fromJson);

  Future<Part> findOne(int id) => _api.getOne('/parts/$id', Part.fromJson);

  Future<void> create(Map<String, dynamic> body) =>
      _api.post('/parts', data: body);

  Future<void> update(int id, Map<String, dynamic> body) =>
      _api.put('/parts/$id', data: body);

  Future<void> remove(int id) => _api.delete('/parts/$id');
}
