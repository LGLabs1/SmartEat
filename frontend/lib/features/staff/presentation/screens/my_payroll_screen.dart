import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/auth_provider.dart';
import '../../../../utils/staff_utils.dart';
import '../../data/staff_service.dart';

/// Staff-facing history of the signed-in user's own payroll payouts.
class MyPayrollScreen extends StatefulWidget {
  const MyPayrollScreen({super.key});

  @override
  State<MyPayrollScreen> createState() => _MyPayrollScreenState();
}

class _MyPayrollScreenState extends State<MyPayrollScreen> {
  late final Future<Map<String, dynamic>?> _profileFuture;
  late final String _uid;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _uid = auth.user?.uid ?? '';
    _profileFuture = auth.getCurrentUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My payroll')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(text: 'Failed to load profile: ${snapshot.error}');
          }
          if (_uid.isEmpty) {
            return const _Message(text: 'You are not signed in.');
          }
          final profile = snapshot.data;
          final eateryId = (profile?['eateryId'] ?? '').toString().trim();
          if (eateryId.isEmpty) {
            return const _Message(
              text: 'Your account is not linked to an eatery yet.',
            );
          }
          return _PayoutHistory(eateryId: eateryId, uid: _uid);
        },
      ),
    );
  }
}

class _PayoutHistory extends StatelessWidget {
  const _PayoutHistory({required this.eateryId, required this.uid});

  final String eateryId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: StaffService.myPayoutsStream(eateryId, uid: uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message(text: 'Failed to load payroll: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final payouts = docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList()
          ..sort(_comparePayouts);
        final summary = staffPayoutSummary(payouts);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(summary: summary),
            const SizedBox(height: 20),
            Text(
              'History',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (payouts.isEmpty)
              const _EmptyState()
            else
              for (final payout in payouts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PayoutCard(payout: payout),
                ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ({double paid, double advances, int count}) summary;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Payout summary',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Weekly payouts',
                    value: _money(summary.paid),
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: 'Advances',
                    value: _money(summary.advances),
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${summary.count} ${summary.count == 1 ? 'record' : 'records'} · '
              'advances are deducted from weekly pay',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
        ],
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.payout});

  final Map<String, dynamic> payout;

  @override
  Widget build(BuildContext context) {
    final type = (payout['type'] ?? 'weekly').toString().trim().toLowerCase();
    final isAdvance = type == 'advance';
    final weekStart = (payout['weekStart'] ?? '').toString().trim();
    final amountRaw = payout['amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : 0.0;
    final paidBy = (payout['paidByName'] ?? '').toString().trim();
    final paidAt = _formatDate(payout['paidAt'] ?? payout['createdAt']);

    final details = <String>[
      if (isAdvance) 'Advance' else 'Weekly payout',
      if (paidBy.isNotEmpty) 'by $paidBy',
      if (paidAt.isNotEmpty) paidAt,
    ];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isAdvance ? Colors.orange.shade400 : Colors.green.shade500,
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
          isAdvance ? '-${_money(amount)}' : _money(amount),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isAdvance ? Colors.orange.shade800 : Colors.green.shade800,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'No payouts recorded yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

String _money(double value) => '₱${value.toStringAsFixed(2)}';

int _comparePayouts(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aWeek = (a['weekStart'] ?? '').toString();
  final bWeek = (b['weekStart'] ?? '').toString();
  final byWeek = bWeek.compareTo(aWeek);
  if (byWeek != 0) return byWeek;
  return _paidAtMillis(b).compareTo(_paidAtMillis(a));
}

int _paidAtMillis(Map<String, dynamic> payout) {
  final value = payout['paidAt'] ?? payout['createdAt'];
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is String) {
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  }
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

String _ymd(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
