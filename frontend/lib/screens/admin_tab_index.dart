/// Public admin dashboard tab indices so nested admin screens (e.g. Finance's
/// "go to Staff Payroll") can navigate without hardcoding index literals.
class AdminTabIndex {
  AdminTabIndex._();
  static const int home = 0;
  static const int menu = 1;
  static const int orders = 2;
  static const int inventory = 3;
  static const int analytics = 4;
  static const int finance = 5;
  static const int staff = 6;
}