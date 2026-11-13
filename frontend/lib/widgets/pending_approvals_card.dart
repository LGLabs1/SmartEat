import 'package:flutter/material.dart';

/// A staff member awaiting approval.
class PendingStaffEntry {
  const PendingStaffEntry({
    required this.uid,
    required this.name,
    this.email = '',
    this.phone = '',
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
}

/// Amber banner listing newly registered staff that still need approval.
///
/// Rendered at the top of the Staff tab. Returns an empty box when there is
/// nothing pending, so callers can include it unconditionally.
class PendingApprovalsCard extends StatelessWidget {
  const PendingApprovalsCard({
    super.key,
    required this.pending,
    required this.onApprove,
    required this.onReject,
  });

  final List<PendingStaffEntry> pending;
  final Future<void> Function(String uid) onApprove;
  final Future<void> Function(String uid, String name) onReject;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: Colors.amber.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  'Pending approvals (${pending.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'These people joined with your eatery code and need your approval.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final entry in pending) ...[
              _PendingRow(
                entry: entry,
                onApprove: () => onApprove(entry.uid),
                onReject: () => onReject(entry.uid, entry.name),
              ),
              if (entry != pending.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.entry,
    required this.onApprove,
    required this.onReject,
  });

  final PendingStaffEntry entry;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (entry.email.isNotEmpty) entry.email,
      if (entry.phone.isNotEmpty) entry.phone,
    ].join(' · ');

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.amber.shade200,
          child: Icon(Icons.person_outline, color: Colors.amber.shade900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: onApprove,
          child: const Text('Approve'),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onReject,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
