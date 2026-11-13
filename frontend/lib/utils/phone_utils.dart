/// Helpers for Philippine mobile numbers.
///
/// Storage format is always `63XXXXXXXXXX` so Firestore documents and
/// server-side PhilSMS calls agree on one canonical value.
class PhoneUtils {
  PhoneUtils._();

  static final RegExp _normalized = RegExp(r'^639\d{9}$');

  static String? normalizePhMobile(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    var digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) {
      digits = digits.substring(1);
    }
    digits = digits.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }

    if (digits.startsWith('63')) {
      // Already country-coded.
    } else if (digits.startsWith('0')) {
      digits = '63${digits.substring(1)}';
    } else if (digits.length == 10 && digits.startsWith('9')) {
      digits = '63$digits';
    } else {
      return null;
    }

    return _normalized.hasMatch(digits) ? digits : null;
  }

  static bool isValidPhMobile(String? value) =>
      normalizePhMobile(value) != null;

  /// Formats a canonical number as `0917 123 4567`.
  static String formatPhMobile(String? value) {
    final normalized = normalizePhMobile(value);
    if (normalized == null) return (value ?? '').trim();
    final local = '0${normalized.substring(2)}';
    return '${local.substring(0, 4)} ${local.substring(4, 7)} '
        '${local.substring(7)}';
  }

  /// Hides the middle digits for display in settings.
  static String maskPhMobile(String? value) {
    final normalized = normalizePhMobile(value);
    if (normalized == null) return 'Not set';
    final local = normalized.substring(2);
    return '+63 ${local[0]}•• ••• ${local.substring(6)}';
  }
}
