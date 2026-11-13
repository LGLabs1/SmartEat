part of 'package:smarteat/screens/staff_management_screen.dart';

class _PayrollTab extends StatefulWidget {
  const _PayrollTab({
    required this.eateryId,
    required this.usersByUid,
    required this.weekStart,
    required this.onRecordPayout,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final DateTime weekStart;
  final Future<void> Function(
    String uid,
    String userLabel,
    double amount,
    String type,
  ) onRecordPayout;

  @override
  State<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<_PayrollTab> {
  // Memoized per eatery/week so rebuilds reuse the same Firestore listeners.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _profilesStream;
  String _profilesStreamKey = '';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _attendanceStream;
  String _attendanceStreamKey = '';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _payoutsStream;
  String _payoutsStreamKey = '';

  Stream<QuerySnapshot<Map<String, dynamic>>> _profilesFor(String eateryId) {
    if (_profilesStream == null || _profilesStreamKey != eateryId) {
      _profilesStreamKey = eateryId;
      _profilesStream = StaffService.staffProfilesStream(eateryId);
    }
    return _profilesStream!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceFor(
      String eateryId, String startKey, String endKey) {
    final key = '$eateryId|$startKey|$endKey';
    if (_attendanceStream == null || _attendanceStreamKey != key) {
      _attendanceStreamKey = key;
      _attendanceStream = StaffService.attendanceStream(
        eateryId,
        startKey: startKey,
        endKey: endKey,
      );
    }
    return _attendanceStream!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _payoutsFor(
      String eateryId, String startKey) {
    final key = '$eateryId|$startKey';
    if (_payoutsStream == null || _payoutsStreamKey != key) {
      _payoutsStreamKey = key;
      _payoutsStream = StaffService.payrollPayoutsStream(
        eateryId,
        weekStartKey: startKey,
      );
    }
    return _payoutsStream!;
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtMoney(double v) => '₱${v.toStringAsFixed(2)}';

  String _displayName(Map<String, dynamic> data, String uid) =>
      staffDisplayName(data, uid);

  @override
  Widget build(BuildContext context) {
    final weekEnd = widget.weekStart.add(const Duration(days: 6));
    final startKey = _fmtDate(widget.weekStart);
    final endKey = _fmtDate(weekEnd);

    final profilesStream = _profilesFor(widget.eateryId);
    final attendanceStream =
        _attendanceFor(widget.eateryId, startKey, endKey);
    final payoutsStream = _payoutsFor(widget.eateryId, startKey);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: profilesStream,
      builder: (context, profSnap) {
        final rateByUid = <String, double>{};
        final halfDayRateByUid = <String, double>{};
        if (profSnap.hasData) {
          for (final d in profSnap.data!.docs) {
            final p = d.data();
            final uid = (p['uid'] ?? '').toString().trim();
            if (uid.isEmpty) continue;
            final raw = p['dailyRate'];
            final rate = raw is num ? raw.toDouble() : 0.0;
            rateByUid[uid] = rate;

            final rawHalf = p['halfDayRate'];
            final halfRate = rawHalf is num ? rawHalf.toDouble() : 0.0;
            halfDayRateByUid[uid] = halfRate;
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: attendanceStream,
          builder: (context, attSnap) {
            final fullDaysByUid = <String, int>{};
            final halfDaysByUid = <String, int>{};
            if (attSnap.hasData) {
              for (final d in attSnap.data!.docs) {
                final a = d.data();
                final uid = (a['uid'] ?? '').toString().trim();
                if (uid.isEmpty) continue;

                final rawUnit = a['workUnit'];
                final unit = rawUnit is num
                    ? rawUnit.toDouble()
                    : (a['present'] == true ? 1.0 : 0.0);

                if (unit >= 1.0) {
                  fullDaysByUid[uid] = (fullDaysByUid[uid] ?? 0) + 1;
                } else if (unit > 0) {
                  halfDaysByUid[uid] = (halfDaysByUid[uid] ?? 0) + 1;
                }
              }
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: payoutsStream,
              builder: (context, paySnap) {
                if (paySnap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load payouts: ${paySnap.error}'),
                    ),
                  );
                }
                final paidWeeklyByUid = <String, double>{};
                final advancesByUid = <String, double>{};
                if (paySnap.hasData) {
                  for (final d in paySnap.data!.docs) {
                    final p = d.data();
                    final uid = (p['uid'] ?? '').toString().trim();
                    if (uid.isEmpty) continue;
                    final raw = p['amount'];
                    final amount = raw is num ? raw.toDouble() : 0.0;
                    final type = (p['type'] ?? 'weekly').toString().trim();
                    if (type == 'advance') {
                      advancesByUid[uid] = (advancesByUid[uid] ?? 0) + amount;
                    } else {
                      paidWeeklyByUid[uid] = amount;
                    }
                  }
                }

                final uids = widget.usersByUid.entries
                    .where((e) => !isAdminUser(e.value))
                    .map((e) => e.key)
                    .toList()
                  ..sort();
                double grandTotal = 0;

                final rows = uids.map((uid) {
                  final userData =
                      widget.usersByUid[uid] ?? const <String, dynamic>{};
                  final label = _displayName(userData, uid);
                  final fullDays = fullDaysByUid[uid] ?? 0;
                  final halfDays = halfDaysByUid[uid] ?? 0;
                  final rate = rateByUid[uid] ?? 0.0;
                  final halfDayRate = effectiveHalfDayRate(
                    dailyRate: rate,
                    halfDayRate: halfDayRateByUid[uid] ?? 0.0,
                  );

                  final gross = computeGrossPay(
                    dailyRate: rate,
                    halfDayRate: halfDayRate,
                    fullDays: fullDays,
                    halfDays: halfDays,
                  );
                  grandTotal += gross;
                  final advances = advancesByUid[uid] ?? 0.0;
                  final net = computeNetPay(gross: gross, advances: advances);
                  final paidAmount = paidWeeklyByUid[uid];
                  final isPaid = paidAmount != null;
                  return {
                    'uid': uid,
                    'label': label,
                    'fullDays': fullDays,
                    'halfDays': halfDays,
                    'rate': rate,
                    'halfDayRate': halfDayRate,
                    'gross': gross,
                    'advances': advances,
                    'net': net,
                    'isPaid': isPaid,
                  };
                }).toList();

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Weekly total',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _fmtMoney(grandTotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...rows.map((r) {
                      final uid = r['uid'] as String;
                      final label = r['label'] as String;
                      final fullDays = r['fullDays'] as int;
                      final halfDays = r['halfDays'] as int;
                      final halfDayRate = r['halfDayRate'] as double;
                      final gross = r['gross'] as double;
                      final advances = r['advances'] as double;
                      final net = r['net'] as double;
                      final isPaid = r['isPaid'] as bool;

                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          title: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Full: $fullDays · Half: $halfDays @ ₱${halfDayRate.toStringAsFixed(2)}/half-day\n'
                            'Gross: ${_fmtMoney(gross)} · Advances: ${_fmtMoney(advances)}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _fmtMoney(net),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: isPaid
                                    ? null
                                    : () async {
                                        final amountController =
                                            TextEditingController();
                                        final saved = await showDialog<bool>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: Text(
                                                  'Advance payout: $label'),
                                              content: TextField(
                                                controller: amountController,
                                                keyboardType:
                                                    TextInputType.number,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Amount (₱)',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(false),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(true),
                                                  child: const Text('Record'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        final amount =
                                            _StaffManagementScreenState
                                                ._asDouble(
                                          amountController.text,
                                          fallback: 0,
                                        );
                                        amountController.dispose();
                                        if (saved != true) return;
                                        if (amount <= 0) return;
                                        await widget.onRecordPayout(
                                          uid,
                                          label,
                                          amount,
                                          'advance',
                                        );
                                      },
                                child: const Text('Advance'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: isPaid || net <= 0
                                    ? null
                                    : () => widget.onRecordPayout(
                                        uid, label, net, 'weekly'),
                                child: Text(isPaid ? 'Paid' : 'Mark paid'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

