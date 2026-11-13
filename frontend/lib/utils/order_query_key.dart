/// Builds a stable cache key for a ranged orders query so identical concurrent
/// calls can share a single in-flight Firestore fetch instead of each paying
/// for its own download. Keyed on eatery + the exact date window.
String orderQueryKey(String eateryId, DateTime? startDate, DateTime? endDate) =>
    '$eateryId|${startDate?.toIso8601String()}|${endDate?.toIso8601String()}';