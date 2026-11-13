import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Human-readable label for a stored order `paymentMethod` value.
String paymentMethodLabel(String method) => switch (method) {
      'gcash' => 'GCash',
      'other' => 'Other E-Wallet',
      _ => 'Cash',
    };

/// Payment details captured at checkout.
///
/// Cash orders carry the amount received and the computed change; non-cash
/// orders carry an optional reference number and an explicit paid/pending
/// status.
class PaymentDetails {
  const PaymentDetails({
    required this.method,
    this.amountReceived,
    this.change,
    this.referenceNumber,
    required this.paymentStatus,
    this.wantsReceipt = false,
  });

  /// `'cash'`, `'gcash'` or `'other'`.
  final String method;

  /// Cash only: the amount handed over by the customer.
  final double? amountReceived;

  /// Cash only: `amountReceived - total`, never negative once submitted.
  final double? change;

  /// Non-cash only: e-wallet reference / transaction number, if provided.
  final String? referenceNumber;

  /// `'paid'` or `'pending'` (always `'paid'` for cash).
  final String paymentStatus;

  /// Whether the user asked for a receipt for this order.
  final bool wantsReceipt;
}

/// Opens the checkout payment dialog.
///
/// Returns the captured [PaymentDetails], or null when cancelled. When
/// [askForReceipt] is true an extra "print a receipt?" switch is offered and
/// the result's [PaymentDetails.wantsReceipt] carries the answer.
Future<PaymentDetails?> showPaymentDetailsDialog(
  BuildContext context, {
  required double totalAmount,
  bool askForReceipt = false,
}) {
  return showDialog<PaymentDetails>(
    context: context,
    builder: (_) => PaymentMethodDialog(
      totalAmount: totalAmount,
      askForReceipt: askForReceipt,
    ),
  );
}

/// Collects the payment method — and the details that come with it — before
/// an order is completed.
///
/// * Cash: the amount received is required, change is computed live, and
///   completing is blocked while the amount is below the order total.
/// * GCash / Other E-Wallet: an optional reference number and a paid/pending
///   status toggle.
class PaymentMethodDialog extends StatefulWidget {
  const PaymentMethodDialog({
    super.key,
    required this.totalAmount,
    this.askForReceipt = false,
  });

  final double totalAmount;
  final bool askForReceipt;

  @override
  State<PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<PaymentMethodDialog> {
  static const _methods = ['cash', 'gcash', 'other'];

  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  String _method = 'cash';
  String _paymentStatus = 'paid';
  bool _wantsReceipt = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the live change readout stays current
    // (and any error clears as soon as the amount is edited).
    _amountController.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  double? get _amountReceived =>
      double.tryParse(_amountController.text.trim());

  bool get _isCash => _method == 'cash';

  double get _change {
    final received = _amountReceived ?? 0;
    return received - widget.totalAmount;
  }

  bool get _canComplete {
    if (!_isCash) return true;
    return (_amountReceived ?? 0) >= widget.totalAmount;
  }

  void _submit() {
    if (_isCash) {
      final received = _amountReceived;
      if (received == null) {
        setState(() => _error = 'Enter the amount received');
        return;
      }
      if (received < widget.totalAmount) {
        setState(() => _error = 'Insufficient amount received');
        return;
      }
      Navigator.of(context).pop(PaymentDetails(
        method: _method,
        amountReceived: received,
        change: received - widget.totalAmount,
        paymentStatus: 'paid',
        wantsReceipt: _wantsReceipt,
      ));
      return;
    }
    Navigator.of(context).pop(PaymentDetails(
      method: _method,
      referenceNumber: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      paymentStatus: _paymentStatus,
      wantsReceipt: _wantsReceipt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Payment Method'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Order Total',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₱${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final method in _methods)
                    ChoiceChip(
                      label: Text(paymentMethodLabel(method)),
                      avatar: Icon(
                        switch (method) {
                          'cash' => Icons.payments_outlined,
                          'gcash' => Icons.account_balance_wallet_outlined,
                          _ => Icons.phone_android_rounded,
                        },
                        size: 18,
                      ),
                      selected: _method == method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isCash) ..._buildCashFields(scheme)
              else ..._buildEWalletFields(scheme),
              if (widget.askForReceipt) ...[
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Print a receipt for this order?'),
                  value: _wantsReceipt,
                  onChanged: (value) =>
                      setState(() => _wantsReceipt = value),
                  secondary: const Icon(Icons.receipt_long_outlined),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canComplete ? _submit : null,
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Complete Order'),
        ),
      ],
    );
  }

  List<Widget> _buildCashFields(ColorScheme scheme) {
    final change = _change;
    return [
      TextField(
        controller: _amountController,
        autofocus: true,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: 'Amount Received',
          prefixIcon: const SizedBox(
            width: 56,
            child: Center(
              child: Text(
                '₱',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          errorText: _error,
        ),
      ),
      const SizedBox(height: 8),
      ActionChip(
        label: const Text('Exact amount'),
        onPressed: () => _amountController.text =
            widget.totalAmount.toStringAsFixed(2),
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: change >= 0
              ? Colors.green.withValues(alpha: 0.08)
              : scheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              'CHANGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: change >= 0
                    ? Colors.green.shade700
                    : scheme.error,
              ),
            ),
            const Spacer(),
            Text(
              '₱${change.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: change >= 0
                    ? Colors.green.shade700
                    : scheme.error,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildEWalletFields(ColorScheme scheme) {
    return [
      TextField(
        controller: _referenceController,
        decoration: const InputDecoration(
          labelText: 'Reference Number',
          hintText: 'Optional',
          prefixIcon: Icon(Icons.tag),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'PAYMENT STATUS',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'paid',
            label: Text('Paid'),
            icon: Icon(Icons.check_circle_outline, size: 18),
          ),
          ButtonSegment(
            value: 'pending',
            label: Text('Pending'),
            icon: Icon(Icons.schedule, size: 18),
          ),
        ],
        selected: {_paymentStatus},
        onSelectionChanged: (selection) =>
            setState(() => _paymentStatus = selection.first),
      ),
    ];
  }
}
