import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/error_messages.dart';

void main() {
  const authSeverities = <String, ErrorSeverity>{
    'wrong-password': ErrorSeverity.error,
    'user-not-found': ErrorSeverity.error,
    'invalid-email': ErrorSeverity.error,
    'weak-password': ErrorSeverity.error,
    'email-already-in-use': ErrorSeverity.error,
    'too-many-requests': ErrorSeverity.warning,
    'user-disabled': ErrorSeverity.warning,
    'network-request-failed': ErrorSeverity.warning,
  };

  for (final entry in authSeverities.entries) {
    test('getSeverity maps ${entry.key} to ${entry.value.name}', () {
      expect(ErrorMessageHelper.getSeverity(entry.key), entry.value);
    });
  }

  test('network-request-failed is not misread as a generic failure', () {
    expect(
      ErrorMessageHelper.getSeverity('network-request-failed'),
      ErrorSeverity.warning,
    );
  });

  test('auth message variants are classified too', () {
    expect(
      ErrorMessageHelper.getSeverity('Incorrect password'),
      ErrorSeverity.error,
    );
    expect(
      ErrorMessageHelper.getSeverity('Too many unsuccessful login attempts'),
      ErrorSeverity.warning,
    );
  });

  test('non-auth severities are unchanged', () {
    expect(
      ErrorMessageHelper.getSeverity('Exception: boom'),
      ErrorSeverity.error,
    );
    expect(
      ErrorMessageHelper.getSeverity('permission-denied'),
      ErrorSeverity.warning,
    );
    expect(
      ErrorMessageHelper.getSeverity('just a notice'),
      ErrorSeverity.info,
    );
  });
}
