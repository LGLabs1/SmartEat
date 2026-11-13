part of 'package:smarteat/screens/staff_management_screen.dart';

class _StaffTab extends StatefulWidget {
  const _StaffTab({
    required this.eateryId,
    required this.eateryName,
    required this.adminUid,
    required this.adminName,
    required this.usersByUid,
    required this.globalSearchQuery,
    required this.onEditProfile,
    required this.onApproveStaff,
    required this.onRemoveStaff,
  });

  final String eateryId;
  final String eateryName;
  final String adminUid;
  final String adminName;
  final Map<String, Map<String, dynamic>> usersByUid;
  final ValueNotifier<String>? globalSearchQuery;
  final Future<void> Function(String uid, Map<String, dynamic> userData)
      onEditProfile;
  final Future<void> Function(BuildContext context, String uid) onApproveStaff;
  final Future<void> Function(BuildContext context,
      {required String uid, required String label}) onRemoveStaff;

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  // Memoized per eatery so rebuilds reuse the same Firestore listener.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _profilesStream;
  String _profilesStreamKey = '';

  final TextEditingController _searchController = TextEditingController();
  String _localQuery = '';
  StaffDirectoryFilter _filter = StaffDirectoryFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_searchController.text == _localQuery) return;
    setState(() => _localQuery = _searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _profilesStreamFor(
      String eateryId) {
    if (_profilesStream == null || _profilesStreamKey != eateryId) {
      _profilesStreamKey = eateryId;
      _profilesStream = StaffService.staffProfilesStream(eateryId);
    }
    return _profilesStream!;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.globalSearchQuery;
    if (notifier == null) return _buildBody(context, _localQuery);
    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (context, query, _) {
        final effective =
            _localQuery.trim().isNotEmpty ? _localQuery : query;
        return _buildBody(context, effective);
      },
    );
  }

  Widget _buildBody(BuildContext context, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _profilesStreamFor(widget.eateryId),
      builder: (context, profilesSnap) {
        if (profilesSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load staff profiles: ${profilesSnap.error}',
              ),
            ),
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

        String profileStatusOf(String uid) =>
            (profileByUid[uid]?['status'] ?? 'active').toString().trim();

        final staffEntries = widget.usersByUid.entries
            .where((e) => !isAdminUser(e.value))
            .toList();

        final pending = staffEntries
            .where((e) => isPendingStaff(e.value))
            .toList()
          ..sort((a, b) => staffDisplayName(a.value, a.key)
              .toLowerCase()
              .compareTo(staffDisplayName(b.value, b.key).toLowerCase()));

        final counts = <StaffDirectoryFilter, int>{
          StaffDirectoryFilter.all: staffEntries.length,
          StaffDirectoryFilter.active: 0,
          StaffDirectoryFilter.pending: 0,
          StaffDirectoryFilter.inactive: 0,
        };
        for (final e in staffEntries) {
          final bucket = staffFilterFor(
            data: e.value,
            profileStatus: profileStatusOf(e.key),
          );
          counts[bucket] = (counts[bucket] ?? 0) + 1;
        }

        final entries = staffEntries.where((e) {
          final data = e.value;
          final p = profileByUid[e.key] ?? const <String, dynamic>{};
          final status = profileStatusOf(e.key);
          if (!staffMatchesFilter(
            data: data,
            profileStatus: status,
            filter: _filter,
          )) {
            return false;
          }
          final profilePosition = (p['position'] ?? '').toString().trim();
          final position = profilePosition.isNotEmpty
              ? profilePosition
              : (data['position'] ?? '').toString().trim();
          return staffMatchesQuery(
            data: data,
            uid: e.key,
            query: query,
            position: position,
          );
        }).toList()
          ..sort((a, b) => staffDisplayName(a.value, a.key)
              .toLowerCase()
              .compareTo(staffDisplayName(b.value, b.key).toLowerCase()));

        final isFiltering =
            query.isNotEmpty || _filter != StaffDirectoryFilter.all;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _StaffInviteCard(
              eateryId: widget.eateryId,
              eateryName: widget.eateryName,
            ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 8),
              PendingApprovalsCard(
                pending: [
                  for (final e in pending)
                    PendingStaffEntry(
                      uid: e.key,
                      name: staffDisplayName(e.value, e.key),
                      email: (e.value['email'] ?? '').toString(),
                      phone: staffPhone(e.value),
                    ),
                ],
                onApprove: (uid) => widget.onApproveStaff(context, uid),
                onReject: (uid, name) => widget.onRemoveStaff(
                  context,
                  uid: uid,
                  label: name,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _StaffSearchField(
              controller: _searchController,
              onClear: () => _searchController.clear(),
            ),
            const SizedBox(height: 8),
            _StaffFilterBar(
              filter: _filter,
              counts: counts,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              _StaffEmptyState(isFiltering: isFiltering)
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StaffDirectoryCard(
                    uid: entry.key,
                    data: entry.value,
                    profile: profileByUid[entry.key] ??
                        const <String, dynamic>{},
                    onTap: () => widget.onEditProfile(entry.key, entry.value),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _StaffInviteCard extends StatelessWidget {
  const _StaffInviteCard({required this.eateryId, required this.eateryName});

  final String eateryId;
  final String eateryName;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: eateryId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eatery code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_add_alt_1, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Invite staff',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Share this code so new staff can join '
              '${eateryName.isEmpty ? 'your eatery' : eateryName}.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      eateryId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy eatery code',
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffSearchField extends StatelessWidget {
  const _StaffSearchField({required this.controller, required this.onClear});

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search by name, email, phone, or position',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _StaffFilterBar extends StatelessWidget {
  const _StaffFilterBar({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final StaffDirectoryFilter filter;
  final Map<StaffDirectoryFilter, int> counts;
  final ValueChanged<StaffDirectoryFilter> onChanged;

  static const _labels = <StaffDirectoryFilter, String>{
    StaffDirectoryFilter.all: 'All',
    StaffDirectoryFilter.active: 'Active',
    StaffDirectoryFilter.pending: 'Pending',
    StaffDirectoryFilter.inactive: 'Inactive',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final entry in _labels.entries)
          ChoiceChip(
            label: Text('${entry.value} (${counts[entry.key] ?? 0})'),
            selected: filter == entry.key,
            onSelected: (_) => onChanged(entry.key),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _StaffDirectoryCard extends StatelessWidget {
  const _StaffDirectoryCard({
    required this.uid,
    required this.data,
    required this.profile,
    required this.onTap,
  });

  final String uid;
  final Map<String, dynamic> data;
  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = staffDisplayName(data, uid);
    final email = (data['email'] ?? '').toString().trim();
    final phone = staffPhone(data);
    final profilePosition = (profile['position'] ?? '').toString().trim();
    final position = profilePosition.isNotEmpty
        ? profilePosition
        : (data['position'] ?? '').toString().trim();
    final status = (profile['status'] ?? 'active').toString().trim();
    final bucket = staffFilterFor(data: data, profileStatus: status);
    final dailyRate = profile['dailyRate'];
    final rate = dailyRate is num ? dailyRate.toDouble() : 0.0;

    final details = <String>[
      if (position.isNotEmpty) position,
      if (phone.isNotEmpty) phone,
      if (rate > 0) '₱${rate.toStringAsFixed(2)}/day',
    ];

    final colors = _statusColors(bucket);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: colors.$1,
          child: Text(
            staffInitials(name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _StaffStatusChip(bucket: bucket),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email.isEmpty ? uid : email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (details.isNotEmpty)
                Text(
                  details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 20),
      ),
    );
  }
}

class _StaffStatusChip extends StatelessWidget {
  const _StaffStatusChip({required this.bucket});

  final StaffDirectoryFilter bucket;

  @override
  Widget build(BuildContext context) {
    final label = switch (bucket) {
      StaffDirectoryFilter.active => 'Active',
      StaffDirectoryFilter.pending => 'Pending',
      StaffDirectoryFilter.inactive => 'Inactive',
      StaffDirectoryFilter.all => 'All',
    };
    final colors = _statusColors(bucket);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.$1,
        ),
      ),
    );
  }
}

class _StaffEmptyState extends StatelessWidget {
  const _StaffEmptyState({required this.isFiltering});

  final bool isFiltering;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            isFiltering
                ? 'No staff match your search or filter.'
                : 'No staff yet. Share the invite code above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

(Color, Color) _statusColors(StaffDirectoryFilter bucket) {
  return switch (bucket) {
    StaffDirectoryFilter.active => (Colors.green.shade800, Colors.green.shade50),
    StaffDirectoryFilter.pending => (Colors.orange.shade800, Colors.orange.shade50),
    StaffDirectoryFilter.inactive => (Colors.blueGrey.shade700, Colors.blueGrey.shade50),
    StaffDirectoryFilter.all => (Colors.blueGrey.shade700, Colors.blueGrey.shade50),
  };
}
