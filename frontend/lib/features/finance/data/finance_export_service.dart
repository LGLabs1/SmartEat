import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'finance_format.dart';
import 'finance_metrics.dart';

/// Builds and persists CSV exports of finance data to the app documents
/// directory. No third-party CSV package is used so the output is fully
/// controlled (RFC-4180-style quoting).
class FinanceExportService {
  FinanceExportService._();

  static String _escape(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  static String _row(List<Object?> cells) =>
      cells.map((c) => _escape((c ?? '').toString())).join(',');

  /// Returns the generated CSV body for the provided expenses.
  static String buildExpensesCsv(
    List<Map<String, dynamic>> expenses,
    FinanceFormat fmt,
  ) {
    final buf = StringBuffer();
    buf.writeln(_row(const [
      'Date',
      'Name',
      'Category',
      'Amount',
      'Supplier',
      'Receipt',
      'Payment Method',
      'Status',
      'Source',
      'Linked Purchase',
      'Notes',
    ]));
    for (final e in expenses) {
      final date = FinanceMetrics.expenseDate(e);
      buf.writeln(_row([
        date == null ? '' : FinanceFormat.date(date),
        (e['name'] ?? '').toString(),
        (e['category'] ?? '').toString(),
        FinanceMetrics.amountOf(e).toStringAsFixed(2),
        (e['supplierName'] ?? '').toString(),
        (e['receiptNumber'] ?? '').toString(),
        (e['paymentMethod'] ?? '').toString(),
        (e['paymentStatus'] ?? '').toString(),
        FinanceMetrics.source(e),
        (e['linkedPurchaseId'] ?? '').toString(),
        (e['notes'] ?? '').toString(),
      ]));
    }
    return buf.toString();
  }

  /// Returns the generated CSV body for the provided payables.
  static String buildPayablesCsv(
    List<Map<String, dynamic>> payables,
    FinanceFormat fmt,
  ) {
    final buf = StringBuffer();
    buf.writeln(_row(const [
      'Due Date',
      'Name',
      'Vendor',
      'Frequency',
      'Amount Type',
      'Amount',
      'Estimated',
      'Status',
      'Notes',
    ]));
    for (final p in payables) {
      final due = FinanceFormat.asDate(p['dueDate']);
      final isVariable = FinanceMetrics.isVariablePayable(p);
      buf.writeln(_row([
        due == null ? '' : FinanceFormat.date(due),
        (p['name'] ?? '').toString(),
        (p['vendor'] ?? '').toString(),
        (p['frequency'] ?? '').toString(),
        isVariable ? 'variable' : 'fixed',
        isVariable ? '' : FinanceMetrics.amountOf(p).toStringAsFixed(2),
        isVariable
            ? FinanceMetrics.estimatedAmountOf(p).toStringAsFixed(2)
            : '',
        FinanceMetrics.isPaid(p) ? 'paid' : 'unpaid',
        (p['notes'] ?? '').toString(),
      ]));
    }
    return buf.toString();
  }

  /// Writes [contents] to `<documents>/exports/<fileName>` and returns the
  /// absolute path. Throws on IO failure so callers can surface an error.
  static Future<String> writeCsv(String fileName, String contents) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/${fileName}_$stamp.csv');
    await file.writeAsString(contents);
    return file.path;
  }
}
