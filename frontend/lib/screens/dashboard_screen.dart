import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import 'pos_screen.dart';
import 'analytics_screen.dart';
import 'menu_screen.dart';
import 'inventory_screen.dart';
import 'login_screen.dart';
import 'staff_management_screen.dart';
import 'recipe_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class StaffHomeTab extends StatefulWidget {
  const StaffHomeTab({Key? key, required this.onNavigate}) : super(key: key);

  final ValueChanged<int> onNavigate;

  @override
  State<StaffHomeTab> createState() => _StaffHomeTabState();
}

class _StaffHomeTabState extends State<StaffHomeTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _todayOrders = const [];
  String _eateryName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryName = (profile?['eateryName'] ?? '').toString().trim();

      final res = await ApiService.getTodayOrders();
      final orders = List<Map<String, dynamic>>.from(res['data'] ?? const []);
      if (!mounted) return;
      setState(() {
        _todayOrders = orders;
        _eateryName = eateryName;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load: $_error'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Today',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _eateryName.isEmpty
                          ? 'Quick access for staff'
                          : _eateryName,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _ActionChip(
                              icon: Icons.shopping_cart,
                              label: 'Open POS',
                              onTap: () => widget.onNavigate(1),
                            ),
                            _ActionChip(
                              icon: Icons.restaurant_menu,
                              label: 'View Menu',
                              onTap: () => widget.onNavigate(2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Today\'s Orders',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (_todayOrders.isEmpty)
                              Text(
                                'No orders yet today.',
                                style: TextStyle(color: Colors.grey.shade700),
                              )
                            else
                              ..._todayOrders.take(8).map((order) {
                                final id = (order['id'] ?? '').toString();
                                final total = (order['totalAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final status =
                                    (order['status'] ?? '').toString().trim();
                                final statusKey = status.toLowerCase();
                                final itemsRaw = order['items'];
                                final items =
                                    itemsRaw is List ? itemsRaw : const [];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      const Icon(Icons.receipt_long_outlined),
                                  title: Text(
                                    id.isEmpty
                                        ? 'Order'
                                        : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle:
                                      status.isEmpty ? null : Text(status),
                                  trailing:
                                      Text('₱${total.toStringAsFixed(2)}'),
                                  onTap: id.isEmpty
                                      ? null
                                      : () async {
                                          await showDialog<void>(
                                            context: context,
                                            builder: (context) {
                                              int asInt(dynamic v) {
                                                if (v is int) return v;
                                                if (v is num) return v.toInt();
                                                return int.tryParse(
                                                        (v ?? '').toString()) ??
                                                    0;
                                              }

                                              double asDouble(dynamic v) {
                                                if (v is num)
                                                  return v.toDouble();
                                                return double.tryParse(
                                                        (v ?? '').toString()) ??
                                                    0.0;
                                              }

                                              final lastAddedRaw =
                                                  order['lastAddedItems'];
                                              final lastAdded =
                                                  lastAddedRaw is List
                                                      ? lastAddedRaw
                                                      : const [];

                                              return AlertDialog(
                                                title: Text(
                                                  'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                                                ),
                                                content: SizedBox(
                                                  width: 520,
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (status.isNotEmpty)
                                                          Text(
                                                            'Status: $status',
                                                            style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700),
                                                          ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                            'Total: ₱${total.toStringAsFixed(2)}'),
                                                        const SizedBox(
                                                            height: 12),
                                                        const Divider(),
                                                        const SizedBox(
                                                            height: 8),
                                                        const Text(
                                                          'Items',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800),
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        if (items.isEmpty)
                                                          Text(
                                                            'No items',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey
                                                                    .shade700),
                                                          )
                                                        else
                                                          ...items.map((raw) {
                                                            final it =
                                                                raw is Map
                                                                    ? raw
                                                                    : const {};
                                                            final name =
                                                                (it['name'] ??
                                                                        '')
                                                                    .toString();
                                                            final qty = asInt(
                                                                it['quantity']);
                                                            final price =
                                                                asDouble(it[
                                                                    'price']);
                                                            final lineTotal =
                                                                price * qty;
                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          8),
                                                              child: Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      name.isEmpty
                                                                          ? 'Item'
                                                                          : name,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Text('x$qty'),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  Text(
                                                                      '₱${lineTotal.toStringAsFixed(2)}'),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                        if (lastAdded
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                              height: 12),
                                                          const Divider(),
                                                          const SizedBox(
                                                              height: 8),
                                                          const Text(
                                                            'Newly added items',
                                                            style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          ...lastAdded
                                                              .map((raw) {
                                                            final it =
                                                                raw is Map
                                                                    ? raw
                                                                    : const {};
                                                            final name =
                                                                (it['name'] ??
                                                                        '')
                                                                    .toString();
                                                            final qty = asInt(
                                                                it['quantity']);
                                                            final price =
                                                                asDouble(it[
                                                                    'price']);
                                                            final lineTotal =
                                                                price * qty;
                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          8),
                                                              child: Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      name.isEmpty
                                                                          ? 'Item'
                                                                          : name,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Text('x$qty'),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  Text(
                                                                    '₱${lineTotal.toStringAsFixed(2)}',
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(context)
                                                            .pop(),
                                                    child: const Text('Close'),
                                                  ),
                                                  FilledButton(
                                                    onPressed:
                                                        statusKey == 'pending'
                                                            ? () {
                                                                Navigator.of(
                                                                        context)
                                                                    .pop();
                                                                Navigator.of(
                                                                        context)
                                                                    .push(
                                                                  MaterialPageRoute(
                                                                    builder: (_) =>
                                                                        POSScreen(
                                                                      initialAddToExistingOrder:
                                                                          true,
                                                                      initialOrderId:
                                                                          id,
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            : null,
                                                    child:
                                                        const Text('Add Items'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _isRoleLoading = true;
  String? _roleError;
  bool _isAdmin = false;
  bool _isApprovedStaff = true;
  bool _isApprovalRefreshing = false;
  bool _adminViewEnabled = true;
  String _eateryName = '';
  String _eateryId = '';
  String _displayName = '';
  String? _lastLoadedUid;
  final ValueNotifier<String> _globalSearchQuery = ValueNotifier<String>('');
  final TextEditingController _globalSearchController = TextEditingController();

  bool get _isAdminRole {
    return _isAdmin && _adminViewEnabled;
  }

  bool get _canSwitchDashboard {
    return _isAdmin;
  }

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _globalSearchController.dispose();
    _globalSearchQuery.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid != null && uid.isNotEmpty && uid != _lastLoadedUid) {
      _lastLoadedUid = uid;
      _loadRole();
    }
  }

  Future<void> _loadRole({bool setLoadingState = true}) async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      if (setLoadingState) {
        setState(() {
          _isRoleLoading = false;
          _roleError = 'Not signed in.';
        });
      }
      return;
    }

    if (setLoadingState) {
      setState(() {
        _isRoleLoading = true;
        _roleError = null;
      });
    }

    try {
      final profile = await context
          .read<AuthProvider>()
          .getCurrentUserProfile()
          .timeout(const Duration(seconds: 12));
      if (profile == null) {
        throw Exception('Profile not found');
      }
      final role = (profile['role'] ?? '').toString().trim().toLowerCase();
      final dynamic isAdminRaw = profile['isAdmin'];
      final bool isAdminFlag = isAdminRaw == true ||
          isAdminRaw == 1 ||
          (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
      final isAdmin = isAdminFlag || role == 'admin';

      final dynamic approvedRaw = profile['approved'];
      final bool approved = approvedRaw == null ? true : approvedRaw == true;
      final eateryName = (profile['eateryName'] ?? '').toString().trim();
      final eateryId = (profile['eateryId'] ?? '').toString().trim();
      final firstName = (profile['firstName'] ?? '').toString().trim();
      final lastName = (profile['lastName'] ?? '').toString().trim();
      final displayName = ('$firstName $lastName').trim();
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _isApprovedStaff = approved;
        _eateryName = eateryName;
        _eateryId = eateryId;
        _displayName = displayName;
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roleError =
            'Failed to load profile. Please check your connection and Firestore rules.\n\n$e';
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
    }
  }

  Future<void> _refreshApprovalStatus() async {
    setState(() {
      _isApprovalRefreshing = true;
      _roleError = null;
    });
    try {
      await _loadRole(setLoadingState: false);
    } finally {
      if (!mounted) return;
      setState(() {
        _isApprovalRefreshing = false;
      });
    }
  }

  void _goToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  void _setAdminViewEnabled(bool enabled) {
    setState(() {
      _adminViewEnabled = enabled;
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isRoleLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_roleError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Smart Eat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to load profile: $_roleError',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadRole,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isAdmin && !_isApprovedStaff) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Smart Eat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'Your account is pending admin approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask your admin to approve your account. Once approved, tap Refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isApprovalRefreshing ? null : _refreshApprovalStatus,
                      child: _isApprovalRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Refresh'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => context.read<AuthProvider>().logout(),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tabs = _isAdminRole
        ? <Widget>[
            DashboardHomeTab(onNavigate: _goToTab),
            MenuScreen(globalSearchQuery: _globalSearchQuery),
            InventoryScreen(globalSearchQuery: _globalSearchQuery),
            const AnalyticsScreen(),
            RecipeScreen(globalSearchQuery: _globalSearchQuery),
            StaffManagementScreen(globalSearchQuery: _globalSearchQuery),
          ]
        : <Widget>[
            StaffHomeTab(onNavigate: _goToTab),
            const POSScreen(showAppBar: false),
            MenuScreen(globalSearchQuery: _globalSearchQuery),
          ];

    final items = _isAdminRole
        ? const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu),
              label: 'Menu',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory),
              label: 'Inventory',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Recipes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.group_outlined),
              label: 'Staff',
            ),
          ]
        : const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart),
              label: 'POS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu),
              label: 'Menu',
            ),
          ];

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    final email = context.read<AuthProvider>().user?.email ?? '';
    final roleLabel = _isAdmin ? 'Admin' : 'Staff';

    final isNarrowSearch = MediaQuery.of(context).size.width < 520;
    final searchHint = isNarrowSearch ? '' : 'Search';

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.2),
                      child: Icon(
                        Icons.person_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName.isNotEmpty
                                ? _displayName
                                : (email.isNotEmpty ? email : 'Account'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (_eateryName.isNotEmpty)
                            Text(
                              _eateryName,
                              style: TextStyle(color: Colors.grey.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (_isAdmin && _eateryId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Eatery ID: $_eateryId',
                                    style:
                                        TextStyle(color: Colors.grey.shade700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _eateryId),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Eatery ID copied'),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          if (_eateryName.isEmpty && email.isNotEmpty)
                            Text(
                              email,
                              style: TextStyle(color: Colors.grey.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dashboard_outlined),
                      title: const Text('Home'),
                      selected: _selectedIndex == 0,
                      onTap: () {
                        Navigator.of(context).pop();
                        _goToTab(0);
                      },
                    ),
                    if (_canSwitchDashboard)
                      ListTile(
                        leading: Icon(
                          _adminViewEnabled
                              ? Icons.swap_horiz
                              : Icons.admin_panel_settings_outlined,
                        ),
                        title: Text(
                          _adminViewEnabled
                              ? 'Switch to Main Dashboard'
                              : 'Switch to Admin Dashboard',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _setAdminViewEnabled(!_adminViewEnabled);
                        },
                      ),
                    const Divider(height: 24),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const _SimplePlaceholderScreen(
                                    title: 'Settings'),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const _SimplePlaceholderScreen(
                              title: 'Notifications',
                            ),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Profile'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const _SimplePlaceholderScreen(
                                    title: 'Profile'),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const _SimplePlaceholderScreen(title: 'About'),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 24),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Logout'),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.read<AuthProvider>().logout();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final maxSearchWidth = constraints.maxWidth >= 900
                ? 420.0
                : constraints.maxWidth >= 600
                    ? 320.0
                    : 200.0;
            final isNarrow = constraints.maxWidth < 520;

            Widget searchField(double maxWidth) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _globalSearchController,
                    onChanged: (v) => _globalSearchQuery.value = v,
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      suffixIcon: ValueListenableBuilder<String>(
                        valueListenable: _globalSearchQuery,
                        builder: (context, value, _) {
                          if (value.trim().isEmpty) return const SizedBox();
                          return IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _globalSearchController.clear();
                              _globalSearchQuery.value = '';
                            },
                            icon: const Icon(Icons.close, color: Colors.white),
                          );
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.18),
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            }

            final titleBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _eateryName.isEmpty ? 'Smart Eat' : _eateryName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_eateryName.isNotEmpty)
                  Text(
                    'Smart Eat',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            );

            if (isNarrow) {
              final compactTitle = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _eateryName.isEmpty ? 'Smart Eat' : _eateryName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_eateryName.isNotEmpty)
                    Text(
                      'Smart Eat',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              );

              final narrowSearchWidth = constraints.maxWidth >= 420
                  ? 180.0
                  : constraints.maxWidth >= 380
                      ? 160.0
                      : 140.0;

              return Row(
                children: [
                  Expanded(child: compactTitle),
                  const SizedBox(width: 10),
                  searchField(narrowSearchWidth),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: 12),
                searchField(maxSearchWidth),
              ],
            );
          },
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withBlue(
                      (Theme.of(context).colorScheme.primary.blue + 40)
                          .clamp(0, 255),
                    ),
              ],
            ),
          ),
        ),
        elevation: 2,
        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        actions: [
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: items,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class DashboardHomeTab extends StatefulWidget {
  const DashboardHomeTab({Key? key, required this.onNavigate})
      : super(key: key);

  final ValueChanged<int> onNavigate;

  @override
  State<DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _SimplePlaceholderScreen extends StatelessWidget {
  const _SimplePlaceholderScreen({Key? key, required this.title})
      : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _DashboardHomeTabState extends State<DashboardHomeTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _todayOrders = const [];
  List<Map<String, dynamic>> _lowStock = const [];
  String _eateryName = '';
  String _completingOrderId = '';
  bool _isAdmin = false;

  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryName = (profile?['eateryName'] ?? '').toString().trim();
      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      final dynamic isAdminRaw = profile?['isAdmin'];
      final bool isAdminFlag = isAdminRaw == true ||
          isAdminRaw == 1 ||
          (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
      final isAdmin = isAdminFlag || role == 'admin';

      final results = await Future.wait([
        ApiService.getSummaryStats(),
        ApiService.getTodayOrders(),
        ApiService.getLowStockItems(),
      ]);

      final summary = results[0]['data'] as Map<String, dynamic>?;
      final orders =
          List<Map<String, dynamic>>.from(results[1]['data'] ?? const []);
      final lowStock =
          List<Map<String, dynamic>>.from(results[2]['data'] ?? const []);

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _todayOrders = orders;
        _lowStock = lowStock;
        _eateryName = eateryName;
        _isAdmin = isAdmin;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _completeOrder(String orderId) async {
    if (orderId.isEmpty) return;
    setState(() => _completingOrderId = orderId);
    try {
      await ApiService.completeOrder(orderId);
      if (!mounted) return;
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order completed. Stocks updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      String message;
      if (e is FirebaseException) {
        final code = (e.code).toString();
        final details = (e.message ?? '').toString();
        message = details.trim().isEmpty
            ? 'Firebase error: $code'
            : 'Firebase error: $code — $details';
      } else {
        // Aggressive Flutter web error extraction
        dynamic current = e;
        String? bestMessage;
        for (int i = 0; i < 5; i++) {
          if (current is FirebaseException) {
            final code = (current.code).toString();
            final details = (current.message ?? '').toString();
            bestMessage = details.trim().isEmpty
                ? 'Firebase error: $code'
                : 'Firebase error: $code — $details';
            break;
          }
          try {
            // Try various properties that might contain the real error
            final next = current.error;
            final msg = current.message ??
                current.details ??
                current.code ??
                current.description;
            if (msg != null &&
                msg.toString().isNotEmpty &&
                !msg
                    .toString()
                    .contains('Dart exception thrown from converted Future')) {
              bestMessage = msg.toString();
            }
            if (next == null || next == current) break;
            current = next;
          } catch (_) {
            break;
          }
        }
        message = bestMessage ?? current.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete order: $message')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _completingOrderId = '');
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    if (!_isAdmin) return;

    String formatTimestamp(dynamic value) {
      if (value == null) return '';
      if (value is Timestamp) {
        final d = value.toDate();
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')} '
            '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
      }
      return value.toString();
    }

    final id = (order['id'] ?? '').toString();
    final status = (order['status'] ?? '').toString();
    final paymentMethod = (order['paymentMethod'] ?? '').toString();
    final notes = (order['notes'] ?? '').toString();
    final rejectReason = (order['rejectReason'] ?? '').toString();
    final voidReason = (order['voidReason'] ?? '').toString();
    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = formatTimestamp(order['createdAt']);
    final completedAt = formatTimestamp(order['completedAt']);
    final voidedAt = formatTimestamp(order['voidedAt']);

    final itemsRaw = order['items'];
    final items = itemsRaw is List ? itemsRaw : const [];

    final lastAddedRaw = order['lastAddedItems'];
    final lastAdded = lastAddedRaw is List ? lastAddedRaw : const [];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            id.isEmpty
                ? 'Order Details'
                : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Status: $status',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Total: ₱${total.toStringAsFixed(2)}'),
                  if (paymentMethod.trim().isNotEmpty)
                    Text('Payment: $paymentMethod'),
                  if (createdAt.isNotEmpty) Text('Created: $createdAt'),
                  if (completedAt.isNotEmpty) Text('Completed: $completedAt'),
                  if (notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Notes: $notes'),
                  ],
                  if (rejectReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Reject reason: $rejectReason',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (voidReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Void reason: $voidReason',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (voidedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Voided: $voidedAt'),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Text(
                      'No items',
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  else
                    ...items.map((raw) {
                      final it = raw is Map ? raw : const {};
                      final name = (it['name'] ?? '').toString();
                      final qtyRaw = it['quantity'];
                      final qty = qtyRaw is num
                          ? qtyRaw.toInt()
                          : int.tryParse(qtyRaw?.toString() ?? '') ?? 0;
                      final priceRaw = it['price'];
                      final price = priceRaw is num
                          ? priceRaw.toDouble()
                          : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;
                      final lineTotal = price * qty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name.isEmpty ? 'Item' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('x$qty'),
                            const SizedBox(width: 12),
                            Text('₱${lineTotal.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    }),
                  if (lastAdded.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Newly added items',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ...lastAdded.map((raw) {
                      final it = raw is Map ? raw : const {};
                      final name = (it['name'] ?? '').toString();
                      final qtyRaw = it['quantity'];
                      final qty = qtyRaw is num
                          ? qtyRaw.toInt()
                          : int.tryParse(qtyRaw?.toString() ?? '') ?? 0;
                      final priceRaw = it['price'];
                      final price = priceRaw is num
                          ? priceRaw.toDouble()
                          : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;
                      final lineTotal = price * qty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name.isEmpty ? 'Item' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('x$qty'),
                            const SizedBox(width: 12),
                            Text('₱${lineTotal.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (status.trim().toLowerCase() == 'pending')
              TextButton(
                onPressed: () async {
                  final controller = TextEditingController();
                  try {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Void Order'),
                          content: SizedBox(
                            width: 520,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'This will mark the order as voided. Stocks will not be updated.',
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Reason (optional)',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Void'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmed != true) return;
                    await ApiService.voidOrder(id, reason: controller.text);
                    if (!mounted) return;
                    await _loadDashboard();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Order voided.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to void order: $e')),
                    );
                  } finally {
                    controller.dispose();
                  }
                },
                child: const Text(
                  'Void',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (status.trim().toLowerCase() == 'rejected')
              TextButton(
                onPressed: () async {
                  try {
                    await ApiService.restoreOrderToPending(id);
                    if (!mounted) return;
                    await _loadDashboard();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Order restored to pending.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to restore order: $e')),
                    );
                  }
                },
                child: const Text('Restore to pending'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Failed to load dashboard: $_error',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadDashboard,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildKpis(context),
                    const SizedBox(height: 16),
                    _buildQuickActions(context),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildLowStock(context)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildTodayOrders(context)),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            _buildLowStock(context),
                            const SizedBox(height: 16),
                            _buildTodayOrders(context),
                          ],
                        );
                      },
                    ),
                  ],
                ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final userEmail = context.read<AuthProvider>().user?.email ?? '';
    final subtitle = _eateryName.isNotEmpty
        ? _eateryName
        : (userEmail.isEmpty ? 'Welcome back' : 'Welcome back, $userEmail');
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.dashboard_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dashboard',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpis(BuildContext context) {
    final today = (_summary?['today'] as Map<String, dynamic>?) ?? const {};
    final orders = (today['orders'] as num?)?.toInt() ?? 0;
    final revenue = (today['revenue'] as num?)?.toDouble() ?? 0.0;
    final menuItems = (_summary?['menuItems'] as num?)?.toInt() ?? 0;
    final lowStockCount = _lowStock.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100
            ? 4
            : width >= 760
                ? 3
                : 2;

        final isPhoneNarrow = width < 420;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 2
                ? (isPhoneNarrow ? 1.35 : 1.55)
                : crossAxisCount == 3
                    ? 2.0
                    : 2.2,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            switch (index) {
              case 0:
                return _KpiCard(
                  title: 'Today\'s Sales',
                  value: '₱${revenue.toStringAsFixed(2)}',
                  icon: Icons.payments_outlined,
                  color: Colors.blue,
                );
              case 1:
                return _KpiCard(
                  title: 'Orders Today',
                  value: orders.toString(),
                  icon: Icons.receipt_long_outlined,
                  color: Colors.indigo,
                );
              case 2:
                return _KpiCard(
                  title: 'Menu Items',
                  value: menuItems.toString(),
                  icon: Icons.restaurant_menu,
                  color: Colors.teal,
                );
              default:
                return _KpiCard(
                  title: 'Low Stock',
                  value: lowStockCount.toString(),
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                );
            }
          },
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Management',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isWide = width >= 720;

                final primary = FilledButton.icon(
                  onPressed: () => widget.onNavigate(1),
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Menu Management'),
                );

                final secondary = Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(2),
                      icon: const Icon(Icons.inventory),
                      label: const Text('Inventory'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(3),
                      icon: const Icon(Icons.analytics),
                      label: const Text('Analytics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(4),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Recipes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(5),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Staff'),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primary),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: secondary),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: primary),
                    const SizedBox(height: 12),
                    secondary,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStock(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange),
                      const SizedBox(width: 8),
                      const Text(
                        'Low Stock',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _lowStock.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onNavigate(2),
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_lowStock.isEmpty)
              Text(
                'All good — no low stock items.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ..._lowStock.take(5).map((item) {
                final name = (item['name'] ?? 'Unknown').toString();
                final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
                final min = (item['minStock'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Current: ${current.toStringAsFixed(1)}  •  Min: ${min.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayOrders(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Colors.indigo),
                      const SizedBox(width: 8),
                      const Text(
                        'Today\'s Orders',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _todayOrders.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_todayOrders.isEmpty)
              Text(
                'No orders yet today.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ..._todayOrders.take(5).map((order) {
                final id = (order['id'] ?? '').toString();
                final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final status = (order['status'] ?? 'unknown').toString();
                final statusKey = status.trim().toLowerCase();
                final canComplete = _isAdmin && statusKey == 'pending';
                final isCompleting = _completingOrderId == id;
                final isNarrow = MediaQuery.of(context).size.width < 420;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 10,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    id.isEmpty
                        ? 'Order'
                        : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(status),
                  onTap: _isAdmin ? () => _showOrderDetails(order) : null,
                  trailing: canComplete
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isNarrow ? 88 : 140,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('₱${total.toStringAsFixed(2)}'),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 28,
                                child: isNarrow
                                    ? IconButton(
                                        tooltip: 'Complete',
                                        onPressed: isCompleting
                                            ? null
                                            : () => _completeOrder(id),
                                        icon: isCompleting
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.check_circle),
                                      )
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: SizedBox(
                                          height: 28,
                                          child: ElevatedButton(
                                            onPressed: isCompleting
                                                ? null
                                                : () => _completeOrder(id),
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            child: isCompleting
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Text(
                                                    'Complete',
                                                    style:
                                                        TextStyle(fontSize: 12),
                                                  ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        )
                      : Text('₱${total.toStringAsFixed(2)}'),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isPhoneNarrow = MediaQuery.of(context).size.width < 420;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isPhoneNarrow ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: isPhoneNarrow ? 36 : 40,
              height: isPhoneNarrow ? 36 : 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: isPhoneNarrow ? 20 : 24,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isPhoneNarrow ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: isPhoneNarrow ? 12 : 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
