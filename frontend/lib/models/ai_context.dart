class AIContext {
  final String rawContextText;
  final Map<String, dynamic> structuredData;
  final String detectedIntent;

  AIContext({
    required this.rawContextText,
    required this.structuredData,
    required this.detectedIntent,
  });
}
