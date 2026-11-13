import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../../../widgets/dashboard/empty_state.dart';
import '../../../../widgets/dashboard/section_card.dart';
import '../../data/finance_format.dart';

/// Staff payroll overview. Uses memoized Firestore stream factories owned by
/// the parent screen so listeners survive tab switches.
class FinancePayrollTab extends StatelessWidget {
  const FinancePayrollTab({
    super.key,
    required this.eateryId,
    required this.fmt,
    required this.staffUsersStream,
    required this.staffProfilesStream,
    this.onNavigateToStaff,
  });

  final String? eateryId;
  final FinanceFormat fmt;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String)
      staffUsersStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String)
      staffProfilesStream;
  final VoidCallback? onNavigateToStaff;

  @override
  Widget build(BuildContext context) {
    final id = eateryId;
    if (id == null || id.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.pagePadding),
        child: EmptyState(
          icon: Icons.badge_outlined,
          title: 'Payroll not available',
          subtitle: 'Your eatery is not set up yet.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      children: [
        SectionCard(
          title: 'Staff Payroll',
          icon: Icons.groups_outlined,
          iconColor: const Color(0xFF6366F1),
          action: onNavigateToStaff == null
              ? null
              : TextButton.icon(
                  onPressed: onNavigateToStaff,
                  icon: const Icon(Icons.arrow_forward_ios, size: 12),
                  label: const Text('Manage'),
                ),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: staffUsersStream(id),
            builder: (context, usersSnap) {
              if (usersSnap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (usersSnap.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Failed to load staff',
                  subtitle: '${usersSnap.error}',
                  iconColor: AppTheme.error,
                );
              }

              final userDocs = usersSnap.data?.docs ?? const [];
              if (userDocs.isEmpty) {
                return const EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No staff registered yet',
                  subtitle: 'Add staff to view payroll rates.',
                );
              }

              final usersByUid = <String, Map<String, dynamic>>{
                for (final d in userDocs) d.id: d.data(),
              };

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: staffProfilesStream(id),
                builder: (context, profilesSnap) {
                  if (profilesSnap.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final profileByUid = <String, Map<String, dynamic>>{};
                  if (profilesSnap.hasData) {
                    for (final d in profilesSnap.data!.docs) {
                      final docUid = d.id.toString().trim();
                      if (docUid.isEmpty) continue;
                      profileByUid[docUid] = d.data();
                    }
                  }

                  final entries = usersByUid.entries.toList()
                    ..sort((a, b) {
                      final aName = _displayName(a.value, a.key);
                      final bName = _displayName(b.value, b.key);
                      return aName
                          .toLowerCase()
                          .compareTo(bName.toLowerCase());
                    });

                  return Column(
                    children: [
                      for (final entry in entries)
                        _PayrollRow(
                          uid: entry.key,
                          userData: entry.value,
                          profile: profileByUid[entry.key] ??
                              const <String, dynamic>{},
                          fmt: fmt,
                          onTap: onNavigateToStaff,
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _displayName(Map<String, dynamic> data, String uid) {
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final name = ('$first $last').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }
}

class _PayrollRow extends StatelessWidget {
  const _PayrollRow({
    required this.uid,
    required this.userData,
    required this.profile,
    required this.fmt,
    this.onTap,
  });

  final String uid;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> profile;
  final FinanceFormat fmt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = (userData['firstName'] ?? '').toString().trim();
    final last = (userData['lastName'] ?? '').toString().trim();
    final name = ('$first $last').trim();
    final display = name.isNotEmpty
        ? name
        : (userData['email'] ?? uid).toString();
    final email = (userData['email'] ?? '').toString();
    final position = (profile['position'] ?? '').toString().trim();
    final rate = profile['dailyRate'] is num
        ? (profile['dailyRate'] as num).toDouble()
        : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
              child: const Icon(
                Icons.badge_outlined,
                size: 18,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${email.isEmpty ? uid : email}'
                    '${position.isEmpty ? '' : ' • $position'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            rate > 0
                ? Text(
                    '${fmt.money(rate)}/day',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  )
                : Text(
                    'No rate',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
