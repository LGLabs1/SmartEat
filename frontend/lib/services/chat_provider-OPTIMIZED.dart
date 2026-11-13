import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final bool cached;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.cached = false,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _ollamaOnline = false;
  bool _isCheckingStatus = true;
  String? _lastError;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get ollamaOnline => _ollamaOnline;
  bool get isCheckingStatus => _isCheckingStatus;
  String? get lastError => _lastError;

  ChatProvider() {
    _addWelcomeMessage();
    checkStatus();
  }

  void _addWelcomeMessage() {
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            "👋 Hello! I'm Sage, your intelligent business assistant for SmartEat.\n\n"
            "I can assist you with:\n"
            "• Restaurant insights & business analytics\n"
            "• Inventory optimization & order forecasting\n"
            "• Best practices for using SmartEat\n\n"
            "How can I help you optimize your eatery today? Try asking: 'How did my restaurant perform this week?' or 'What are my low stock items?'",
        timestamp: DateTime.now(),
      ));
    }
  }

  // OPTIMIZATION: Check Ollama status with retry
  Future<void> checkStatus() async {
    _isCheckingStatus = true;
    notifyListeners();
    
    int retries = 2;
    while (retries > 0) {
      try {
        final status = await ApiService.getChatbotStatus()
            .timeout(const Duration(seconds: 5));
        _ollamaOnline = status['ollamaRunning'] == true;
        _lastError = null;
        break;
      } catch (e) {
        retries--;
        if (retries == 0) {
          _ollamaOnline = false;
          _lastError = 'Ollama offline. Start it with: ollama serve';
          print('Ollama status check failed: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    _isCheckingStatus = false;
    notifyListeners();
  }

  // OPTIMIZATION: Send message with better error handling and timeouts
  Future<void> sendMessage(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;
    
    if (!_ollamaOnline) {
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Ollama is not running.\n\nPlease start Ollama:\n`ollama serve`\n\nThen try again.',
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    // Add user message
    _messages.add(ChatMessage(
      role: 'user',
      content: trimmedText,
      timestamp: DateTime.now(),
    ));
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      // OPTIMIZATION: Send only recent history (last 5 exchanges) for faster processing
      final allMessages = _messages.where((m) => m.role != 'system').toList();
      final historyStartIdx = allMessages.length > 10
          ? allMessages.length - 10
          : 0;
      final history = allMessages.sublist(historyStartIdx);
      final historyJson = history.map((m) => m.toJson()).toList();

      print('📤 Sending message (history: ${history.length} messages)...');
      
      final response = await ApiService.sendChatMessage(
        message: trimmedText,
        history: historyJson,
      ).timeout(
        const Duration(seconds: 65),
        onTimeout: () => throw TimeoutException('AI response took too long (>65s)'),
      );

      final assistantContent = response['response'] ??
          'I apologize, I could not generate a response.';
      final wasCached = response['cached'] == true;

      _messages.add(ChatMessage(
        role: 'assistant',
        content: wasCached 
            ? '⚡ $assistantContent' 
            : assistantContent,
        timestamp: DateTime.now(),
        cached: wasCached,
      ));
      
      if (wasCached) {
        print('✓ Got cached response');
      }
    } on TimeoutException catch (e) {
      _lastError = e.message ?? 'Request timeout';
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            '⏱️ The request timed out.\n\nThe AI model is responding slowly. Please:\n'
            '1. Check that Ollama is running smoothly\n'
            '2. Try a shorter question\n'
            '3. Wait a moment and try again',
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      _lastError = 'Failed to get response';
      print('❌ Chat error: $e');
      
      if (e.toString().contains('Connection refused')) {
        _messages.add(ChatMessage(
          role: 'assistant',
          content:
              '❌ Backend connection failed.\n\n'
              'Please ensure:\n'
              '1. Backend server is running\n'
              '2. Ollama is started (`ollama serve`)\n'
              '3. Check your network connection',
          timestamp: DateTime.now(),
        ));
      } else {
        _messages.add(ChatMessage(
          role: 'assistant',
          content:
              '❌ Error: ${e.toString().replaceAll('Exception: ', '')}\n\n'
              'Please try again or restart the app.',
          timestamp: DateTime.now(),
        ));
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // OPTIMIZATION: Get insights with better error messages
  Future<void> getAIInsights() async {
    if (!_ollamaOnline) {
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Cannot fetch insights: Ollama is offline.\n\nStart Ollama first: `ollama serve`',
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      print('📊 Fetching AI insights...');
      
      final response = await ApiService.getAIInsights().timeout(
        const Duration(seconds: 65),
        onTimeout: () => throw TimeoutException('Insights request timeout'),
      );
      
      final data = response['data'];
      if (data == null) {
        throw Exception('No data returned');
      }

      final summary = data['aiSummary'] ?? 'No summary available';

      _messages.add(ChatMessage(
        role: 'assistant',
        content: '📊 **Your Performance (Last 7 Days)**\n\n'
            '**Orders:** ${data['totalOrders'] ?? 0}\n'
            '**Revenue:** ₱${(data['totalRevenue'] ?? 0).toStringAsFixed(2)}\n'
            '**Avg/Day:** ${(data['avgDailyOrders'] ?? 0).toStringAsFixed(1)} orders\n'
            '**Active Days:** ${data['activeDays'] ?? 0}\n\n'
            '**AI Analysis:**\n$summary',
        timestamp: DateTime.now(),
      ));
      
      print('✓ Insights loaded successfully');
    } on TimeoutException catch (e) {
      _lastError = 'Insights request timeout';
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            '⏱️ Insights request timed out. Please try again in a moment.',
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      _lastError = 'Failed to fetch insights';
      print('❌ Insights error: $e');
      
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            '❌ Could not fetch insights.\n\n'
            'Error: ${e.toString().replaceAll('Exception: ', '')}\n\n'
            'Please check your connection and try again.',
        timestamp: DateTime.now(),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearHistory() {
    _messages.clear();
    _addWelcomeMessage();
    _lastError = null;
    notifyListeners();
  }
}