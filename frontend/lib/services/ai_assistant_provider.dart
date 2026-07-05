import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/insight.dart';
import 'firestore_insights_service.dart';
import 'intent_detector.dart';
import 'api_service.dart';

class AIAssistantProvider extends ChangeNotifier {
  // UI Panel States
  bool _isExpanded = false;
  bool get isExpanded => _isExpanded;

  Offset? _buttonPosition;
  Offset? get buttonPosition => _buttonPosition;

  // Popup state (for quick alerts anchored to the button)
  bool _showPopup = false;
  bool get showPopup => _showPopup;
  String? _popupContent;
  String? get popupContent => _popupContent;

  // Active Screen Tracker
  String _activePage = 'dashboard'; // 'dashboard', 'inventory', 'orders', 'menu', 'reports', 'general'
  String get activePage => _activePage;

  List<Insight> _activeInsights = [];
  List<Insight> get activeInsights => _activeInsights;

  bool _loadingInsights = false;
  bool get loadingInsights => _loadingInsights;

  // Business Summary State
  Map<String, dynamic> _businessSummary = {};
  Map<String, dynamic> get businessSummary => _businessSummary;

  bool _loadingSummary = false;
  bool get loadingSummary => _loadingSummary;

  // Notification / Badge State
  bool _hasNewImportantInsight = false;
  bool get hasNewImportantInsight => _hasNewImportantInsight;

  // Chat Interface State
  final List<Map<String, dynamic>> _chatHistory = [];
  List<Map<String, dynamic>> get chatHistory => _chatHistory;

  bool _isGeneratingResponse = false;
  bool get isGeneratingResponse => _isGeneratingResponse;

  // Navigation Request Stream
  final StreamController<String> _navigationController = StreamController<String>.broadcast();
  Stream<String> get navigationRequests => _navigationController.stream;

  AIAssistantProvider() {
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _loadButtonPosition();
    // Initial fetch of insights & summary
    refreshData();
    // Refresh summary every 2 minutes
    Timer.periodic(const Duration(minutes: 2), (_) {
      refreshData();
    });
  }

  @override
  void dispose() {
    _navigationController.close();
    super.dispose();
  }

  void togglePanel() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _hasNewImportantInsight = false; // Reset notification when panel is opened
    }
    notifyListeners();
  }

  void setPanelExpanded(bool expanded) {
    _isExpanded = expanded;
    if (_isExpanded) {
      _hasNewImportantInsight = false;
    }
    notifyListeners();
  }

  void updateButtonPosition(Offset newPos) {
    _buttonPosition = newPos;
    notifyListeners();
    _saveButtonPosition(newPos);
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
        _buttonPosition = Offset(x, y);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Show a transient popup anchored to the assistant button.
  void displayPopup(String content, {Duration duration = const Duration(seconds: 4)}) {
    _popupContent = content;
    _showPopup = true;
    notifyListeners();

    // Auto-hide after duration
    Future.delayed(duration, () {
      _showPopup = false;
      _popupContent = null;
      notifyListeners();
    });
  }

  /// Sets the active page/tab and automatically fetches corresponding passive insights
  Future<void> setActivePage(String pageName) async {
    if (_activePage == pageName) return;
    _activePage = pageName;
    notifyListeners();
    await _loadPageInsights();
  }

  /// Refreshes all metrics and active page insights
  Future<void> refreshData() async {
    await Future.wait([
      _loadPageInsights(),
      _loadBusinessSummary(),
    ]);
  }

  Future<void> _loadBusinessSummary() async {
    _loadingSummary = true;
    notifyListeners();

    try {
      _businessSummary = await FirestoreInsightsService.fetchBusinessSummary();
      // If there are low stock items and the panel is closed, show a quick popup
      try {
        final low = (_businessSummary['lowStockCount'] as int?) ?? 0;
        if (low > 0 && !_isExpanded) {
          final names = (_businessSummary['lowStockNames'] as List?)?.take(3).join(', ') ?? '';
          displayPopup('Low stock: $names (${low.toString()})');
        }
      } catch (_) {}
    } catch (_) {}

    _loadingSummary = false;
    notifyListeners();
  }

  Future<void> _loadPageInsights() async {
    _loadingInsights = true;
    notifyListeners();

    try {
      List<Map<String, dynamic>> rawInsights = [];
      switch (_activePage) {
        case 'dashboard':
          rawInsights = await FirestoreInsightsService.getDashboardInsights();
          break;
        case 'inventory':
          rawInsights = await FirestoreInsightsService.getInventoryInsights();
          break;
        case 'orders':
          rawInsights = await FirestoreInsightsService.getOrdersInsights();
          break;
        case 'menu':
          rawInsights = await FirestoreInsightsService.getMenuInsights();
          break;
        case 'reports':
          rawInsights = await FirestoreInsightsService.getReportsInsights();
          break;
        case 'finance':
          rawInsights = await FirestoreInsightsService.getFinanceInsights();
          break;
        default:
          rawInsights = [];
      }

      _activeInsights = rawInsights.map((map) {
        return Insight(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: map['title'] ?? 'Insight',
          message: map['message'] ?? '',
          page: _activePage,
          isImportant: map['isImportant'] ?? false,
          icon: map['icon'] ?? Icons.info_outline,
          color: map['color'] ?? Colors.blue,
          createdAt: DateTime.now(),
        );
      }).toList();

      // Check if any new insight is important and show popup
      if (_activeInsights.isNotEmpty && !_isExpanded) {
        final importantInsights = _activeInsights.where((i) => i.isImportant).toList();
        
        if (importantInsights.isNotEmpty) {
          _hasNewImportantInsight = true;
          // Show transient popup for important insights (inventory, orders, etc.)
          displayPopup(importantInsights.first.message);
        } else {
          // Show AI-Summary popup for all other pages with their top insight
          final topInsight = _activeInsights.first;
          displayPopup(topInsight.message, duration: const Duration(seconds: 5));
        }
      }
    } catch (_) {}

    _loadingInsights = false;
    notifyListeners();
  }

  /// Sends user chat message, performs intent detection, constructs client-side context (RAG) and calls Ollama
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add user message to chat history
    _chatHistory.add({
      'role': 'user',
      'content': text,
    });
    _isGeneratingResponse = true;
    notifyListeners();

    try {
      // 1. Local Intent Detection
      final intent = IntentDetector.detectIntent(text);
      debugPrint('Detected Intent: $intent');

      // 2. Handle Navigation Intent directly
      if (intent == 'navigation') {
        _isGeneratingResponse = false;
        
        // Find best matching tab
        String pageToNavigate = 'dashboard';
        String reply = 'Sure! Opening that for you now.';
        
        final lowerText = text.toLowerCase();
        if (lowerText.contains('inventory') || lowerText.contains('stock')) {
          pageToNavigate = 'inventory';
          reply = 'Opening the Inventory tab now.';
        } else if (lowerText.contains('menu') || lowerText.contains('dish')) {
          pageToNavigate = 'menu';
          reply = 'Navigating to the Menu screen.';
        } else if (lowerText.contains('report') || lowerText.contains('analytics') || lowerText.contains('chart')) {
          pageToNavigate = 'reports';
          reply = 'Opening the Analytics Dashboard for you.';
        } else if (lowerText.contains('pos') || lowerText.contains('order')) {
          pageToNavigate = 'orders';
          reply = 'Navigating to the Orders / POS screen.';
        } else if (lowerText.contains('finance') || lowerText.contains('expense')) {
          pageToNavigate = 'finance';
          reply = 'Opening the Finance and Expenses screen.';
        } else if (lowerText.contains('staff') || lowerText.contains('employee')) {
          pageToNavigate = 'staff';
          reply = 'Opening the Staff Management screen.';
        } else {
          reply = 'Which page would you like to navigate to? (Dashboard, Menu, Inventory, Analytics, Finance, Staff)';
        }

        if (pageToNavigate != 'dashboard' || lowerText.contains('dashboard') || lowerText.contains('home')) {
          _navigationController.add(pageToNavigate);
        }

        _chatHistory.add({
          'role': 'assistant',
          'content': reply,
        });
        notifyListeners();
        return;
      }

      // 3. Query Firebase & Build Context for RAG
      // We load the summary to construct up-to-date context
      await _loadBusinessSummary();
      final summary = _businessSummary;

      String contextString = '';
      if (intent == 'inventory') {
        contextString = 'Low Stock Count: ${summary['lowStockCount']}, Low Stock Ingredients: ${(summary['lowStockNames'] as List?)?.join(', ') ?? 'None'}, Total Inventory items tracked: ${summary['totalInventoryCount']}.';
      } else if (intent == 'sales') {
        contextString = 'Today\'s Revenue: ₱${(summary['todayRevenue'] as double?)?.toStringAsFixed(2)}, Completed Orders Count Today: ${summary['todayOrdersCount']}, Best Selling Item Today: ${summary['topSeller']}.';
      } else if (intent == 'orders') {
        contextString = 'Active Pending Orders in Queue: ${summary['pendingOrdersCount']}, Completed Orders Today: ${summary['todayOrdersCount']}, Best Selling Item: ${summary['topSeller']}.';
      } else {
        // General query - provide overall business status context
        contextString = 'Today\'s Revenue: ₱${(summary['todayRevenue'] as double?)?.toStringAsFixed(2)}, Completed Orders: ${summary['todayOrdersCount']}, Active Pending Orders: ${summary['pendingOrdersCount']}, Low Stock Ingredients Count: ${summary['lowStockCount']}, Top Selling Item: ${summary['topSeller']}.';
      }

      // 4. Send Message + Context to API
      final List<Map<String, dynamic>> apiHistoryFormat = _chatHistory.map((m) {
        return {
          'role': m['role'],
          'content': m['content'],
        };
      }).toList().cast<Map<String, dynamic>>();

      final apiResult = await ApiService.sendChatMessage(
        message: text,
        history: apiHistoryFormat.sublist(0, apiHistoryFormat.length - 1), // exclude current message
        context: contextString,
      );

      final reply = apiResult['response'] ?? 'I could not generate a response. Please try again.';

      _chatHistory.add({
        'role': 'assistant',
        'content': reply,
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
      _chatHistory.add({
        'role': 'assistant',
        'content': 'Sorry, I encountered an error communicating with the server: $e',
      });
    }

    _isGeneratingResponse = false;
    notifyListeners();
  }

  void clearChat() {
    _chatHistory.clear();
    notifyListeners();
  }
}
