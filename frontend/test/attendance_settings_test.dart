import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/attendance_settings_service.dart';

void main() {
  group('AttendanceSettings.fromMap', () {
    test('uses defaults for missing or invalid values', () {
      const fallback = AttendanceSettings();

      expect(
          AttendanceSettings.fromMap(null).fullDayHours, fallback.fullDayHours);
      expect(
          AttendanceSettings.fromMap({}).halfDayHours, fallback.halfDayHours);
      expect(
          AttendanceSettings.fromMap({}).graceMinutes, fallback.graceMinutes);
      expect(AttendanceSettings.fromMap({}).timezone, 'Asia/Manila');

      final invalid = AttendanceSettings.fromMap({
        'fullDayHours': 0,
        'halfDayHours': -2,
        'graceMinutes': -5,
        'scheduledStart': '   ',
        'timezone': '  ',
      });
      expect(invalid.fullDayHours, 8);
      expect(invalid.halfDayHours, 4);
      expect(invalid.graceMinutes, 0);
      expect(invalid.scheduledStart, '');
      expect(invalid.timezone, 'Asia/Manila');
    });

    test('parses numbers stored as strings', () {
      final settings = AttendanceSettings.fromMap({
        'fullDayHours': '10',
        'halfDayHours': '5.5',
        'graceMinutes': '15',
        'scheduledStart': ' 09:30 ',
      });

      expect(settings.fullDayHours, 10);
      expect(settings.halfDayHours, 5.5);
      expect(settings.graceMinutes, 15);
      expect(settings.scheduledStart, '09:30');
    });

    test('copyWith and toMap round-trip overrides', () {
      final settings = const AttendanceSettings().copyWith(
        fullDayHours: 12,
        halfDayHours: 6,
        graceMinutes: 20,
        scheduledStart: '08:00',
        timezone: 'Asia/Manila',
      );
      final map = settings.toMap();

      expect(map['fullDayHours'], 12);
      expect(map['halfDayHours'], 6);
      expect(map['graceMinutes'], 20);
      expect(map['scheduledStart'], '08:00');
      expect(map['timezone'], 'Asia/Manila');
    });
  });
}
