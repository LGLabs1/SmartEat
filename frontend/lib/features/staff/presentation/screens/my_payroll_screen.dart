import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/auth_provider.dart';
import '../../../../theme.dart';
import '../../../../utils/staff_utils.dart';
import '../../../../widgets/dashboard/section_card.dart';
import '../../../../widgets/dashboard/sage_hover_card.dart';
import '../../../../widgets/feature_tab_header.dart';
import '../../../../widgets/smart_eat_header.dart';
import '../../data/staff_service.dart';

class MyPayrollScreen extends StatefulWidget {
  const MyPayrollScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FeatureTabHeader(
          title: 'My payroll',
          tabs: [
            FeatureTabItem(label: 'Payouts', icon: Icons.payments_outlined),
          ],
          selectedIndex: 0,
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _Message(
                  text: 'Failed to load profile: ${snapshot.error}',
                );
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
        ),
      ],
    );
    if (!widget.showAppBar) return content;
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: SmartEatHeader(
          titleText: 'My payroll',
          showBackButton: true,
          actions: const [SizedBox(width: 4)],
        ),
        body: content,
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
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          children: [
            _SummaryCard(summary: summary),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Payout history',
              icon: Icons.history_outlined,
              badge: '${payouts.length}',
              child: payouts.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: [
                        for (final payout in payouts)
                          _PayoutCard(payout: payout),
                      ],
                    ),
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

    return SectionCard(
      title: 'Payout summary',
      icon: Icons.account_balance_wallet_outlined,
      badge: '${summary.count} ${summary.count == 1 ? 'record' : 'records'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Weekly payouts',
                  value: _money(summary.paid),
                  color: AppTheme.sageSuccess,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryTile(
                  label: 'Advances',
                  value: _money(summary.advances),
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Advances are deducted from weekly pay',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    final accent = isAdvance ? AppTheme.warning : AppTheme.sageSuccess;

    return SageHoverCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      accent: accent,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent,
            child: Icon(
              isAdvance ? Icons.trending_up : Icons.payments_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weekStart.isEmpty ? 'Unknown week' : 'Week of $weekStart',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  details.join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isAdvance ? '-${_money(amount)}' : _money(amount),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No payouts recorded yet.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
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
