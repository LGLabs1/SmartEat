import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/ai_assistant_provider.dart';
import '../services/analytics_service.dart';
import '../services/firebase_service.dart';
import '../services/notification_trigger_manager.dart';

import '../features/finance/data/business_kpis.dart';
import '../features/finance/data/finance_format.dart';
import '../features/finance/data/finance_metrics.dart';
import '../features/staff/data/staff_service.dart';
import '../features/staff/presentation/screens/my_payroll_screen.dart';
import '../utils/staff_utils.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/dashboard/section_card.dart';
import '../widgets/dashboard/kpi_card.dart';
import '../widgets/dashboard/empty_state.dart';
import '../widgets/dashboard/revenue_trend_chart.dart';
import 'pos_screen.dart';
import 'orders_screen.dart';
import 'analytics_screen.dart';
import 'menu_screen.dart';
import 'inventory_screen.dart';
import 'staff_management_screen.dart';
import 'finance_screen.dart';
import 'admin_tab_index.dart';
// chatbot_screen.dart is intentionally not imported: the header button that
// opened ChatbotScreen was removed. Re-add the import when it is re-wired.

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Tab layout. Both dashboards render an Orders tab, so the two orderings are
  // spelled out here rather than sprinkled as bare literals — inserting or
  // reordering a tab is a one-line change instead of a sweep.
  static const int _adminTabCount = 7;
  static const int _staffTabCount = 3;

  // Admin: Home, Menu, Orders, Inventory, Analytics, Finance, Staff
  static const int _adminHomeTab = AdminTabIndex.home;
  static const int _adminMenuTab = AdminTabIndex.menu;
  static const int _adminOrdersTab = AdminTabIndex.orders;
  static const int _adminInventoryTab = AdminTabIndex.inventory;
  static const int _adminAnalyticsTab = AdminTabIndex.analytics;
  static const int _adminFinanceTab = AdminTabIndex.finance;
  static const int _adminStaffTab = AdminTabIndex.staff;

  // Staff: POS, Orders, Menu
  static const int _staffPosTab = 0;
  static const int _staffOrdersTab = 1;
  static const int _staffMenuTab = 2;

  // The remembered tab is scoped per dashboard. A single shared key let one
  // role's index leak into the other's layout, where it silently fell out of
  // range and reset to 0.
  static const String _adminSelectedIndexKey = 'dashboard_selected_index_admin';
  static const String _staffSelectedIndexKey = 'dashboard_selected_index_staff';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  // Lazy tab mounting. A tab's State is only created once the tab is first
  // visited, instead of the IndexedStack eagerly building all of them. Returning
  // to a tab whose data is older than [_tabStaleAfter] bumps its generation,
  // which changes its key and forces a fresh State (and reload). Kept at 5
  // minutes to limit Firestore reads against the free-tier daily quota; users
  // can still force a refresh with pull-to-refresh.
  static const Duration _tabStaleAfter = Duration(minutes: 5);
  final Set<int> _visitedTabs = <int>{0};
  final Map<int, DateTime> _tabLoadedAt = <int, DateTime>{
    0: DateTime.now(),
  };
  final Map<int, int> _tabGenerations = <int, int>{};
  bool _isRoleLoading = true;
  String? _roleError;
  bool _isAdmin = false;
  bool _isApprovedStaff = true;
  bool _isApprovalRefreshing = false;
  bool _adminViewEnabled = true;
  bool _inventoryInDetailView = false;
  final GlobalKey<InventoryScreenState> _inventoryKey =
      GlobalKey<InventoryScreenState>();
  String _eateryName = '';
  String _eateryId = '';
  String _displayName = '';
  String? _lastLoadedUid;
  final ValueNotifier<String> _globalSearchQuery = ValueNotifier<String>('');
  final TextEditingController _globalSearchController = TextEditingController();
  final NotificationTriggerManager _notificationTriggers =
      NotificationTriggerManager();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<String>? _aiNavigationSub;
  bool _sidebarVisible = true;
  bool _removalDialogShown = false;

  bool get _isAdminRole {
    return _isAdmin && _adminViewEnabled;
  }

  bool get _canSwitchDashboard {
    return _isAdmin;
  }

  /// Keeps the Sage overlay in sync with what is on screen. The assistant is
  /// only mounted for admins viewing the admin dashboard, so staff users (and
  /// admins who switched to the staff view) never see it. Role loading counts
  /// as restricted so nothing flashes before the role is known.
  void _syncAssistantAccess() {
    if (!mounted) return;
    final restricted = _isRoleLoading || !(_isAdmin && _adminViewEnabled);
    context.read<AIAssistantProvider>().setStaffDashboardActive(restricted);
  }

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
    _startUserDocListener();
    _notificationTriggers.startPeriodicChecks();
  }

  bool _sidebarInitialized = false;

  void _startUserDocListener() {
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.trim().isEmpty) return;

      _userDocSub?.cancel();
      _userDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((snap) async {
        if (!mounted) return;
        if (!snap.exists) return;

        final data = snap.data() ?? <String, dynamic>{};
        final removalMessage = (data['removalMessage'] ?? '').toString().trim();
        final removedAt = data['removedAt'];
        final removedFromEateryId =
            (data['removedFromEateryId'] ?? '').toString().trim();

        if (removalMessage.isEmpty) return;
        if (_removalDialogShown) return;

        _removalDialogShown = true;

        try {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return AlertDialog(
                title: const Text('Access Removed'),
                content: Text(removalMessage),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        } finally {
          if (!mounted) return;

          // Clear local role state to avoid any UI loops while logout happens.
          setState(() {
            _isRoleLoading = false;
            _roleError = null;
            _eateryId = '';
            _eateryName = '';
          });

          try {
            await context.read<AuthProvider>().logout();
          } catch (_) {}
        }

        // Best-effort cleanup of the message so the dialog doesn't keep re-appearing
        // when the user logs in again or when snapshot replays.
        try {
          if (removedFromEateryId.isNotEmpty || removedAt != null) {
            await FirebaseFirestore.instance.collection('users').doc(uid).set({
              'removalMessage': '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (_) {}
      });
    } catch (e) {}
  }

  Future<void> _initializeDashboard() async {
    await _loadRole();
    if (mounted) {
      // Defer restoring the remembered tab until after the first frame so the
      // shell (Home tab) paints immediately instead of blocking startup on a
      // heavy deep tab (finance, staff, …) building its data views.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSavedTabIndex();
      });
    }
  }

  /// Key holding the remembered tab for whichever dashboard is on screen.
  String get _selectedIndexKey =>
      _isAdminRole ? _adminSelectedIndexKey : _staffSelectedIndexKey;

  int get _tabCount => _isAdminRole ? _adminTabCount : _staffTabCount;

  Future<void> _loadSavedTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_selectedIndexKey);
      if (savedIndex != null && mounted) {
        // Wait for role to be loaded first, then validate the saved index
        // _isAdmin is set by _loadRole() which runs in initState
        if (savedIndex >= 0 && savedIndex < _tabCount) {
          setState(() {
            _selectedIndex = savedIndex;
            _visitedTabs.add(savedIndex);
            _tabLoadedAt[savedIndex] = DateTime.now();
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _saveTabIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_selectedIndexKey, index);
    } catch (e) {}
  }

  @override
  void dispose() {
    _notificationTriggers.dispose();
    _globalSearchController.dispose();
    _globalSearchQuery.dispose();
    _userDocSub?.cancel();
    _aiNavigationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize sidebar visibility based on screen width (only once)
    if (!_sidebarInitialized) {
      final screenWidth = MediaQuery.of(context).size.width;
      _sidebarVisible = screenWidth >= 768;
      _sidebarInitialized = true;
    }
    // Handle user auth changes
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) {
      // User logged out, stop loading
      if (_isRoleLoading) {
        setState(() => _isRoleLoading = false);
      }
      _syncAssistantAccess();
      return;
    }
    if (_aiNavigationSub == null) {
      _aiNavigationSub = context
          .read<AIAssistantProvider>()
          .navigationRequests
          .listen(_handleAIAssistantNavigation);
      context
          .read<AIAssistantProvider>()
          .setActivePage(_activePageNameForIndex(_selectedIndex));
    }
    if (uid != _lastLoadedUid) {
      _lastLoadedUid = uid;
      _loadRole();
    }
  }

  Future<void> _loadRole({bool setLoadingState = true}) async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      // Turn off loading; AuthGate handles routing to login.
      if (setLoadingState) {
        setState(() => _isRoleLoading = false);
      }
      return;
    }

    if (setLoadingState) {
      setState(() {
        _isRoleLoading = true;
        _roleError = null;
      });
      _syncAssistantAccess();
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
      final roleChanged = isAdmin != _isAdmin;
      setState(() {
        _isAdmin = isAdmin;
        _isApprovedStaff = approved;
        _eateryName = eateryName;
        _eateryId = eateryId;
        _displayName = displayName;
        if (roleChanged) {
          // Tab layout differs per role; drop all lazy-tab state so stale
          // indices never bleed across dashboards.
          _selectedIndex = 0;
          _visitedTabs
            ..clear()
            ..add(0);
          _tabLoadedAt
            ..clear()
            ..[0] = DateTime.now();
          _tabGenerations.clear();
        }
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
      _syncAssistantAccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roleError =
            'Failed to load profile. Please check your connection and Firestore rules.\n\n$e';
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
      _syncAssistantAccess();
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
    if (!mounted) return;
    // Prevent navigation while role is loading
    if (_isRoleLoading) {
      return;
    }
    try {
      // Validate index against available tabs
      if (index < 0 || index >= _tabCount) {
        return;
      }
      final now = DateTime.now();
      final firstVisit = !_visitedTabs.contains(index);
      final loadedAt = _tabLoadedAt[index];
      final isStale = !firstVisit &&
          loadedAt != null &&
          now.difference(loadedAt) > _tabStaleAfter;
      setState(() {
        _selectedIndex = index;
        _visitedTabs.add(index);
        if (firstVisit || isStale) {
          if (isStale) {
            _tabGenerations[index] = (_tabGenerations[index] ?? 0) + 1;
          }
          _tabLoadedAt[index] = now;
        }
      });
      _saveTabIndex(index);
      context
          .read<AIAssistantProvider>()
          .setActivePage(_activePageNameForIndex(index));
    } catch (e) {}
  }

  /// Builds a tab lazily. Unvisited, inactive tabs collapse to an inert
  /// placeholder so their State never mounts until first shown.
  Widget _lazyTab(int index, Widget Function(Key key) builder,
      {Key? fixedKey}) {
    final active = index == _selectedIndex;
    if (!active && !_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    final key =
        fixedKey ?? ValueKey('tab_$index#${_tabGenerations[index] ?? 0}');
    return builder(key);
  }

  void _setAdminViewEnabled(bool enabled) {
    if (!mounted) return;
    // Prevent view switch while role is loading
    if (_isRoleLoading) {
      return;
    }
    try {
      setState(() {
        _adminViewEnabled = enabled;
        _selectedIndex = 0;
        _visitedTabs
          ..clear()
          ..add(0);
        _tabLoadedAt
          ..clear()
          ..[0] = DateTime.now();
        _tabGenerations.clear();
      });
      _syncAssistantAccess();
      _saveTabIndex(0);
    } catch (e) {}
  }

  Future<void> _showGlobalSearchResults(String query) async {
    final results = await showDialog<List<_GlobalSearchResult>>(
      context: context,
      builder: (context) => _GlobalSearchDialog(query: query),
    );

    if (results != null && results.isNotEmpty) {
      final result = results.first;
      // Navigate based on result type
      switch (result.type) {
        case 'menu':
          _goToTab(_isAdminRole ? _adminMenuTab : _staffMenuTab);
          break;
        case 'inventory':
          if (_isAdminRole) {
            _goToTab(_adminInventoryTab);
          }
          break;
        case 'order':
          _goToTab(_isAdminRole ? _adminOrdersTab : _staffOrdersTab);
          break;
      }
    }
  }

  String _pageTitleForIndex(int index) {
    if (_isAdminRole) {
      switch (index) {
        case _adminHomeTab:
          return 'Home';
        case _adminMenuTab:
          return 'Menu';
        case _adminOrdersTab:
          return 'Orders';
        case _adminInventoryTab:
          return 'Inventory';
        case _adminAnalyticsTab:
          return 'Analytics Dashboard';
        case _adminFinanceTab:
          return 'Finance';
        case _adminStaffTab:
          return 'Staff';
        default:
          return 'Smart Eat';
      }
    }

    switch (index) {
      case _staffPosTab:
        return 'POS';
      case _staffOrdersTab:
        return 'Orders';
      case _staffMenuTab:
        return 'Menu';
      default:
        return 'Smart Eat';
    }
  }

  String _activePageNameForIndex(int index) {
    if (_isAdminRole) {
      switch (index) {
        case _adminHomeTab:
          return 'dashboard';
        case _adminMenuTab:
          return 'menu';
        case _adminOrdersTab:
          return 'orders';
        case _adminInventoryTab:
          return 'inventory';
        case _adminAnalyticsTab:
          return 'reports';
        case _adminFinanceTab:
          return 'finance';
        case _adminStaffTab:
          return 'staff';
        default:
          return 'general';
      }
    }

    switch (index) {
      case _staffPosTab:
        return 'orders';
      case _staffOrdersTab:
        return 'orders';
      case _staffMenuTab:
        return 'menu';
      default:
        return 'general';
    }
  }

  void _handleAIAssistantNavigation(String pageName) {
    final pageIndex = _indexForPageName(pageName);
    if (pageIndex != null) {
      _goToTab(pageIndex);
    }
  }

  int? _indexForPageName(String pageName) {
    if (_isAdminRole) {
      switch (pageName) {
        case 'dashboard':
          return _adminHomeTab;
        case 'menu':
          return _adminMenuTab;
        case 'orders':
          return _adminOrdersTab;
        case 'inventory':
          return _adminInventoryTab;
        case 'reports':
          return _adminAnalyticsTab;
        case 'finance':
          return _adminFinanceTab;
        case 'staff':
          return _adminStaffTab;
      }
    } else {
      // Staff has no dashboard tab any more, so 'dashboard' intentionally has
      // no mapping here — POS and Orders both report 'orders'.
      switch (pageName) {
        case 'orders':
          return _staffOrdersTab;
        case 'menu':
          return _staffMenuTab;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isRoleLoading) {
      return const SkeletonDashboard();
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

    final adminTabs = <Widget>[
      _lazyTab(
          _adminHomeTab, (k) => DashboardHomeTab(key: k, onNavigate: _goToTab)),
      _lazyTab(
          _adminMenuTab,
          (k) => MenuScreen(
                key: k,
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false,
              )),
      _lazyTab(_adminOrdersTab, (k) => OrdersScreen(key: k, isAdmin: true)),
      _lazyTab(
          _adminInventoryTab,
          (k) => InventoryScreen(
                key: k,
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false,
                onBackNeeded: () =>
                    setState(() => _inventoryInDetailView = true),
                onOpenDrawer: () =>
                    setState(() => _inventoryInDetailView = false),
              ),
          fixedKey: _inventoryKey),
      _lazyTab(_adminAnalyticsTab,
          (k) => AnalyticsScreen(key: k, showAppBar: false)),
      _lazyTab(
          _adminFinanceTab,
          (k) => FinanceScreen(
                key: k,
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false,
                onNavigate: _goToTab,
              )),
      _lazyTab(
          _adminStaffTab,
          (k) => StaffManagementScreen(
                key: k,
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false,
              )),
    ];

    final staffTabs = <Widget>[
      _lazyTab(_staffPosTab, (k) => POSScreen(key: k, showAppBar: false)),
      _lazyTab(_staffOrdersTab, (k) => OrdersScreen(key: k)),
      _lazyTab(
          _staffMenuTab,
          (k) => MenuScreen(
                key: k,
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false,
              )),
    ];

    final tabs = _isAdminRole ? adminTabs : staffTabs;

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    final isNarrowSearch = MediaQuery.of(context).size.width < 520;
    final searchHint = isNarrowSearch ? '' : 'Search';
    final pageTitle = _pageTitleForIndex(_selectedIndex);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            final showBackButton = _isAdminRole &&
                _selectedIndex == _adminInventoryTab &&
                _inventoryInDetailView;
            return IconButton(
              tooltip: showBackButton
                  ? 'Back'
                  : (_sidebarVisible ? 'Hide Menu' : 'Show Menu'),
              icon: Icon(showBackButton
                  ? Icons.arrow_back
                  : (_sidebarVisible ? Icons.menu_open : Icons.menu)),
              onPressed: _isRoleLoading
                  ? null
                  : () {
                      if (showBackButton) {
                        setState(() => _inventoryInDetailView = false);
                        null;
                      } else {
                        setState(() => _sidebarVisible = !_sidebarVisible);
                      }
                    },
            );
          },
        ),
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
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        _showGlobalSearchResults(v.trim());
                      }
                    },
                    onTap: () {
                      if (_globalSearchQuery.value.trim().isNotEmpty) {
                        _showGlobalSearchResults(
                            _globalSearchQuery.value.trim());
                      }
                    },
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
                      fillColor: Colors.white.withValues(alpha: 0.18),
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
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

            final searchWidth = isNarrow
                ? (constraints.maxWidth >= 420
                    ? 180.0
                    : constraints.maxWidth >= 380
                        ? 160.0
                        : 140.0)
                : maxSearchWidth;

            final brandMaxWidth = isNarrow
                ? 130.0
                : constraints.maxWidth >= 900
                    ? 240.0
                    : 180.0;

            final brand = ConstrainedBox(
              constraints: BoxConstraints(maxWidth: brandMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Smart Eat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_eateryName.trim().isNotEmpty)
                    Text(
                      _eateryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                ],
              ),
            );

            final title = Text(
              pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            );

            return SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: brand,
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: brandMaxWidth + 12,
                      ),
                      child: title,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: searchField(searchWidth),
                  ),
                ],
              ),
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
                      ((Theme.of(context).colorScheme.primary.b * 255.0)
                                  .round() +
                              40)
                          .clamp(0, 255),
                    ),
              ],
            ),
          ),
        ),
        elevation: 2,
        shadowColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        actions: const [
          // Chatbot entry point intentionally removed from the header. The
          // ChatbotScreen import is retained for the code to be re-wired later.
          SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 768;

          // Wide screen: persistent sidebar that compresses content
          if (isWideScreen) {
            return Row(
              children: [
                if (_sidebarVisible) _buildSidebar(),
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(
                        index: _selectedIndex,
                        children: tabs,
                      ),
                      if (_isRoleLoading)
                        Container(
                          color: Colors.white.withValues(alpha: 0.8),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Narrow screen: overlay sidebar
          return Stack(
            children: [
              IndexedStack(
                index: _selectedIndex,
                children: tabs,
              ),
              if (_sidebarVisible)
                GestureDetector(
                  onTap: () => setState(() => _sidebarVisible = false),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              if (_sidebarVisible) _buildSidebar(),
              if (_isRoleLoading)
                Container(
                  color: Colors.white.withValues(alpha: 0.8),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    final email = context.read<AuthProvider>().user?.email ?? '';
    final roleLabel = _isAdmin ? 'Admin' : 'Staff';
    final sidebarWidth = 260.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.2),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (_eateryName.isNotEmpty)
                        Text(
                          _eateryName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontSize: 11,
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
                    onTap: () => _setAdminViewEnabled(!_adminViewEnabled),
                  ),
                if (_isAdminRole) ...[
                  _buildNavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Home',
                    index: _adminHomeTab,
                  ),
                  _buildNavItem(
                    icon: Icons.restaurant_menu,
                    label: 'Menu',
                    index: _adminMenuTab,
                  ),
                  _buildNavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orders',
                    index: _adminOrdersTab,
                  ),
                  _buildNavItem(
                    icon: Icons.inventory,
                    label: 'Inventory',
                    index: _adminInventoryTab,
                  ),
                  _buildNavItem(
                    icon: Icons.analytics,
                    label: 'Analytics',
                    index: _adminAnalyticsTab,
                  ),
                  _buildNavItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Finance',
                    index: _adminFinanceTab,
                  ),
                  _buildNavItem(
                    icon: Icons.group_outlined,
                    label: 'Staff',
                    index: _adminStaffTab,
                  ),
                ] else ...[
                  _buildNavItem(
                    icon: Icons.shopping_cart,
                    label: 'POS',
                    index: _staffPosTab,
                  ),
                  _buildNavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orders',
                    index: _staffOrdersTab,
                  ),
                  _buildNavItem(
                    icon: Icons.restaurant_menu,
                    label: 'Menu',
                    index: _staffMenuTab,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.lunch_dining_outlined,
                      color: Colors.grey.shade600,
                    ),
                    title: const Text('Staff meal'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const StaffMealDialog(),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.payments_outlined,
                      color: Colors.grey.shade600,
                    ),
                    title: const Text('My payroll'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyPayrollScreen(),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  onTap: () =>
                      Navigator.of(context).pushNamed('/notifications'),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title:
                      const Text('Logout', style: TextStyle(color: Colors.red)),
                  onTap: () => context.read<AuthProvider>().logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade600,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      onTap: () => _goToTab(index),
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

class _DashboardHomeTabState extends State<DashboardHomeTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _todayOrders = const [];
  List<Map<String, dynamic>> _lowStock = const [];
  List<Map<String, dynamic>> _payables = const [];
  List<Map<String, dynamic>> _expenses = const [];
  List<Map<String, dynamic>> _itemPerformance = const [];
  List<Map<String, dynamic>> _dailySales = const [];
  List<Map<String, dynamic>> _stockMovements = const [];
  List<Map<String, dynamic>> _inventoryItems = const [];
  List<Map<String, dynamic>> _damagedItems = const [];

  // Aggregated KPIs. Single source of truth for every metric tile.
  DashboardModel? _model;

  String? _eateryId;

  // Health score lives on BusinessContext, not DashboardModel, so it needs its
  // own call (analytics_service.dart:583).
  double _healthScore = 0;
  String _healthLabel = '';

  // Seven-day revenue series + next-peak forecast for the Sales Trend card.
  // Loaded once per [_loadDashboard]; never fetched from build().
  List<TrendPoint> _trendPoints = const [];
  String _trendForecast = '';

  @override
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
      String? eateryId;
      try {
        eateryId = await FirebaseService.getCurrentEateryId();
      } catch (e) {
        debugPrint('getCurrentEateryId failed: $e');
      }

      dynamic safe(Future<dynamic> f, String label) async {
        try {
          return await f;
        } catch (e) {
          debugPrint('$label failed: $e');
          return <String, dynamic>{'data': const []};
        }
      }

      final results = await Future.wait<dynamic>([
        safe(ApiService.getTodayOrders(), 'getTodayOrders'),
        safe(ApiService.getLowStockItems(), 'getLowStockItems'),
        safe(ApiService.getPayables(), 'getPayables'),
        safe(ApiService.getExpenses(), 'getExpenses'),
        safe(ApiService.getItemPerformance(), 'getItemPerformance'),
        safe(ApiService.getDailySalesAnalytics(days: 62),
            'getDailySalesAnalytics'),
        safe(ApiService.getStockMovements(), 'getStockMovements'),
        safe(ApiService.getInventoryItems(), 'getInventoryItems'),
        safe(ApiService.getDamagedItems(), 'getDamagedItems'),
      ]);
      ;

      List<Map<String, dynamic>> asList(dynamic raw) {
        try {
          if (raw is List)
            return raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          if (raw is! Map) return const [];
          final data = raw['data'];
          if (data is List)
            return data
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          if (data is Map) {
            for (final k in const ['items', 'orders', 'dailySales']) {
              final v = data[k];
              if (v is List)
                return v
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
            }
          }
        } catch (_) {}
        return const [];
      }

      final orders = asList(results[0]);
      final lowStock = asList(results[1]);
      final payables = asList(results[2]);
      final expenses = asList(results[3]);
      final itemPerfRaw = results[4] as Map<String, dynamic>? ?? const {};
      final itemPerformance = List<Map<String, dynamic>>.from(
          itemPerfRaw['data']?['items'] ?? itemPerfRaw['items'] ?? const []);
      final salesRaw = results[5] as Map<String, dynamic>? ?? const {};
      final dailySales = List<Map<String, dynamic>>.from(salesRaw['data']
              ?['dailySales'] ??
          salesRaw['dailySales'] ??
          const []);
      final stockMovements = asList(results[6]);
      final inventoryItems = asList(results[7]);
      final damagedItems = asList(results[8]);

      // Aggregated KPI model. Skipped when eateryId is unavailable so the
      // list cards below still render rather than failing the whole load.
      DashboardModel? model;
      double healthScore = 0;
      String healthLabel = '';
      if (eateryId != null && eateryId.isNotEmpty) {
        try {
          model = await AnalyticsService.getDashboardModel(eateryId);
        } catch (e) {
          debugPrint('DashboardModel fetch failed: $e');
        }
        try {
          final health =
              await AnalyticsService.getBusinessHealthScore(eateryId);
          healthScore = (health['score'] as num?)?.toDouble() ?? 0;
          healthLabel = (health['label'] ?? '').toString();
        } catch (e) {
          debugPrint('BusinessHealthScore fetch failed: $e');
        }
      }

      // Incomplete orders now live on the Orders tab, not here.

      List<TrendPoint> trendPoints = const [];
      String trendForecast = '';
      if (eateryId != null && eateryId.isNotEmpty) {
        final trend = await _loadTrendSeries(eateryId);
        trendPoints = trend.points;
        trendForecast = trend.forecast;
      }

      if (!mounted) return;
      setState(() {
        _eateryId = eateryId;
        _model = model;
        _healthScore = healthScore;
        _healthLabel = healthLabel;
        _todayOrders = orders;
        _lowStock = lowStock;
        _payables = payables;
        _expenses = expenses;
        _itemPerformance = itemPerformance;
        _dailySales = dailySales;
        _stockMovements = stockMovements;
        _inventoryItems = inventoryItems;
        _damagedItems = damagedItems;
        _trendPoints = trendPoints;
        _trendForecast = trendForecast;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildStaffCard(BuildContext context) {
    final eateryId = _eateryId;
    if (eateryId == null || eateryId.isEmpty) {
      return const SizedBox.shrink();
    }

    final todayKey = staffFormatYmd(DateTime.now());
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: StaffService.usersStream(eateryId),
      builder: (context, usersSnap) {
        if (usersSnap.hasError) {
          return _staffCardShell(
            child: Text('Failed to load staff: ${usersSnap.error}'),
          );
        }
        if (!usersSnap.hasData) {
          return _staffCardShell(
            child: const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final staff = <Map<String, dynamic>>[];
        for (final doc in usersSnap.data!.docs) {
          final data = doc.data();
          if (isAdminUser(data) || !isApprovedUser(data)) continue;
          staff.add({'uid': doc.id, ...data});
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: StaffService.attendanceStream(
            eateryId,
            startKey: todayKey,
            endKey: todayKey,
          ),
          builder: (context, attendanceSnap) {
            final presentUids = <String>{};
            for (final doc in attendanceSnap.data?.docs ?? const []) {
              final data = doc.data();
              final uid = (data['uid'] ?? '').toString().trim();
              if (uid.isEmpty) continue;
              final rawUnit = data['workUnit'];
              final workUnit = rawUnit is num ? rawUnit.toDouble() : 0.0;
              if (data['present'] == true || workUnit > 0) {
                presentUids.add(uid);
              }
            }

            final presentCount =
                staff.where((s) => presentUids.contains(s['uid'])).length;

            final ordered = [...staff]..sort((a, b) {
                final aPresent = presentUids.contains(a['uid']) ? 0 : 1;
                final bPresent = presentUids.contains(b['uid']) ? 0 : 1;
                if (aPresent != bPresent) return aPresent.compareTo(bPresent);
                final aName =
                    staffDisplayName(a, a['uid'] as String).toLowerCase();
                final bName =
                    staffDisplayName(b, b['uid'] as String).toLowerCase();
                return aName.compareTo(bName);
              });

            final visible = ordered.take(6).toList();
            final hidden = ordered.length - visible.length;

            return _staffCardShell(
              presentCount: presentCount,
              totalCount: staff.length,
              child: staff.isEmpty
                  ? Text(
                      'No staff accounts yet. Add staff from Staff Management.',
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const Divider(height: 16),
                          _buildStaffRow(
                            context,
                            visible[i]['uid'] as String,
                            visible[i],
                            isPresent: presentUids.contains(visible[i]['uid']),
                          ),
                        ],
                        if (hidden > 0) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '+$hidden more staff',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _staffCardShell({
    required Widget child,
    int? presentCount,
    int? totalCount,
  }) {
    return SectionCard(
      title: 'Staff on duty',
      icon: Icons.groups_outlined,
      iconColor: Colors.deepPurple,
      badge: totalCount == null ? null : '$presentCount/$totalCount',
      action: TextButton(
        onPressed: () => widget.onNavigate(AdminTabIndex.staff),
        child: const Text('View all'),
      ),
      child: child,
    );
  }

  Widget _buildStaffRow(
    BuildContext context,
    String uid,
    Map<String, dynamic> data, {
    required bool isPresent,
  }) {
    final name = staffDisplayName(data, uid);
    final phone = staffPhone(data);
    final subtitle =
        phone.isNotEmpty ? phone : (data['email'] ?? '').toString().trim();
    final scheme = Theme.of(context).colorScheme;
    final color = isPresent ? Colors.green : scheme.outline;
    final textColor =
        isPresent ? Colors.green.shade800 : scheme.onSurfaceVariant;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            staffInitials(name),
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
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
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isPresent ? 'On duty' : 'Not in yet',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKpis(BuildContext context) {
    final m = _model;

    final todayRevenue = m?.todayRevenue ?? 0.0;
    final dayChange = m?.dayChangePercent ?? 0.0;
    final ordersToday = m?.todayTotalOrders ?? _todayOrders.length;
    final pendingToday = m?.todayPendingCount ?? 0;
    final aov = m?.averageOrderValue ?? 0.0;
    final weekRevenue = m?.weekRevenue ?? 0.0;
    final itemsSold = m?.todayTotalItemsSold ?? 0;
    final totalMenuItems = m?.totalMenuItems ?? 0;
    final zeroSales = m?.zeroSalesItemCount ?? 0;
    final lowStockCount = m?.lowStockCount ?? _lowStock.length;
    final criticalStock = m?.criticalStockCount ?? 0;

    final now = DateTime.now();
    double mtdNetSales = 0;
    for (final sale in _dailySales) {
      final date = DateTime.tryParse(sale['date']?.toString() ?? '');
      if (date == null) continue;
      if (date.year != now.year || date.month != now.month) continue;
      mtdNetSales += (sale['revenue'] as num?)?.toDouble() ??
          (sale['totalAmount'] as num?)?.toDouble() ??
          0;
    }
    final mtdEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final mtdStart = DateTime(now.year, now.month, 1);
    final opExMtd =
        BusinessKpis.operatingExpenses(_expenses, start: mtdStart, end: mtdEnd);
    final cogs = BusinessKpis.resolveCogs(
        stockMovements: _stockMovements, itemPerformance: _itemPerformance);
    final menuRows = BusinessKpis.menuProfitRows(_itemPerformance);
    final costed = menuRows.where((r) => r.hasCosting).length;
    final recipeMargin = menuRows
        .where((r) => r.hasCosting)
        .fold<double>(0, (s, r) => s + r.profit);
    final recipeRevenue = menuRows
        .where((r) => r.hasCosting)
        .fold<double>(0, (s, r) => s + r.revenue);
    final recipeCogs = menuRows
        .where((r) => r.hasCosting)
        .fold<double>(0, (s, r) => s + r.estimatedCogs);
    final netProfitMtd = cogs.isEstimated
        ? (mtdNetSales -
            opExMtd -
            (recipeRevenue > 0
                ? mtdNetSales * (recipeCogs / recipeRevenue)
                : 0))
        : (mtdNetSales - opExMtd - cogs.amount);
    final inv = BusinessKpis.inventoryKpi(
        inventoryItems: _inventoryItems,
        stockMovements: _stockMovements,
        damagedItems: _damagedItems);
    final payablesKpi = BusinessKpis.payablesKpi(_payables, now: now);

    final currency = NumberFormat.currency(symbol: '\u20B1', decimalDigits: 2);
    final peso = NumberFormat.currency(symbol: '\u20B1', decimalDigits: 0);

    final tiles = <Widget>[
      KpiCard(
          title: 'Today\'s Sales',
          value: peso.format(todayRevenue),
          icon: Icons.payments_outlined,
          color: Colors.blue,
          trendPercent: m == null ? null : dayChange,
          description:
              'Total sales from orders placed today. Trend compares today to yesterday when available.'),
      KpiCard(
          title: 'Orders Today',
          value: ordersToday.toString(),
          icon: Icons.receipt_long_outlined,
          color: Colors.indigo,
          subtitle:
              pendingToday > 0 ? '$pendingToday pending' : 'All completed',
          description:
              'Number of orders created today, with pending/incomplete orders shown in the subtitle.'),
      KpiCard(
          title: 'Avg Order Value',
          value: currency.format(aov),
          icon: Icons.calculate_outlined,
          color: Colors.teal,
          description:
              'Average amount spent per completed order (AOV), based on available order totals.'),
      KpiCard(
          title: 'Net Profit (MTD)',
          value: peso.format(netProfitMtd),
          icon: Icons.savings_outlined,
          color: netProfitMtd >= 0 ? Colors.green : Colors.red,
          subtitle:
              'Uses ${cogs.sourceLabel}${cogs.isEstimated ? " ratio estimate" : ""}; discounts/order-level gross may be unavailable here',
          description:
              'Month-to-date net profit estimate: net sales minus operating expenses and COGS. Uses Actual sale-consumption COGS when available; otherwise uses Estimated recipe/menu costing.'),
      KpiCard(
          title: 'Gross Margin (Menu Costing)',
          value: peso.format(recipeMargin),
          icon: Icons.calculate_outlined,
          color: recipeMargin >= 0 ? Colors.green : Colors.red,
          subtitle:
              '$costed/${_itemPerformance.length} costed \u00B7 separate from Actual COGS',
          description:
              'Recipe/menu-costing gross margin for costed items. Separate from Actual COGS (stock movements/sale consumption when available).'),
      KpiCard(
          title: 'Inventory Value / Waste',
          value: peso.format(inv.inventoryValue),
          icon: Icons.inventory_2_outlined,
          color: Colors.brown,
          subtitle:
              'Waste ${currency.format(inv.wasteCost)} \u00B7 ${inv.hasActualConsumption ? "consumption tracked" : "consumption N/A"}',
          description:
              'Current inventory value from on-hand stock and unit costs. Waste comes from damaged/write-off records; consumption appears only when sale-consumption movements exist.'),
      KpiCard(
          title: 'Outstanding Payables',
          value: peso.format(payablesKpi.outstanding),
          icon: Icons.payment,
          color: Colors.orange,
          subtitle:
              'Overdue ${currency.format(payablesKpi.overdue)} \u00B7 Due 30d ${payablesKpi.dueThisMonth}',
          description:
              'Total unpaid payables currently outstanding, including overdue amounts and bills due in the next 30 days.'),
      KpiCard(
          title: 'Week Revenue',
          value: peso.format(weekRevenue),
          icon: Icons.calendar_view_week_outlined,
          color: Colors.deepPurple,
          description:
              'Total revenue for the current week based on completed order/sales data.'),
      KpiCard(
          title: 'Low Stock / Menu',
          value: lowStockCount.toString(),
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          subtitle: criticalStock > 0
              ? '$criticalStock critical \u00B7 Menu $totalMenuItems'
              : 'Items sold today $itemsSold \u00B7 Menu $totalMenuItems${zeroSales > 0 ? " ($zeroSales no sales)" : ""}',
          description:
              'Inventory and menu health: low/critical stock items, total menu items, and menu items with no recorded sales.'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100 ? 4 : (width >= 560 ? 2 : 1);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // Wider ratio = shorter tiles, closer to Finance/Inventory KPI density.
            childAspectRatio: crossAxisCount == 1 ? 3.2 : 2.9,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) => tiles[index],
        );
      },
    );
  }

  /// Seven-day revenue line chart with a next-peak forecast line.
  ///
  /// Reads the series cached on state by [_loadTrendSeries]; performant because
  /// build() stays synchronous and never triggers a fetch.
  Widget _buildSalesTrend(BuildContext context) {
    final points = _trendPoints;
    final forecastText = _trendForecast;

    return SectionCard(
      title: 'Sales Trend',
      icon: Icons.show_chart_rounded,
      iconColor: const Color(0xFF1E88E5),
      badge: 'Last 7 days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevenueTrendChart(points: points, height: 170),
          if (forecastText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_graph_outlined,
                    size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    forecastText,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Fetches the trend series and forecast off the critical path and returns
  /// them. Awaited by [_loadDashboard] so the fetch happens exactly once per
  /// load rather than on every rebuild.
  Future<({List<TrendPoint> points, String forecast})> _loadTrendSeries(
    String eateryId,
  ) async {
    var points = <TrendPoint>[];
    var forecast = '';
    try {
      final results = await Future.wait<dynamic>([
        AnalyticsService.getSalesTrend(eateryId, days: 7),
        AnalyticsService.getSalesForecast(eateryId),
      ]);

      final trendRaw = results[0]['dailyTrend'];
      if (trendRaw is List) {
        points = trendRaw
            .map((raw) {
              final m = raw is Map ? raw : const {};
              final date = DateTime.tryParse((m['date'] ?? '').toString());
              return TrendPoint(
                label: date != null ? DateFormat('EEE').format(date) : '',
                value: (m['revenue'] as num?)?.toDouble() ?? 0,
              );
            })
            .where((p) => p.label.isNotEmpty)
            .toList();
      }

      final forecastRaw = results[1]['forecast'];
      if (forecastRaw is List && forecastRaw.isNotEmpty) {
        final next = forecastRaw.first;
        if (next is Map) {
          final predicted = (next['predictedRevenue'] as num?)?.toDouble() ?? 0;
          final dayName = (next['dayName'] ?? '').toString();
          if (predicted > 0) {
            final peso = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
            forecast = 'Forecast for $dayName: ${peso.format(predicted)}';
          }
        }
      }
    } catch (e) {
      debugPrint('Sales trend fetch failed: $e');
    }
    return (points: points, forecast: forecast);
  }

  /// Compact menu health: top five sellers by revenue, plus category and
  /// zero-sales counts. No equivalent summary exists elsewhere in the app.
  Widget _buildMenuPerformance(BuildContext context) {
    final m = _model;
    final top = (m?.topFiveItems ?? const [])
        .cast<Map<String, dynamic>>()
        .take(5)
        .toList();
    final maxRevenue = top.isEmpty
        ? 0.0
        : top
            .map((e) => (e['revenue'] as num?)?.toDouble() ?? 0)
            .reduce((a, b) => a > b ? a : b);
    final peso = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return SectionCard(
      title: 'Menu Performance',
      icon: Icons.restaurant_menu,
      iconColor: const Color(0xFF0EA5A4),
      badge: 'Last 30 days',
      child: top.isEmpty
          ? const EmptyState(
              icon: Icons.restaurant_menu,
              title: 'No sales data yet',
              subtitle: 'Top sellers appear once orders start coming in.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in top) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (item['name'] ?? 'Item').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item['qty'] ?? 0} sold',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              peso.format(
                                  (item['revenue'] as num?)?.toDouble() ?? 0),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: maxRevenue <= 0
                                ? 0
                                : ((item['revenue'] as num?)?.toDouble() ?? 0) /
                                    maxRevenue,
                            minHeight: 4,
                            backgroundColor: Colors.grey.shade200,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFF0EA5A4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if ((m?.zeroSalesItemCount ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${m!.zeroSalesItemCount} menu item'
                    '${m.zeroSalesItemCount == 1 ? '' : 's'} with no sales',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildFinanceOverview(BuildContext context) {
    final now = DateTime.now();
    final payablesKpi = BusinessKpis.payablesKpi(_payables, now: now);
    final overdue = payablesKpi.overdue;
    final upcomingPayables =
        FinanceMetrics.upcomingPayables(_payables, days: 7, now: now)
          ..sort((a, b) {
            final ad = FinanceFormat.asDate(a['dueDate']);
            final bd = FinanceFormat.asDate(b['dueDate']);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });
    final unpaidCount =
        _payables.where((p) => !FinanceMetrics.isPaid(p)).length;
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final totalMonthlyExpenses = BusinessKpis.operatingExpenses(_expenses,
        start: monthStart, end: monthEnd);
    double mtdNetSales = 0;
    for (final sale in _dailySales) {
      final date = DateTime.tryParse(sale['date']?.toString() ?? '');
      if (date == null || date.year != now.year || date.month != now.month)
        continue;
      mtdNetSales += (sale['revenue'] as num?)?.toDouble() ??
          (sale['totalAmount'] as num?)?.toDouble() ??
          0;
    }
    final cogs = BusinessKpis.resolveCogs(
        stockMovements: _stockMovements, itemPerformance: _itemPerformance);
    final menuRows = BusinessKpis.menuProfitRows(_itemPerformance);
    final recipeRevenue = menuRows
        .where((r) => r.hasCosting)
        .fold<double>(0, (s, r) => s + r.revenue);
    final recipeCogs = menuRows
        .where((r) => r.hasCosting)
        .fold<double>(0, (s, r) => s + r.estimatedCogs);
    final cogsValue = cogs.isEstimated
        ? (recipeRevenue > 0 ? mtdNetSales * (recipeCogs / recipeRevenue) : 0.0)
        : cogs.amount;
    final netProfitMtd = mtdNetSales - totalMonthlyExpenses - cogsValue;
    final margin = mtdNetSales > 0 ? netProfitMtd / mtdNetSales * 100 : 0.0;
    final peso = NumberFormat.currency(symbol: '\u20B1', decimalDigits: 0);
    final currency = NumberFormat.currency(symbol: '\u20B1', decimalDigits: 2);
    final upcomingLabel =
        upcomingPayables.isEmpty ? null : '${upcomingPayables.length} due';

    return SectionCard(
      title: 'Finance Overview',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: const Color(0xFF16A34A),
      badge: upcomingLabel,
      action: TextButton(
          onPressed: () =>
              widget.onNavigate(_DashboardScreenState._adminFinanceTab),
          child: const Text('Open')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'MTD Net Sales*',
                  value: peso.format(mtdNetSales),
                  color: Colors.green,
                  description:
                      'Month-to-date net sales from daily sales data. Order-level discounts/gross may be unavailable in this source.')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'COGS*',
                  value: peso.format(cogsValue),
                  color: Colors.blue,
                  description:
                      'COGS for this snapshot: Actual sale-consumption movements when available; otherwise Estimated recipe/menu costing fallback.')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'OpEx (MTD)',
                  value: peso.format(totalMonthlyExpenses),
                  color: Colors.red,
                  description:
                      'Month-to-date operating expenses using an expense-category heuristic.')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'Net Profit*',
                  value: peso.format(netProfitMtd),
                  color: netProfitMtd >= 0 ? Colors.teal : Colors.red,
                  description:
                      'Estimated month-to-date net profit (net sales minus COGS* and operating expenses).')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'Margin*',
                  value: '${margin.toStringAsFixed(1)}%',
                  color: netProfitMtd >= 0 ? Colors.teal : Colors.red,
                  description:
                      'Net profit margin based on the COGS* source shown above.')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: 'Payables Due',
                  value: peso.format(payablesKpi.outstanding),
                  color: Colors.orange,
                  description:
                      'Outstanding payables/bills due, including overdue/upcoming amounts when available.')),
          SizedBox(
              width: 150,
              child: _MiniMetric(
                  label: overdue > 0 ? 'Overdue' : 'Unpaid',
                  value: overdue > 0 ? peso.format(overdue) : '$unpaidCount',
                  color: overdue > 0 ? Colors.red : Colors.purple)),
        ]),
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '*Net sales from daily sales (discount/gross may be unavailable). COGS: ${cogs.sourceLabel}${cogs.isEstimated ? ' (estimated fallback)' : ''}; separate from menu-costing gross margin. Operating expenses heuristic.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        if (upcomingPayables.isEmpty)
          Text('No bills due within 7 days.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
        else
          ...upcomingPayables.take(3).map((p) {
            final name = (p['name'] ?? 'Unknown').toString();
            final isVariable = FinanceMetrics.isVariablePayable(p);
            final amount = FinanceMetrics.amountOf(p);
            final estimate = FinanceMetrics.estimatedAmountOf(p);
            final due = _asDate(p['dueDate']);
            final frequency = (p['frequency'] ?? '').toString();
            String dueText = 'No due date';
            if (due != null) {
              final daysUntil = due.difference(now).inDays;
              if (daysUntil < 0)
                dueText = '${daysUntil.abs()} days overdue';
              else if (daysUntil == 0)
                dueText = 'Due today';
              else if (daysUntil == 1)
                dueText = 'Due tomorrow';
              else
                dueText = 'Due in $daysUntil days';
            }
            final amountText = isVariable
                ? (amount > 0
                    ? currency.format(amount)
                    : (estimate > 0
                        ? '~${currency.format(estimate)} est.'
                        : 'Amount varies'))
                : currency.format(amount);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                  '$dueText${frequency.isNotEmpty ? ' · $frequency' : ''}',
                  style: const TextStyle(fontSize: 12)),
              trailing: Text(amountText,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          (isVariable && estimate <= 0) ? Colors.grey : null)),
            );
          }),
      ]),
    );
  }

  /// Inline Sage briefing summary for the dashboard.
  ///
  /// Renders the latest persisted briefing from [AIAssistantProvider] rather
  /// than the modal [SageBriefingCard] dialog, which cannot be embedded in a
  /// scroll view. "Open Sage" hands off to the side panel for the full view.
  Widget _buildSageBriefingCard(BuildContext context) {
    final assistant = context.watch<AIAssistantProvider>();
    final briefing = assistant.latestBriefing;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Sage Briefing',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (briefing != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      briefing.periodLabel,
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (briefing == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Sage briefing yet.',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check back during the next scheduled briefing window.',
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                DateFormat('MMM d, yyyy • h:mm a').format(briefing.generatedAt),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                briefing.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.grey.shade800,
                ),
              ),
              if (briefing.recommendation.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Recommendation",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        briefing.recommendation,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          assistant.openSageBriefingPanel(showHistory: false),
                      child: const Text('Open Sage'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          assistant.openSageBriefingPanel(showHistory: true),
                      child: const Text('View All Briefings'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Widget _buildLowStock(BuildContext context) {
    // Separate low stock and out of stock
    final lowStockItems = _lowStock.where((item) {
      final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
      return current > 0;
    }).toList();

    final outOfStockItems = _lowStock.where((item) {
      final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
      return current <= 0;
    }).toList();

    return SectionCard(
      title: 'Inventory Overview',
      icon: Icons.inventory_2_outlined,
      iconColor: const Color(0xFFF59E0B),
      badge: _lowStock.isEmpty
          ? null
          : '${lowStockItems.length + outOfStockItems.length} alerts',
      action: TextButton(
        onPressed: () =>
            widget.onNavigate(_DashboardScreenState._adminInventoryTab),
        child: const Text('Open'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same dense metric strip as the Finance Overview, so the two
          // side-by-side cards read as a matched pair.
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: 'Tracked Items',
                  value: '${_model?.totalInventoryItems ?? _lowStock.length}',
                  color: Colors.blueGrey,
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Low Stock',
                  value: '${lowStockItems.length}',
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Out of Stock',
                  value: '${outOfStockItems.length}',
                  color: Colors.red,
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Stock Value',
                  value: NumberFormat.currency(symbol: '₱', decimalDigits: 0)
                      .format(_model?.totalInventoryValue ?? 0),
                  color: const Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (lowStockItems.isEmpty && outOfStockItems.isEmpty)
            Text(
              'All good — no stock issues.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            )
          else ...[
            // Out of Stock section
            if (outOfStockItems.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Out of Stock (${outOfStockItems.length})',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...outOfStockItems
                  .take(3)
                  .map((item) => _buildStockItemTile(item, isOutOfStock: true)),
              if (outOfStockItems.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 20),
                  child: Text(
                    '+${outOfStockItems.length - 3} more',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 10),
            ],

            // Low Stock section
            if (lowStockItems.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.trending_down,
                      color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Low Stock (${lowStockItems.length})',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...lowStockItems.take(3).map(
                  (item) => _buildStockItemTile(item, isOutOfStock: false)),
              if (lowStockItems.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 20),
                  child: Text(
                    '+${lowStockItems.length - 3} more',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStockItemTile(Map<String, dynamic> item,
      {required bool isOutOfStock}) {
    final name = (item['name'] ?? 'Unknown').toString();
    final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
    final min = (item['minStock'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap: () => _showInventoryItemDetails(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOutOfStock ? Colors.red : Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isOutOfStock
                        ? 'Out of stock'
                        : 'Current: ${current.toStringAsFixed(1)}  •  Min: ${min.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: isOutOfStock ? Colors.red : Colors.orange.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  void _showInventoryItemDetails(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'Unknown').toString();
    final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
    final min = (item['minStock'] as num?)?.toDouble() ?? 0;
    final unit = (item['unit'] ?? 'units').toString();
    final category = (item['category'] ?? 'Uncategorized').toString();
    final isOutOfStock = current <= 0;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: isOutOfStock ? Colors.red : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOutOfStock
                        ? Colors.red.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOutOfStock
                          ? Colors.red.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOutOfStock
                            ? Icons.error_outline
                            : Icons.warning_amber,
                        color: isOutOfStock ? Colors.red : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOutOfStock ? 'Out of Stock' : 'Low Stock Alert',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isOutOfStock
                                    ? Colors.red
                                    : Colors.orange.shade700,
                              ),
                            ),
                            Text(
                              isOutOfStock
                                  ? 'This item needs restocking immediately'
                                  : 'Current stock is below minimum level',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Category:', category),
                _buildDetailRow(
                    'Current Stock:', '${current.toStringAsFixed(1)} $unit'),
                _buildDetailRow(
                    'Minimum Stock:', '${min.toStringAsFixed(1)} $unit'),
                if (!isOutOfStock)
                  _buildDetailRow('Shortage:',
                      '${(min - current).toStringAsFixed(1)} $unit'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigate(_DashboardScreenState
                    ._adminInventoryTab); // Navigate to Inventory
              },
              icon: const Icon(Icons.inventory, size: 18),
              label: const Text('View Inventory'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
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
                    _buildKpis(context),
                    const SizedBox(height: 16),
                    _buildSageBriefingCard(context),
                    const SizedBox(height: 16),
                    // Finance – Inventory at ≥900px, stacked below that.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildFinanceOverview(context)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildLowStock(context)),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildFinanceOverview(context),
                            const SizedBox(height: 16),
                            _buildLowStock(context),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildStaffCard(context),
                    const SizedBox(height: 16),
                    // Menu performance – Sales trend at ≥900px.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildMenuPerformance(context)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildSalesTrend(context)),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildMenuPerformance(context),
                            const SizedBox(height: 16),
                            _buildSalesTrend(context),
                          ],
                        );
                      },
                    ),
                  ],
                ),
    );
  }
}

/// One row of the "Incomplete Orders" card on the admin home dashboard.
///
/// Deliberately not a [ListTile]. ListTile's trailing slot is height-
/// constrained, so stacking an amount above a button overflowed its box by a
/// few pixels. Here the amount and the action sit side by side in a single
/// [Row], so there is no vertical budget to miss and the row grows with its
/// text instead of clipping it.
class IncompleteOrderRow extends StatelessWidget {
  const IncompleteOrderRow({
    super.key,
    required this.orderId,
    required this.total,
    required this.dateText,
    required this.isCompleting,
    required this.onTap,
    required this.onComplete,
  });

  final String orderId;
  final double total;
  final String dateText;
  final bool isCompleting;
  final VoidCallback? onTap;
  final VoidCallback onComplete;

  static const double _wideActionWidth = 92;
  static const double _narrowActionWidth = 32;
  static const double _actionHeight = 32;

  /// Total width needed before the labelled "Complete" button is worth using:
  /// icon + gaps + a usable slice for the order id and amount.
  static const double _wideLayoutMinWidth = _wideActionWidth + 150;

  @override
  Widget build(BuildContext context) {
    // Decide the action shape from the space this row actually gets, not from
    // the window. The row lives inside a card that is sometimes one column of a
    // split layout, so window width alone can promise space it never receives.
    return LayoutBuilder(
      builder: (context, constraints) => _buildRow(constraints.maxWidth),
    );
  }

  Widget _buildRow(double availableWidth) {
// Below this the "Complete" label plus icon cannot fit beside the amount,
    // so switch to the icon-only action.
    // A 200px-wide row is the narrowest this card is ever laid out at; it is
    // covered by the overflow tests.
    final isNarrow = availableWidth < _wideLayoutMinWidth;
    final shortId = orderId.length > 6 ? orderId.substring(0, 6) : orderId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    color: Colors.red, size: 22),
                const SizedBox(width: 12),
                // Flexible, not Expanded: the text column gives up width to
                // the amount and action when space runs short.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        orderId.isEmpty ? 'Order' : 'Order #$shortId',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Created: $dateText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Flexible so an unusually long amount ellipsizes instead of
                // pushing the row into a horizontal overflow.
                Flexible(
                  child: Text(
                    '₱${total.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: isNarrow ? _narrowActionWidth : _wideActionWidth,
                  height: _actionHeight,
                  child: isNarrow
                      ? _CompleteIconButton(
                          isCompleting: isCompleting,
                          onPressed: onComplete,
                        )
                      : _CompleteButton(
                          isCompleting: isCompleting,
                          onPressed: onComplete,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The green "Complete" action shown on wide layouts.
class _CompleteButton extends StatelessWidget {
  const _CompleteButton({
    required this.isCompleting,
    required this.onPressed,
  });

  final bool isCompleting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand rather than a FittedBox: FittedBox reports its child's
    // intrinsic size upward, which is what pushed this button past its slot.
    // The caller already hands over an exactly-sized box.
    return SizedBox.expand(
      child: ElevatedButton(
        onPressed: isCompleting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isCompleting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const FittedBox(
                // Scaling the label is safe — a FittedBox inside an
                // already-fixed button cannot change the button's height.
                fit: BoxFit.scaleDown,
                child: Text(
                  'Complete',
                  maxLines: 1,
                  style: TextStyle(fontSize: 12),
                ),
              ),
      ),
    );
  }
}

/// Icon-only variant for narrow layouts, where "Complete" will not fit.
class _CompleteIconButton extends StatelessWidget {
  const _CompleteIconButton({
    required this.isCompleting,
    required this.onPressed,
  });

  final bool isCompleting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: IconButton(
        tooltip: 'Complete',
        padding: EdgeInsets.zero,
        onPressed: isCompleting ? null : onPressed,
        icon: isCompleting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle, color: Colors.green),
      ),
    );
  }
}

/// A label/value pair for dense metric strips inside [SectionCard].
///
/// Deliberately not tappable and not boxed, so a row of these reads as one
/// band of figures rather than a row of competing cards.
class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
    this.description,
  });

  final String label;
  final String value;
  final Color color;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    if (description == null || description!.isEmpty) return content;
    return Tooltip(
      message: description!,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      showDuration: const Duration(seconds: 4),
      child: content,
    );
  }
}

/// Staff meal ordering, which writes to its own `staff_meals` subcollection via
/// [ApiService.createStaffMealOrder] rather than to `orders`.
///
/// Opened from the staff sidebar's "Staff meal" action.
class StaffMealDialog extends StatefulWidget {
  const StaffMealDialog({Key? key}) : super(key: key);

  @override
  State<StaffMealDialog> createState() => _StaffMealDialogState();
}

class _StaffMealDialogState extends State<StaffMealDialog> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _menuItems = [];
  final Map<String, int> _selectedItems = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMenuItems();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadMenuItems() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getMenuItems();
      if (response['data'] != null) {
        final items = (response['data'] as List)
            .where((item) => item['isAvailable'] == true)
            .toList();
        setState(() {
          _menuItems = List<Map<String, dynamic>>.from(items);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load menu: $e')),
        );
      }
    }
  }

  void _updateQuantity(String itemId, int delta) {
    setState(() {
      final current = _selectedItems[itemId] ?? 0;
      final newQty = current + delta;
      if (newQty <= 0) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems[itemId] = newQty;
      }
    });
  }

  Future<void> _submitMealOrder() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = context.read<AuthProvider>().user;
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();

      final items = _selectedItems.entries.map((entry) {
        final menuItem = _menuItems.firstWhere((i) => i['id'] == entry.key);
        return {
          'menuId': entry.key,
          'name': menuItem['name'],
          'quantity': entry.value,
          'price': menuItem['price'] ?? 0,
        };
      }).toList();

      await ApiService.createStaffMealOrder({
        'staffId': user?.uid,
        'staffName': profile?['firstName'] != null
            ? '${profile!['firstName']} ${profile['lastName'] ?? ''}'.trim()
            : user?.email ?? 'Unknown',
        'eateryId': profile?['eateryId'] ?? '',
        'eateryName': profile?['eateryName'] ?? '',
        'items': items,
        'notes': _notesController.text.trim(),
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal order submitted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit order: $e')),
      );
    }
  }

  double get _totalCost {
    double total = 0;
    for (final entry in _selectedItems.entries) {
      final menuItem = _menuItems.firstWhere((i) => i['id'] == entry.key);
      final price = (menuItem['price'] as num?)?.toDouble() ?? 0;
      total += price * entry.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Group menu items by category
    final categories = <String, List<Map<String, dynamic>>>{};
    for (final item in _menuItems) {
      final category = item['category'] as String? ?? 'Other';
      categories.putIfAbsent(category, () => []).add(item);
    }
    final sortedCategories = categories.keys.toList()..sort();

    return AlertDialog(
      title: const Text('Staff Meal Order'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: _isLoading && _menuItems.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sortedCategories.length,
                      itemBuilder: (context, categoryIndex) {
                        final category = sortedCategories[categoryIndex];
                        final items = categories[category]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            ...items.map((item) {
                              final itemId = item['id'] ?? '';
                              final quantity = _selectedItems[itemId] ?? 0;
                              return ListTile(
                                dense: true,
                                title: Text(item['name'] ?? 'Unknown'),
                                subtitle: Text(
                                  '₱${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          _updateQuantity(itemId, -1),
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                    ),
                                    Text('$quantity'),
                                    IconButton(
                                      onPressed: () =>
                                          _updateQuantity(itemId, 1),
                                      icon: const Icon(Icons.add_circle_outline,
                                          size: 20),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₱${_totalCost.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Any special requests?',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitMealOrder,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit Order'),
        ),
      ],
    );
  }
}

// Global search result model
class _GlobalSearchResult {
  final String id;
  final String name;
  final String type;
  final String? category;
  final String? subtitle;
  final Map<String, dynamic>? data;

  _GlobalSearchResult({
    required this.id,
    required this.name,
    required this.type,
    this.category,
    this.subtitle,
    this.data,
  });
}

// Global search dialog
class _GlobalSearchDialog extends StatefulWidget {
  final String query;

  const _GlobalSearchDialog({Key? key, required this.query}) : super(key: key);

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  List<_GlobalSearchResult> _results = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = widget.query.toLowerCase();
      final results = <_GlobalSearchResult>[];

      // Search menu items
      try {
        final menuRes = await ApiService.getMenuItems();
        final menuItems =
            List<Map<String, dynamic>>.from(menuRes['data'] ?? []);
        for (final item in menuItems) {
          final name = (item['name'] ?? '').toString();
          final category = (item['category'] ?? '').toString();
          if (name.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: (item['id'] ?? '').toString(),
              name: name,
              type: 'menu',
              category: category,
              subtitle: '₱${(item['price'] ?? 0)}',
              data: item,
            ));
          }
        }
      } catch (_) {}

      // Search inventory items
      try {
        final invRes = await ApiService.getInventoryItems();
        final invItems = List<Map<String, dynamic>>.from(invRes['data'] ?? []);
        for (final item in invItems) {
          final name = (item['name'] ?? '').toString();
          if (name.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: (item['id'] ?? '').toString(),
              name: name,
              type: 'inventory',
              subtitle: 'Stock: ${(item['currentStock'] ?? 0)}',
              data: item,
            ));
          }
        }
      } catch (_) {}

      // Search orders
      try {
        final ordersRes = await ApiService.getTodayOrders();
        final orders = List<Map<String, dynamic>>.from(ordersRes['data'] ?? []);
        for (final order in orders) {
          final id = (order['id'] ?? '').toString();
          final items = order['items'] as List<dynamic>? ?? [];
          final hasMatch = items.any((it) {
            final itemName = (it is Map ? (it['name'] ?? '').toString() : '');
            return itemName.toLowerCase().contains(query);
          });
          if (hasMatch || id.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: id,
              name: 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
              type: 'order',
              subtitle:
                  '₱${(order['totalAmount'] ?? 0)} • ${(order['status'] ?? 'unknown')}',
              data: order,
            ));
          }
        }
      } catch (_) {}

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _getTypeIcon(String type) {
    switch (type) {
      case 'menu':
        return const Icon(Icons.restaurant_menu, color: Colors.teal, size: 20);
      case 'inventory':
        return const Icon(Icons.inventory_2, color: Colors.blue, size: 20);
      case 'order':
        return const Icon(Icons.receipt_long, color: Colors.indigo, size: 20);
      default:
        return const Icon(Icons.search, size: 20);
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'menu':
        return 'Menu';
      case 'inventory':
        return 'Inventory';
      case 'order':
        return 'Order';
      default:
        return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'menu':
        return Colors.teal;
      case 'inventory':
        return Colors.blue;
      case 'order':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.search),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search: "${widget.query}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 48),
                        const SizedBox(height: 12),
                        Text('Error: $_error'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _performSearch,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                color: Colors.grey.shade400, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No results found for "${widget.query}"',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            leading: _getTypeIcon(result.type),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    result.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getTypeColor(result.type)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _getTypeColor(result.type)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _getTypeLabel(result.type),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _getTypeColor(result.type),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: result.subtitle != null
                                ? Text(
                                    result.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(context).pop([result]);
                            },
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
