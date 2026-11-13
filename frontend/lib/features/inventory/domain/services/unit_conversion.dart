class UnitConversion {
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
}
