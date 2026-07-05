import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../services/ai_assistant_provider.dart';
import '../services/auth_provider.dart';
import 'insight_card.dart';

class AISidePanel extends StatefulWidget {
  const AISidePanel({super.key});

  @override
  State<AISidePanel> createState() => _AISidePanelState();
}

class _AISidePanelState extends State<AISidePanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _loadUserDisplayName();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _loadUserDisplayName() async {
    try {
      final auth = context.read<AuthProvider>();
      final profile = await auth.getCurrentUserProfile();
      if (profile != null && mounted) {
        final firstName = (profile['firstName'] ?? profile['name'] ?? '').toString().trim();
        if (firstName.isNotEmpty) {
          setState(() {
            _displayName = firstName;
          });
          return;
        }
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && mounted) {
        setState(() {
          _displayName = user.displayName ?? user.email?.split('@')[0] ?? '';
        });
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AIAssistantProvider>();
    final size = MediaQuery.of(context).size;
    final width = size.width > 420 ? 380.0 : size.width * 0.85;

    if (provider.isGeneratingResponse || provider.chatHistory.isNotEmpty) {
      _scrollToBottom();
    }

    return Container(
      width: width,
      height: size.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(-5, 0),
          ),
        ],
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(provider),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        _buildSummarySection(provider),
                        const SizedBox(height: 16),
                        _buildInsightsSection(provider),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.assistant_outlined,
                                color: Colors.blueAccent.shade100,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'SmartBot AI Assistant',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildChatHistory(provider),
                      ],
                    ),
                  ),
                  _buildInputBar(provider),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AIAssistantProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getGreeting()},',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _displayName.isNotEmpty ? '$_displayName!' : 'Boss!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => provider.setPanelExpanded(false),
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Collapse Assistant',
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(AIAssistantProvider provider) {
    final summary = provider.businessSummary;
    if (provider.loadingSummary && summary.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final double todayRev = (summary['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    final int todayOrders = summary['todayOrdersCount'] as int? ?? 0;
    final int pendingOrders = summary['pendingOrdersCount'] as int? ?? 0;
    final int lowStock = summary['lowStockCount'] as int? ?? 0;
    final String topSeller = summary['topSeller'] as String? ?? 'None';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TODAY\'S SUMMARY',
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          // Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'Revenue',
                  '₱${todayRev.toStringAsFixed(0)}',
                  Icons.monetization_on,
                  Colors.green,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  'Orders',
                  '$todayOrders',
                  Icons.receipt_long,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'Pending',
                  '$pendingOrders',
                  Icons.hourglass_bottom,
                  Colors.orange,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  'Low Stock',
                  '$lowStock',
                  Icons.warning,
                  lowStock > 0 ? Colors.redAccent : Colors.grey,
                ),
              ),
            ],
          ),
          if (topSeller != 'None') ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(color: Colors.white.withOpacity(0.1)),
            ),
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber.shade200, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Best Seller: $topSeller',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsightsSection(AIAssistantProvider provider) {
    if (provider.loadingInsights && provider.activeInsights.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final insights = provider.activeInsights;
    if (insights.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${provider.activePage.toUpperCase()} ALERTS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => provider.refreshData(),
              icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.38), size: 14),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...insights.map((insight) => InsightCard(insight: insight)),
      ],
    );
  }

  Widget _buildChatHistory(AIAssistantProvider provider) {
    final history = provider.chatHistory;

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.03),
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: Colors.white30, size: 32),
            const SizedBox(height: 10),
            const Text(
              'No messages yet. Ask me anything about your menu, inventory levels, sales revenue, or help with navigation!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x61FFFFFF),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length + (provider.isGeneratingResponse ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == history.length) {
          // Loading response bubble
          return _buildAssistantBubble(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SmartBot is thinking...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        }

        final msg = history[index];
        final isUser = msg['role'] == 'user';

        if (isUser) {
          return _buildUserBubble(msg['content'] ?? '');
        } else {
          return _buildAssistantBubble(
            child: Text(
              msg['content'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildUserBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildInputBar(AIAssistantProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ask SmartBot...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: Colors.blueAccent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: provider.isGeneratingResponse ? null : (v) => _handleSend(provider),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: provider.isGeneratingResponse ? null : () => _handleSend(provider),
            icon: Icon(
              Icons.send_rounded,
              color: provider.isGeneratingResponse ? Colors.white30 : Colors.blueAccent.shade100,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSend(AIAssistantProvider provider) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    provider.sendMessage(text);
    _scrollToBottom();
  }
}
