class UnitConversionException implements Exception {
  const UnitConversionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UnitConversion {
  static const Map<String, String> _aliases = {
    'g': 'g',
    'gram': 'g',
    'grams': 'g',
    'kg': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'mg': 'mg',
    'milligram': 'mg',
    'milligrams': 'mg',
    'ml': 'ml',
    'milliliter': 'ml',
    'milliliters': 'ml',
    'millilitre': 'ml',
    'millilitres': 'ml',
    'l': 'l',
    'liter': 'l',
    'liters': 'l',
    'litre': 'l',
    'litres': 'l',
    'cl': 'cl',
    'centiliter': 'cl',
    'centiliters': 'cl',
    'centilitre': 'cl',
    'centilitres': 'cl',
    'dl': 'dl',
    'deciliter': 'dl',
    'deciliters': 'dl',
    'decilitre': 'dl',
    'decilitres': 'dl',
    'pc': 'pcs',
    'pcs': 'pcs',
    'piece': 'pcs',
    'pieces': 'pcs',
    'pack': 'pack',
    'packs': 'pack',
    'bottle': 'bottle',
    'bottles': 'bottle',
    'box': 'box',
    'boxes': 'box',
    'can': 'can',
    'cans': 'can',
    'dozen': 'dozen',
    'dozens': 'dozen',
  };

  static const Map<String, String> _families = {
    'g': 'mass',
    'kg': 'mass',
    'mg': 'mass',
    'ml': 'volume',
    'l': 'volume',
    'cl': 'volume',
    'dl': 'volume',
    'pcs': 'count',
    'pack': 'count',
    'bottle': 'count',
    'box': 'count',
    'can': 'count',
    'dozen': 'count',
  };

  static const Map<String, double> _toCanonical = {
    'mg': 0.001,
    'g': 1,
    'kg': 1000,
    'ml': 1,
    'cl': 10,
    'dl': 100,
    'l': 1000,
    'pcs': 1,
    'pack': 1,
    'bottle': 1,
    'box': 1,
    'can': 1,
    'dozen': 1,
  };

  static double toBase(double qty, double conversionFactor) {
    if (conversionFactor <= 0) return qty;
    return qty * conversionFactor;
  }

  static double fromBase(double qtyBase, double conversionFactor) {
    if (conversionFactor <= 0) return qtyBase;
    return qtyBase / conversionFactor;
  }

  static double normalizeFactor(double? factor) {
    if (factor == null || factor <= 0) return 1.0;
    return factor;
  }

  static String normalizeUnit(String unit) {
    final normalized = unit.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    return _aliases[normalized] ?? normalized;
  }

  static bool isCompatible(String fromUnit, String toUnit) {
    final from = normalizeUnit(fromUnit);
    final to = normalizeUnit(toUnit);
    if (from.isEmpty || to.isEmpty) return false;
    if (from == to) return true;
    final fromFamily = _families[from];
    final toFamily = _families[to];
    if (fromFamily == null || toFamily == null) return false;
    return fromFamily == toFamily;
  }

  static double convert(double value, String fromUnit, String toUnit) {
    final from = normalizeUnit(fromUnit);
    final to = normalizeUnit(toUnit);
    if (from.isEmpty || to.isEmpty) return value;
    if (from == to) return value;

    final fromFamily = _families[from];
    final toFamily = _families[to];
    final fromFactor = _toCanonical[from];
    final toFactor = _toCanonical[to];

    if (fromFamily == null ||
        toFamily == null ||
        fromFactor == null ||
        toFactor == null ||
        fromFamily != toFamily) {
      throw UnitConversionException(
        'Cannot convert $fromUnit to $toUnit. Use compatible mass or volume units.',
      );
    }

    return value * fromFactor / toFactor;
  }

  static double costPerUnit({
    required double inventoryUnitCost,
    required String inventoryUnit,
    required String recipeUnit,
  }) {
    return inventoryUnitCost * convert(1, recipeUnit, inventoryUnit);
  }
}
