import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/insight.dart';
import '../models/business_context.dart';
import '../widgets/sage_briefing_card.dart';
import 'firebase_service.dart';
import 'business_context_builder.dart';
import 'firestore_insights_service.dart';
import 'api_service.dart';
import 'chat_errors.dart';
import 'intent_detector.dart';
import 'smart_snapshot_builder.dart';
import 'briefing_history.dart';
import 'briefing_history_service.dart';

class AIAssistantProvider extends ChangeNotifier {
  // ── UI panel state ───────────────────────────────────────────────────────
  bool _isExpanded = false;
  bool get isExpanded => _isExpanded;

  /// Immersive full-screen Sage mode. Entered from the side panel; minimizing
  /// returns to the side panel, closing returns to the floating button.
  bool _isFullScreen = false;
  bool get isFullScreen => _isFullScreen;

  Offset? _buttonPosition;
  Offset? get buttonPosition => _buttonPosition;

  Rect _workspaceBounds = const Rect.fromLTWH(12, 24, 800, 600);
  Rect get workspaceBounds => _workspaceBounds;

  bool _showPopup = false;
  bool get showPopup => _showPopup;
  String? _popupContent;
  String? get popupContent => _popupContent;

  // ── Active screen ────────────────────────────────────────────────────────
  String _activePage = 'dashboard';
  String get activePage => _activePage;

  // ── Insights ─────────────────────────────────────────────────────────────
  List<Insight> _activeInsights = [];
  List<Insight> get activeInsights => _activeInsights;

  bool _loadingInsights = false;
  bool get loadingInsights => _loadingInsights;

  bool _hasNewImportantInsight = false;
  bool get hasNewImportantInsight => _hasNewImportantInsight;

  // ── Business context (replaces old businessSummary map) ──────────────────
  BusinessContext? _businessContext;
  BusinessContext? get businessContext => _businessContext;

  /// Backward-compat shim so AISidePanel can read summary metrics without
  /// a full rewrite of the panel in one shot.
  Map<String, dynamic> get businessSummary => _businessContext == null
      ? {}
      : {
          'todayRevenue': _businessContext!.todayRevenue,
          'todayOrdersCount': _businessContext!.todayOrderCount,
          'pendingOrdersCount': _businessContext!.pendingOrderCount,
          'topSeller': _businessContext!.todayBestSeller,
          'lowStockCount': _businessContext!.lowStockCount,
          'lowStockNames': _businessContext!.lowStockItems
              .take(3)
              .map((i) => i['name'] as String)
              .toList(),
          'weekRevenue': _businessContext!.weekRevenue,
          'dayChangePercent': _businessContext!.dayChangePercent,
          'averageOrderValue': _businessContext!.averageOrderValue,
          'healthScore': _businessContext!.healthScore,
          'healthLabel': _businessContext!.healthLabel,
          'bestDayOfWeek': _businessContext!.bestDayOfWeek,
          'trendDirection': _businessContext!.trendDirection,
          'monthlyGrowthPercent': _businessContext!.monthlyGrowthPercent,
          'criticalStockCount': _businessContext!.criticalStockCount,
          'overallBestSeller': _businessContext!.overallBestSeller,
          'cancelledLast7Days': _businessContext!.cancelledLast7Days,
          'cancellationRatePercent': _businessContext!.cancellationRatePercent,
          'zeroSalesItemCount': _businessContext!.zeroSalesItemCount,
          'peakHour': _businessContext!.peakHour,
          'topCategory': _businessContext!.topCategory,
        };

  bool _loadingContext = false;
  bool get loadingSummary => _loadingContext; // compat alias

  // ── Chat ─────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _chatHistory = [];
  List<Map<String, dynamic>> get chatHistory => _chatHistory;

  bool _isGeneratingResponse = false;
  bool get isGeneratingResponse => _isGeneratingResponse;

  // ── Navigation stream ────────────────────────────────────────────────────
  final StreamController<String> _navigationController =
      StreamController<String>.broadcast();
  Stream<String> get navigationRequests => _navigationController.stream;

  // ── Sage Briefings ─────────────────────────────────────────────────────
  bool _showSageBriefing = false;
  bool get showSageBriefing => _showSageBriefing;

  SageBriefingContent? _sageBriefingContent;
  SageBriefingContent? get sageBriefingContent => _sageBriefingContent;

  List<SageBriefingContent> _briefingHistory = [];
  List<SageBriefingContent> get briefingHistory => _briefingHistory;

  SageBriefingContent? get latestBriefing =>
      _briefingHistory.isEmpty ? null : _briefingHistory.last;

  int _activeSageTab = 0;
  int get activeSageTab => _activeSageTab;

  // ── Access gating ────────────────────────────────────────────────────────

  /// Sage is an admin-only tool. While the staff dashboard is on screen the
  /// whole floating layer stays unmounted, so nothing can render or open it.
  /// Defaults to true so the assistant never flashes before the role resolves.
  bool _staffDashboardActive = true;
  bool get staffDashboardActive => _staffDashboardActive;

  void setStaffDashboardActive(bool active) {
    if (_staffDashboardActive == active) return;
    _staffDashboardActive = active;
    if (active) {
      _isExpanded = false;
      _isFullScreen = false;
      _showSageBriefing = false;
      _sageBriefingContent = null;
      _showPopup = false;
      _popupContent = null;
      _hasNewImportantInsight = false;
      _activeSageTab = 0;
    }
    notifyListeners();
  }

  // ── Init ─────────────────────────────────────────────────────────────────
  AIAssistantProvider() {
    _initializeAsync();
  }

  // Background refresh runs only while the Sage panel is open, so an idle
  // dashboard isn't paying for periodic Firestore reads.
  Timer? _refreshTimer;
  StreamSubscription<User?>? _authStateSub;

  Future<void> _initializeAsync() async {
    await _loadButtonPosition();
    await _loadBriefingHistory();
    if (FirebaseAuth.instance.currentUser == null) {
      print('===== FIRESTORE STARTUP GUARD =====');
      print('AIAssistantProvider startup refresh skipped because auth user is null.');
      print('Current UID: ${FirebaseAuth.instance.currentUser?.uid ?? 'N/A'}');
      print('Current eateryId: N/A');
      print('===================================');
      return;
    }
    await refreshData();

    // Refresh context when auth state changes (user signs in/out)
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // new login — refresh analytics and briefing history immediately
        refreshData();
        refreshBriefingHistory();
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer ??=
        Timer.periodic(const Duration(minutes: 10), (_) => refreshData());
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _authStateSub?.cancel();
    _navigationController.close();
    super.dispose();
  }

  // ── Panel control ────────────────────────────────────────────────────────
  void togglePanel() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _hasNewImportantInsight = false;
      _startRefreshTimer();
    } else {
      _stopRefreshTimer();
    }
    notifyListeners();
  }

  void setPanelExpanded(bool expanded) {
    _isExpanded = expanded;
    if (_isExpanded) {
      _hasNewImportantInsight = false;
      _startRefreshTimer();
    } else {
      _stopRefreshTimer();
    }
    notifyListeners();
  }

  /// Switches the immersive full-screen Sage workspace on/off. Entering
  /// dismisses any briefing overlay; minimizing returns to the side panel.
  void setFullScreen(bool active) {
    if (_isFullScreen == active) return;
    _isFullScreen = active;
    if (active) {
      dismissSageBriefing();
      _hasNewImportantInsight = false;
      _startRefreshTimer();
    } else {
      // Minimize → side panel.
      _isExpanded = true;
      _hasNewImportantInsight = false;
      _startRefreshTimer();
    }
    notifyListeners();
  }

  /// Leaves full-screen mode straight back to the collapsed floating button.
  void exitFullScreen() {
    if (!_isFullScreen) return;
    _isFullScreen = false;
    _isExpanded = false;
    _stopRefreshTimer();
    notifyListeners();
  }

  Offset clampButtonPosition(Offset pos, {double size = 56.0}) {
    final minX = _workspaceBounds.left + 12;
    final maxX = (_workspaceBounds.right - size - 12).clamp(minX, _workspaceBounds.right - 12);
    final minY = _workspaceBounds.top + 12;
    final maxY = (_workspaceBounds.bottom - size - 12).clamp(minY, _workspaceBounds.bottom - 12);

    return Offset(
      pos.dx.clamp(minX, maxX),
      pos.dy.clamp(minY, maxY),
    );
  }

  Offset snapButtonToNearestEdge(Offset pos, {double size = 56.0}) {
    final leftX = _workspaceBounds.left + 12;
    final rightX = (_workspaceBounds.right - size - 12).clamp(leftX, _workspaceBounds.right - 12);
    final clampedY = pos.dy.clamp(
      _workspaceBounds.top + 12,
      (_workspaceBounds.bottom - size - 12).clamp(_workspaceBounds.top + 12, _workspaceBounds.bottom - 12),
    );
    final useLeft = (pos.dx - leftX).abs() <= (pos.dx - rightX).abs();
    return Offset(useLeft ? leftX : rightX, clampedY);
  }

  void updateWorkspaceBounds(Rect bounds) {
    final safeBounds = Rect.fromLTWH(
      bounds.left.clamp(0.0, bounds.right),
      bounds.top.clamp(0.0, bounds.bottom),
      (bounds.width).clamp(120.0, double.infinity),
      (bounds.height).clamp(120.0, double.infinity),
    );
    _workspaceBounds = safeBounds;

    if (_buttonPosition != null) {
      final next = clampButtonPosition(_buttonPosition!);
      if ((next - _buttonPosition!).distance > 0.1) {
        _buttonPosition = next;
        notifyListeners();
        _saveButtonPosition(next);
      }
    } else {
      _buttonPosition = clampButtonPosition(const Offset(24, 24));
      notifyListeners();
      _saveButtonPosition(_buttonPosition!);
    }
  }

  void updateButtonPosition(Offset newPos) {
    final next = clampButtonPosition(newPos);
    if (_buttonPosition == next) return;
    _buttonPosition = next;
    notifyListeners();
    _saveButtonPosition(next);
  }

  void snapButtonToEdge() {
    if (_buttonPosition == null) return;
    final next = snapButtonToNearestEdge(_buttonPosition!);
    if ((next - _buttonPosition!).distance > 0.1) {
      _buttonPosition = next;
      notifyListeners();
      _saveButtonPosition(next);
    }
  }

  Future<void> _saveButtonPosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ai_button_x', pos.dx);
      await prefs.setDouble('ai_button_y', pos.dy);
    } catch (_) {}
  }

  Future<void> _loadButtonPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble('ai_button_x');
      final y = prefs.getDouble('ai_button_y');
      if (x != null && y != null) {
        _buttonPosition = clampButtonPosition(Offset(x, y));
        notifyListeners();
      }
    } catch (_) {}
  }

  void displayPopup(String content,
      {Duration duration = const Duration(seconds: 5)}) {
    _popupContent = content;
    _showPopup = true;
    notifyListeners();
    Future.delayed(duration, () {
      _showPopup = false;
      _popupContent = null;
      notifyListeners();
    });
  }

  // ── Page tracking ────────────────────────────────────────────────────────
  Future<void> setActivePage(String pageName) async {
    if (_activePage == pageName) return;
    _activePage = pageName;
    notifyListeners();
    await _loadPageInsights();
  }

  // ── Data refresh ─────────────────────────────────────────────────────────

  /// Full refresh: rebuilds the BusinessContext then derives insights from it.
  Future<void> refreshData() async {
    await Future.wait([
      _buildBusinessContext(),
      _loadPageInsights(),
    ]);
  }

  Future<void> _buildBusinessContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final eateryId = await FirebaseService.getCurrentEateryId();
    print('===== FIRESTORE REQUEST =====');
    print('Collection: eateries/${eateryId ?? 'N/A'}/orders + inventory + menu');
    print('Document: N/A');
    print('Operation: get (startup analytics)');
    print('Current UID: ${uid ?? 'N/A'}');
    print('Current eateryId: ${eateryId ?? 'N/A'}');
    print('============================');

    _loadingContext = true;
    notifyListeners();
    try {
      _businessContext = await BusinessContextBuilder.build();
      await _triggerScheduledBriefing();
      _triggerProactivePopups();
    } catch (e, stackTrace) {
      print('===== FIRESTORE ERROR =====');
      print('Code: ${e is FirebaseException ? e.code : 'N/A'}');
      print('Message: ${e is FirebaseException ? e.message ?? 'N/A' : e.toString()}');
      print('Stack: $stackTrace');
      print('==========================');
      debugPrint('_buildBusinessContext error: $e');
    }
    _loadingContext = false;
    notifyListeners();
  }

  String? _getCurrentBriefingPeriod() {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17) return 'evening';
    return null;
  }

  String _briefingStorageKey(String period) {
    final now = DateTime.now();
    return 'sage_briefing_${period}_${now.year}_${now.month}_${now.day}';
  }

  Future<bool> _hasSeenBriefingThisPeriod(String period) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_briefingStorageKey(period)) ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _markBriefingSeen(String period) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_briefingStorageKey(period), true);
    } catch (_) {}
  }

  Future<void> _triggerScheduledBriefing() async {
    if (_businessContext == null) return;

    // Keep the current briefing visible until the user manually dismisses it.
    // Background refreshes should not auto-close an active briefing.
    if (_showSageBriefing && _sageBriefingContent != null) {
      return;
    }

    final period = _getCurrentBriefingPeriod();
    if (period == null) {
      _showSageBriefing = false;
      _sageBriefingContent = null;
      notifyListeners();
      return;
    }

    final alreadySeen = await _hasSeenBriefingThisPeriod(period);
    if (alreadySeen) {
      _showSageBriefing = false;
      _sageBriefingContent = null;
      return;
    }

    final content = SageBriefingCard.buildContent(_businessContext!, period);
    _sageBriefingContent = content;
    addBriefingToHistory(content);
    _showSageBriefing = true;
    notifyListeners();
  }

  void dismissSageBriefing() {
    if (_sageBriefingContent != null) {
      _markBriefingSeen(_sageBriefingContent!.period);
    }
    _showSageBriefing = false;
    _sageBriefingContent = null;
    notifyListeners();
  }

  void setActiveSageTab(int tabIndex) {
    final next = tabIndex.clamp(0, 2);
    final openingHistory = next == 2 && _activeSageTab != 2;
    _activeSageTab = next;
    notifyListeners();
    if (openingHistory) {
      // Pull the latest durable history from Firestore when the user looks.
      refreshBriefingHistory();
    }
  }

  /// Opens the latest briefing report in the Summary tab (index 1), or the
  /// full report history in the History tab (index 2) when [showHistory].
  void openSageBriefingPanel({bool showHistory = false}) {
    dismissSageBriefing();
    setPanelExpanded(true);
    setActiveSageTab(showHistory ? 2 : 1);
  }

  /// Opens the chat tab (index 0) so the user can talk to Sage.
  void openSageChat() {
    dismissSageBriefing();
    setPanelExpanded(true);
    setActiveSageTab(0);
  }

  Future<void> _loadBriefingHistory() async {
    await _loadLocalBriefingHistory();
    await refreshBriefingHistory();
  }

  Future<void> _loadLocalBriefingHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('sage_briefings_history');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _briefingHistory = decoded
          .whereType<Map>()
          .map((item) => SageBriefingContent.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
      notifyListeners();
    } catch (_) {}
  }

  /// Pulls every briefing stored for this eatery from Firestore and merges it
  /// into the local list. Safe to call repeatedly; duplicates are ignored.
  Future<void> refreshBriefingHistory() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final eateryId = await FirebaseService.getCurrentEateryId();
      final remote = await BriefingHistoryService.fetch(eateryId);
      if (remote.isEmpty) return;
      _mergeBriefings(remote);
    } catch (e) {
      debugPrint('refreshBriefingHistory error: $e');
    }
  }

  void _mergeBriefings(Iterable<SageBriefingContent> incoming) {
    var changed = false;
    for (final briefing in incoming) {
      final key = _briefingKey(briefing);
      if (_briefingHistory.any((entry) => _briefingKey(entry) == key)) {
        continue;
      }
      _briefingHistory.add(briefing);
      changed = true;
    }
    if (!changed) return;
    _briefingHistory.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    _trimBriefingHistory();
    _saveBriefingHistory();
    notifyListeners();
  }

  static String _briefingKey(SageBriefingContent briefing) =>
      '${briefingDateKey(briefing.generatedAt)}_${briefing.period}';

  void _trimBriefingHistory() {
    const cap = 120;
    if (_briefingHistory.length > cap) {
      _briefingHistory = _briefingHistory.sublist(_briefingHistory.length - cap);
    }
  }

  Future<void> _saveBriefingHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _briefingHistory.map((entry) => entry.toJson()).toList(),
      );
      await prefs.setString('sage_briefings_history', encoded);
    } catch (_) {}
  }

  /// Adds a briefing to the local list (keyed by day + period) and persists
  /// it to Firestore for durable, cross-device history.
  void addBriefingToHistory(SageBriefingContent content) {
    final key = _briefingKey(content);
    if (_briefingHistory.any((entry) => _briefingKey(entry) == key)) return;
    _briefingHistory.add(content);
    _briefingHistory.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    _trimBriefingHistory();
    _saveBriefingHistory();
    notifyListeners();
    unawaited(_persistBriefing(content));
  }

  Future<void> _persistBriefing(SageBriefingContent content) async {
    try {
      final eateryId = await FirebaseService.getCurrentEateryId();
      await BriefingHistoryService.save(eateryId, content);
    } catch (e) {
      debugPrint('_persistBriefing error: $e');
    }
  }

  /// True when a period that has already begun today has no briefing yet.
  bool get hasMissingBriefingsToday {
    if (_businessContext == null) return false;
    final now = DateTime.now();
    final todayKey = briefingDateKey(now);
    return startedBriefingPeriods(now).any((period) => !_briefingHistory.any(
        (b) => briefingDateKey(b.generatedAt) == todayKey && b.period == period));
  }

  /// Backfills briefings for today's periods that have already started but were
  /// never generated (e.g. the app was closed during that window). Returns how
  /// many were created.
  Future<int> generateMissingBriefings() async {
    final context = _businessContext;
    if (context == null) return 0;
    final now = DateTime.now();
    final todayKey = briefingDateKey(now);
    var created = 0;
    for (final period in startedBriefingPeriods(now)) {
      final exists = _briefingHistory.any((b) =>
          briefingDateKey(b.generatedAt) == todayKey && b.period == period);
      if (exists) continue;
      addBriefingToHistory(
        SageBriefingCard.buildContent(context, period, backfill: true),
      );
      created++;
    }
    return created;
  }

  /// Automatically surfaces the most urgent insight as a floating popup.
  void _triggerProactivePopups() {
    if (_businessContext == null || _isExpanded) return;
    final ctx = _businessContext!;

    // Priority 1 — critical stock
    if (ctx.criticalStockCount > 0) {
      final names = ctx.lowStockItems
          .where((i) => i['isCritical'] == true)
          .take(2)
          .map((i) => i['name'] as String)
          .join(', ');
      displayPopup('⚠️ $names ran out of stock. Restock immediately.',
          duration: const Duration(seconds: 6));
      _hasNewImportantInsight = true;
      return;
    }

    // Priority 2 — multiple low-stock items
    if (ctx.lowStockCount >= 3) {
      final names =
          ctx.lowStockItems.take(2).map((i) => i['name'] as String).join(', ');
      displayPopup(
          '🔶 Low stock: $names and ${ctx.lowStockCount - 2} more. Reorder soon.');
      _hasNewImportantInsight = true;
      return;
    }

    // Priority 3 — strong revenue day
    if (ctx.dayChangePercent >= 15) {
      displayPopup(
          '📈 Revenue is up ${ctx.dayChangePercent.toStringAsFixed(0)}% today vs yesterday!');
      return;
    }

    // Priority 4 — declining revenue
    if (ctx.dayChangePercent <= -20) {
      displayPopup(
          '📉 Revenue dropped ${ctx.dayChangePercent.abs().toStringAsFixed(0)}% vs yesterday. Check for issues.');
      _hasNewImportantInsight = true;
      return;
    }

    // Priority 5 — today's best seller surfaced on open
    if (ctx.todayBestSeller != 'None' && ctx.todayBestSellerQty > 0) {
      displayPopup(
          '⭐ ${ctx.todayBestSeller} is today\'s top seller (${ctx.todayBestSellerQty} sold).');
    }
  }

  // ── Page insights (derived from BusinessContext) ─────────────────────────
  Future<void> _loadPageInsights() async {
    _loadingInsights = true;
    notifyListeners();
    try {
      // Reuse the cached context if fresh (< 5 min), otherwise pass null and
      // let FirestoreInsightsService build its own minimal fetch.
      final rawInsights = await FirestoreInsightsService.getInsightsForPage(
        _activePage,
        context: _businessContext,
      );

      _activeInsights = rawInsights.asMap().entries.map((entry) {
        final map = entry.value;
        return Insight(
          id: '${DateTime.now().millisecondsSinceEpoch}_${entry.key}',
          title: map['title'] ?? 'Insight',
          message: map['message'] ?? '',
          page: _activePage,
          isImportant: map['isImportant'] ?? false,
          icon: map['icon'] ?? Icons.info_outline,
          color: map['color'] ?? Colors.blue,
          createdAt: DateTime.now(),
        );
      }).toList();

      if (_activeInsights.isNotEmpty && !_isExpanded) {
        final important =
            _activeInsights.where((i) => i.isImportant).toList();
        if (important.isNotEmpty) {
          _hasNewImportantInsight = true;
          displayPopup(important.first.message);
        }
      }
    } catch (_) {}
    _loadingInsights = false;
    notifyListeners();
  }

  // ── Chat ─────────────────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _chatHistory.add({'role': 'user', 'content': text});
    _isGeneratingResponse = true;
    notifyListeners();

    try {
      // Navigation intent — handle locally, no AI call needed
      final lower = text.toLowerCase();
      if (_isNavigationIntent(lower)) {
        _handleNavigationIntent(lower);
        _isGeneratingResponse = false;
        notifyListeners();
        return;
      }

      // Ensure context is fresh before sending to AI
      if (_businessContext == null) {
        await _buildBusinessContext();
      }

      final detectedIntent = IntentDetector.detectIntent(text);
      debugPrint('🎯 [AIPanel] Detected intent: '
          '${IntentDetector.intentLabel(detectedIntent)}');

      final contextString = _businessContext == null
          ? ''
          : SmartSnapshotBuilder.build(_businessContext!, detectedIntent);

      if (contextString.isNotEmpty) {
        // Full snapshot dump is a hot-path cost — only in debug builds.
        if (kDebugMode) {
          debugPrint('--- SMART SNAPSHOT BEGIN ---\n'
              '$contextString'
              '--- SMART SNAPSHOT END ---');
          debugPrint('[AIPanel] Snapshot size: ${contextString.length} chars');
        }
      } else {
        debugPrint('[AIPanel] No snapshot for intent "$detectedIntent" '
            '— sending question only.');
      }

      final history = _chatHistory
          .take(_chatHistory.length - 1) // exclude current user message
          .where((m) => m['isError'] != true) // never re-send our own errors
          .toList()
          .cast<Map<String, dynamic>>();

      // Cap history to the same window the backend keeps (6 turns) so we do
      // not ship payloads it silently discards.
      final trimmedHistory =
          history.length > 6 ? history.sublist(history.length - 6) : history;

      // Stream the reply: append an empty assistant bubble, then grow it as
      // tokens arrive so the user sees output immediately.
      _chatHistory.add({'role': 'assistant', 'content': ''});
      final assistantIndex = _chatHistory.length - 1;
      var received = false;

      final stream = ApiService.sendChatMessageStream(
        message: text,
        history: trimmedHistory,
        context: contextString,
      ).timeout(
        const Duration(seconds: 125),
        onTimeout: (sink) =>
            sink.addError(TimeoutException('AI response took too long (>125s)')),
      );

      await for (final token in stream) {
        received = true;
        final current =
            (_chatHistory[assistantIndex]['content'] as String? ?? '') + token;
        _chatHistory[assistantIndex] = {
          'role': 'assistant',
          'content': current,
        };
        notifyListeners();
      }

      if (!received) {
        _chatHistory[assistantIndex] = {
          'role': 'assistant',
          'content': 'I could not generate a response. Please try again.',
        };
      }
    } catch (e) {
      debugPrint('AIAssistantProvider.sendMessage error: $e');
      // Cause-specific message — a timeout, a dead backend, and an expired
      // session must not all read the same.
      final errorContent = describeChatError(e);
      // If the stream started but failed before emitting any token, reuse the
      // empty placeholder bubble rather than leaving it dangling above the error.
      final last = _chatHistory.isNotEmpty ? _chatHistory.last : null;
      if (last != null &&
          last['role'] == 'assistant' &&
          (last['content'] as String? ?? '').isEmpty) {
        _chatHistory[_chatHistory.length - 1] = {
          'role': 'assistant',
          'content': errorContent,
          'isError': true,
        };
      } else {
        _chatHistory.add({
          'role': 'assistant',
          'content': errorContent,
          'isError': true,
        });
      }
    }

    _isGeneratingResponse = false;
    notifyListeners();
  }

  bool _isNavigationIntent(String lower) {
    // Distinctive commands are safe to match anywhere in the message.
    if (lower.contains('go to ') ||
        lower.contains('navigate to ') ||
        lower.contains('take me to ')) {
      return true;
    }
    // "open"/"show" only count at the start — otherwise questions like
    // "how many open orders do I have?" get mistaken for navigation.
    return lower.startsWith('open ') ||
        lower.startsWith('show me the ') ||
        lower.startsWith('show me my ') ||
        lower.startsWith('switch to ') ||
        lower.startsWith('jump to ');
  }

  void _handleNavigationIntent(String lower) {
    String page = 'dashboard';
    String reply = 'Opening that screen now.';

    if (lower.contains('inventory') || lower.contains('stock')) {
      page = 'inventory';
      reply = 'Opening the Inventory screen.';
    } else if (lower.contains('menu') || lower.contains('dish')) {
      page = 'menu';
      reply = 'Navigating to the Menu screen.';
    } else if (lower.contains('report') ||
        lower.contains('analytics') ||
        lower.contains('chart')) {
      page = 'reports';
      reply = 'Opening the Analytics Dashboard.';
    } else if (lower.contains('pos') || lower.contains('order')) {
      page = 'orders';
      reply = 'Navigating to the POS / Orders screen.';
    } else if (lower.contains('finance') || lower.contains('expense')) {
      page = 'finance';
      reply = 'Opening the Finance screen.';
    } else if (lower.contains('staff') || lower.contains('employee')) {
      page = 'staff';
      reply = 'Opening Staff Management.';
    } else if (lower.contains('dashboard') || lower.contains('home')) {
      page = 'dashboard';
      reply = 'Navigating to the Dashboard.';
    }

    _navigationController.add(page);
    _chatHistory.add({'role': 'assistant', 'content': reply});
  }

  void clearChat() {
    _chatHistory.clear();
    notifyListeners();
  }
}
