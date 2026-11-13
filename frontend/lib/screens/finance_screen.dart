/// Backwards-compatible re-export.
///
/// The finance module was extracted into `features/finance` for maintainability.
/// This shim keeps existing imports (`import 'finance_screen.dart';`) working.
export '../../features/finance/presentation/screens/finance_screen.dart';
