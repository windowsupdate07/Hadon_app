import '../../core/utils/json.dart';
import '../parts/part_model.dart';

/// `Preset.Status`: 1 = ACTIVE, 2 = INACTIVE.
class PresetStatus {
  PresetStatus._();

  static const active = 1;
  static const inactive = 2;
}

/// `PresetDetails` row: a part and how many units the preset uses.
class PresetDetail {
  const PresetDetail({
    required this.id,
    required this.presetId,
    required this.partId,
    required this.numOfUse,
    this.part,
  });

  factory PresetDetail.fromJson(Map<String, dynamic> j) {
    // Default Sequelize alias for PresetDetails.belongsTo(Parts) is "part".
    final part = asMap(j['part'] ?? j['Part'] ?? j['parts']);
    return PresetDetail(
      id: asInt(j['PresetDetailID']) ?? 0,
      presetId: asInt(j['PresetID']) ?? 0,
      partId: asInt(j['PartID']) ?? 0,
      numOfUse: asInt(j['NumOfUse']) ?? 0,
      part: part == null ? null : Part.fromJson(part),
    );
  }

  final int id;
  final int presetId;
  final int partId;
  final int numOfUse;

  /// Null when the part was (soft) deleted.
  final Part? part;

  String get partName => part?.displayName ?? 'อะไหล่ #$partId (ถูกลบแล้ว)';

  /// Web rule (`checkStockAvailability`): stock must cover `NumOfUse`.
  /// A deleted part can never be supplied.
  bool get hasEnoughStock => part?.hasStockFor(numOfUse) ?? false;
}

/// `Ref_Model_Category_Parts` row that uses a preset (brand / model /
/// repair category / part category grouping), as included by `GET /preset`.
class PresetRef {
  const PresetRef({
    required this.id,
    this.repairCategory,
    this.brand,
    this.model,
    this.partCategory,
  });

  factory PresetRef.fromJson(Map<String, dynamic> j) {
    String? field(String key, String name) => asString(asMap(j[key])?[name]);
    return PresetRef(
      id: asInt(j['RefID']) ?? 0,
      repairCategory: field('repairCategory', 'RepairCategory'),
      brand: field('brand', 'Brand'),
      model: field('model', 'Model'),
      partCategory: field('partCategory', 'PartCategoryName'),
    );
  }

  final int id;
  final String? repairCategory;
  final String? brand;
  final String? model;
  final String? partCategory;

  /// e.g. "Honda (City)".
  String get vehicle {
    final b = brand ?? '-';
    return model == null ? b : '$b ($model)';
  }
}

/// `Preset` with its `presetDetails` (+ `part`) and
/// `ref_model_category_parts` includes from `GET /preset` / `GET /preset/:id`.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.status,
    this.details = const [],
    this.refs = const [],
  });

  factory Preset.fromJson(Map<String, dynamic> j) {
    final details = asMapList(
      j['presetDetails'] ?? j['PresetDetails'],
    ).map(PresetDetail.fromJson).toList();
    final refs = asMapList(
      j['ref_model_category_parts'] ?? j['Ref_Model_Category_Parts'],
    ).map(PresetRef.fromJson).toList();
    return Preset(
      id: asInt(j['PresetID']) ?? 0,
      name: asString(j['Preset']) ?? '',
      status: asInt(j['Status']) ?? PresetStatus.active,
      details: details,
      refs: refs,
    );
  }

  final int id;
  final String name;
  final int status;
  final List<PresetDetail> details;

  /// Brand/model/category groupings that use this preset.
  final List<PresetRef> refs;

  int get refCount => refs.length;

  bool get isActive => status == PresetStatus.active;

  /// "พร้อมใช้งาน" on the web: has parts and every part has enough stock.
  bool get isStockReady =>
      details.isNotEmpty && details.every((d) => d.hasEnoughStock);

  List<PresetDetail> get shortDetails =>
      details.where((d) => !d.hasEnoughStock).toList();

  /// Sum of `NumOfUse * PricePerUnit` for parts that still exist.
  double get totalPrice => details.fold(
    0,
    (sum, d) => sum + d.numOfUse * (d.part?.pricePerUnit ?? 0),
  );

  bool matches(String q) {
    final s = q.toLowerCase();
    return name.toLowerCase().contains(s) ||
        details.any((d) => d.part?.matches(q) ?? false);
  }
}
