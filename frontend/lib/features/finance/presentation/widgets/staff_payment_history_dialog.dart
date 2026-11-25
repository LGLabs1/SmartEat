import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/finance_format.dart';
import '../../../../theme.dart';
import '../../../../utils/staff_utils.dart';
import '../../../staff/data/staff_service.dart';

class StaffPaymentHistoryDialog extends StatelessWidget {
  const StaffPaymentHistoryDialog({
    super.key,
    required this.eateryId,
    required this.uid,
    required this.name,
    required this.fmt,
  });

  final String? eateryId;
  final String uid;
  final String name;
  final FinanceFormat fmt;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final width = ((screen.width - 48).clamp(280.0, 520.0)).toDouble();
    final height = ((screen.height - 96).clamp(360.0, 560.0)).toDouble();
    final eatery = eateryId ?? '';

    return Dialog(
      key: const Key('staff-payment-history-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(gradient: AppTheme.sageGradient),
              child: Row(children: [
                const Icon(Icons.payments_outlined, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment History',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            Expanded(
              child: eatery.isEmpty
                  ? const Center(child: Text('Eatery is not set up yet.'))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: StaffService.myPayoutsStream(eatery, uid: uid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Failed to load payment history: ${snapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        final payouts = snapshot.data?.docs
                                .map((doc) => <String, dynamic>{
                                      'id': doc.id,
                                      ...doc.data(),
                                    })
                                .toList() ??
                            <Map<String, dynamic>>[];
                        payouts.sort(_comparePayouts);
                        final summary = staffPayoutSummary(payouts);

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _SummaryCard(summary: summary, fmt: fmt),
                            const SizedBox(height: 16),
                            Text(
                              'History',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            if (payouts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Column(children: [
                                  Icon(Icons.receipt_long_outlined,
                                      size: 48, color: Colors.white38),
                                  SizedBox(height: 12),
                                  Text('No payments recorded yet.'),
                                ]),
                              )
                            else
                              for (final payout in payouts)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _PayoutRow(payout: payout, fmt: fmt),
                                ),
                          ],
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.fmt});

  final ({double paid, double advances, int count}) summary;
  final FinanceFormat fmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.account_balance_wallet, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Payout summary',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _SummaryTile(
                label: 'Weekly payouts',
                value: fmt.money(summary.paid),
                color: AppTheme.sageSuccess,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: 'Advances',
                value: fmt.money(summary.advances),
                color: AppTheme.warning,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            '${summary.count} ${summary.count == 1 ? 'record' : 'records'} · advances are deducted from weekly pay',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.sageNavy,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ]),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout, required this.fmt});

  final Map<String, dynamic> payout;
  final FinanceFormat fmt;

  @override
  Widget build(BuildContext context) {
    final isAdvance =
        (payout['type'] ?? 'weekly').toString().trim().toLowerCase() ==
            'advance';
    final weekStart = (payout['weekStart'] ?? '').toString().trim();
    final amount = (payout['amount'] as num?)?.toDouble() ?? 0.0;
    final paidBy = (payout['paidByName'] ?? '').toString().trim();
    final paidAt = _formatDate(payout['paidAt'] ?? payout['createdAt']);
    final details = <String>[
      if (isAdvance) 'Advance' else 'Weekly payout',
      if (paidBy.isNotEmpty) 'by $paidBy',
      if (paidAt.isNotEmpty) paidAt,
    ];

    return Card(
      elevation: 0,
      color: AppTheme.sagePanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAdvance ? AppTheme.warning : AppTheme.sageSuccess,
          child: Icon(
            isAdvance ? Icons.trending_up : Icons.payments_outlined,
            color: Colors.white,
          ),
        ),
        title: Text(
          weekStart.isEmpty ? 'Unknown week' : 'Week of $weekStart',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details.join(' · ')),
        trailing: Text(
          isAdvance ? '-${fmt.money(amount)}' : fmt.money(amount),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isAdvance ? AppTheme.warning : AppTheme.sageSuccess,
          ),
        ),
      ),
    );
  }
}

int _comparePayouts(Map<String, dynamic> a, Map<String, dynamic> b) {
  final byWeek = (b['weekStart'] ?? '').toString().compareTo(
        (a['weekStart'] ?? '').toString(),
      );
  if (byWeek != 0) return byWeek;
  return _paidAtMillis(b).compareTo(_paidAtMillis(a));
}

int _paidAtMillis(Map<String, dynamic> payout) {
  final value = payout['paidAt'] ?? payout['createdAt'];
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is String)
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  return 0;
}

String _formatDate(dynamic value) {
  if (value is Timestamp) return _ymd(value.toDate());
  if (value is DateTime) return _ymd(value);
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return _ymd(parsed);
    return value.split('T').first;
  }
  return '';
}

String _ymd(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
