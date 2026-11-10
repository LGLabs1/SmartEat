import 'package:flutter/material.dart';
import 'dart:async';
import 'api_service.dart';
import 'business_context_builder.dart';
import 'chat_errors.dart';
import 'intent_detector.dart';
import 'smart_snapshot_builder.dart';

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final bool cached;

  /// Error/offline notices — shown to the user but never sent back to the
  /// model as conversation history (they bloat the prompt and confuse it).
  final bool isError;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.cached = false,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

class ChatProvider extends ChangeNotifier {
  /// Why Sage is offline: 'backend_down' | 'backend_slow' | 'no_network' |
  /// 'invalid_key' | 'not_configured' | 'quota' | 'slow' | 'ai_down' |
  /// 'demo_disabled' | 'unknown'. Null while online. Used so the pre-send
  /// guard reports the actual cause instead of a generic apology.
  String? _offlineReason;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _sageOnline = false;
  bool _isCheckingStatus = true;
  String? _lastError;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get sageOnline => _sageOnline;
  bool get isCheckingStatus => _isCheckingStatus;
  String? get lastError => _lastError;
  String? get offlineReason => _offlineReason;

  ChatProvider() {
    _addWelcomeMessage();
    checkStatus();
  }

  void _addWelcomeMessage() {
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            "Hey, I'm Sage 🌿 — great to have you here!\n\n"
            "I keep an eye on your numbers so you don't have to. Ask me "
            "anything — for example:\n\n"
            "\"How did we do this week?\"\n"
            "\"What's about to run out?\"\n"
            "\"Which dishes aren't selling?\"\n\n"
            "What's on your mind today?",
        timestamp: DateTime.now(),
      ));
    }
  }

  // OPTIMIZATION: Check Sage status with retry
  Future<void> checkStatus({
    int retries = 2,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _isCheckingStatus = true;
    notifyListeners();

    int attempts = retries;
    while (attempts > 0) {
      try {
        final status = await ApiService.getChatbotStatus().timeout(timeout);
        if (status['online'] == true || status['ollamaRunning'] == true) {
          _sageOnline = true;
          _offlineReason = null;
          _lastError = null;
        } else if (status['demoDisabled'] == true ||
            status['status'] == 'disabled') {
          _sageOnline = false;
          _offlineReason = 'demo_disabled';
          _lastError = status['message']?.toString();
        } else {
          _sageOnline = false;
          // The backend answered but the AI side is down — distinguish a bad
          // key, missing key, quota, or slowness from a generic failure.
          final reason =
              (status['error'] ?? status['code'] ?? status['status'] ?? '')
                  .toString();
          switch (reason) {
            case 'gemini_invalid_key':
              _offlineReason = 'invalid_key';
              break;
            case 'gemini_not_configured':
              _offlineReason = 'not_configured';
              break;
            case 'gemini_quota':
              _offlineReason = 'quota';
              break;
            case 'ai_timeout':
              _offlineReason = 'slow';
              break;
            default:
              _offlineReason = 'ai_down';
          }
          _lastError =
              status['message']?.toString() ?? 'Sage\'s AI service is offline.';
        }
        break;
      } catch (e) {
        attempts--;
        if (attempts == 0) {
          _sageOnline = false;
          _offlineReason = _classifyStatusFailure(e);
          _lastError = _offlineReason;
          print('Sage status check failed: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    _isCheckingStatus = false;
    notifyListeners();
  }

  /// Decides what actually went wrong when the status endpoint could not be
  /// reached, so the offline message names the real cause.
  static String _classifyStatusFailure(Object error) {
    if (error is TimeoutException) return 'backend_slow';
    final text = error.toString().toLowerCase();
    if (text.contains('refused')) return 'backend_down';
    if (text.contains('failed host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename')) {
      return 'no_network';
    }
    return 'unknown';
  }

  /// The offline message matching the recorded cause.
  String _offlineMessage() {
    switch (_offlineReason) {
      case 'backend_down':
        return '📡 Oh no — I can\'t reach the SmartEat backend, so I\'m '
            'running blind right now.\n\nCould you start it for me? '
            '(`npm start` in the backend folder). I\'ll be right here '
            'when it\'s back 💚';
      case 'backend_slow':
        return '⏳ The backend is taking a moment to wake up — it may still '
            'be starting or a bit busy.\n\nGive it a few seconds and send '
            'your question again?';
      case 'no_network':
        return '📡 I think you\'re offline — I can\'t reach the backend from '
            'here.\n\nCheck your Wi-Fi and try me again in a second.';
      case 'invalid_key':
        return '🔑 Sage\'s AI (Gemini) rejected the server\'s API key.\n\n'
            'Ask whoever runs the backend to set a valid GEMINI_API_KEY — '
            'everything else in SmartEat still works fine.';
      case 'not_configured':
        return '🔧 Sage\'s AI (Gemini) isn\'t configured on the backend '
            'yet.\n\nA GEMINI_API_KEY needs to be set there. Everything '
            'else in SmartEat still works fine.';
      case 'quota':
        return '🚦 Sage\'s AI hit its rate/quota limit just now.\n\n'
            'It usually resets on its own shortly — try me again in a bit.';
      case 'slow':
        return '⏱️ Sage\'s AI is being slow to answer right now.\n\n'
            'Hang tight a moment and try again?';
      case 'ai_down':
        return '⚠️ Sage\'s AI service isn\'t reachable at the moment.\n\n'
            'It\'ll likely be back shortly — try me again in a bit ✨';
      case 'demo_disabled':
        return '🌿 Sage is disabled in this demo.\n\nAnalytics, inventory, '
            'finance, and other SmartEat features remain available.';
      default:
        return '⚠️ I couldn\'t check my own status just now.\n\nMake sure '
            'the backend and its AI (Gemini) are configured, then try '
            'again — I\'ll re-check automatically.';
    }
  }

  // OPTIMIZATION: Send message with better error handling and timeouts
  Future<void> sendMessage(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    // The status check runs once at startup — if Sage looked offline then
    // (backend still booting, AI service blip), never give the user a
    // permanent wall of errors. Re-check quickly before giving up.
    if (!_sageOnline) {
      await checkStatus(
          retries: 1, timeout: const Duration(seconds: 2));
      if (!_sageOnline) {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: _offlineMessage(),
          timestamp: DateTime.now(),
          isError: true,
        ));
        notifyListeners();
        return;
      }
    }

    // Greetings / thanks / identity questions get an instant canned reply —
    // no intent detection, no data fetch, no AI round-trip.
    final smallTalk = IntentDetector.smallTalkReply(trimmedText);
    if (smallTalk != null) {
      _messages.add(ChatMessage(role: 'user', content: trimmedText, timestamp: DateTime.now()));
      _messages.add(ChatMessage(
        role: 'assistant',
        content: smallTalk,
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
      // OPTIMIZATION: Send only recent history (last 5 exchanges) for faster
      // processing — and never re-send our own error notices to the model.
      final allMessages = _messages
          .where((m) => m.role != 'system' && !m.isError)
          .toList();
      final historyStartIdx =
          allMessages.length > 10 ? allMessages.length - 10 : 0;
      final history = allMessages.sublist(historyStartIdx);
      final historyJson = history.map((m) => m.toJson()).toList();

      print('📤 Sending message (history: ${history.length} messages)...');

      // Detect intent → build only the relevant snapshot slice.
      // The AI never reads Firestore; Firestore → AnalyticsService → snapshot → AI.
      String contextString = '';
      try {
        final analysis = IntentDetector.analyze(trimmedText);
        final intent = analysis.intent;
        print('🎯 Detected intent: ${IntentDetector.intentLabel(intent)} '
            '(concepts: ${analysis.concepts.join(', ')}, '
            'confidence: ${analysis.confidence})');

        if (IntentDetector.needsClarification(trimmedText, analysis)) {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: 'Happy to help — I just need a tiny bit more to go on! '
                'For example: \u201cHow were sales this week?\u201d, '
                '\u201cWhat\u2019s running low?\u201d, or '
                '\u201cHow\u2019s my profit looking?\u201d',
            timestamp: DateTime.now(),
          ));
          return;
        }

        if (intent != IntentDetector.intentNavigation) {
          final ctx = await BusinessContextBuilder.build();
          contextString = SmartSnapshotBuilder.build(
            ctx,
            intent,
            analysis: analysis,
          );
          print('✓ Smart snapshot built'
              ' [${IntentDetector.intentLabel(intent)}]'
              ' (${contextString.length} chars)');
          // Debug: print snapshot so values can be verified against dashboard
          debugPrint(
              '--- SMART SNAPSHOT BEGIN ---\n$contextString--- SMART SNAPSHOT END ---');
        } else {
          print('ℹ️ Intent is $intent — no snapshot needed.');
        }
      } catch (e) {
        print('⚠️ Snapshot build failed, sending without context: $e');
      }

      final response = await ApiService.sendChatMessage(
        message: trimmedText,
        history: historyJson,
        context: contextString.isNotEmpty ? contextString : null,
      ).timeout(
        const Duration(seconds: 125),
        onTimeout: () =>
            throw TimeoutException('AI response took too long (>125s)'),
      );

      final assistantContent = response['response'] ??
          'Hmm, that came back empty — want to try that again?';
      final wasCached = response['cached'] == true;

      _messages.add(ChatMessage(
        role: 'assistant',
        content: wasCached ? '⚡ $assistantContent' : assistantContent,
        timestamp: DateTime.now(),
        cached: wasCached,
      ));

      if (wasCached) {
        print('✓ Got cached response');
      }
    } catch (e) {
      _lastError = '${e.runtimeType}';
      print('❌ Chat error: $e');
      _messages.add(ChatMessage(
        role: 'assistant',
        content: describeChatError(e),
        timestamp: DateTime.now(),
        isError: true,
      ));
      // Connection-type failures may be a blip (backend restarting, AI
      // service recovering) — refresh status in the background so Sage
      // recovers on its own instead of serving stale "offline" state.
      if (e is ChatApiException &&
          (e.code == 'gemini_error' ||
              e.code == 'gemini_unreachable' ||
              e.code == 'network_unavailable' ||
              e.statusCode == 503)) {
        checkStatus(retries: 1, timeout: const Duration(seconds: 2));
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // OPTIMIZATION: Get insights with better error messages
  Future<void> getAIInsights() async {
    if (!_sageOnline) {
      await checkStatus(
          retries: 1, timeout: const Duration(seconds: 2));
      if (!_sageOnline) {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: _offlineMessage(),
          timestamp: DateTime.now(),
          isError: true,
        ));
        notifyListeners();
        return;
      }
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
    } on TimeoutException catch (_) {
      _lastError = 'insights_timeout';
      _messages.add(ChatMessage(
        role: 'assistant',
        content:
            '⏱️ The insights request timed out — the backend or AI did not '
            'answer in time.\n\nTry again in a moment; if it keeps happening, '
            'check the backend logs.',
        timestamp: DateTime.now(),
        isError: true,
      ));
    } catch (e) {
      _lastError = '${e.runtimeType}';
      print('❌ Insights error: $e');

      _messages.add(ChatMessage(
        role: 'assistant',
        content: '❌ Could not fetch insights.\n\n'
            '${describeChatError(e)}',
        timestamp: DateTime.now(),
        isError: true,
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
