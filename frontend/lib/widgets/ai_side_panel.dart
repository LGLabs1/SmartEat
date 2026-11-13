import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';
import 'floating_ai_button.dart';
import 'sage_markdown.dart';
import 'sage_shared_views.dart';

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

  Future<void> _loadUserDisplayName() async {
    final name = await loadSageDisplayName(context);
    if (name.isNotEmpty && mounted) {
      setState(() => _displayName = name);
    }
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

    return DefaultTabController(
      key: ValueKey(provider.activeSageTab),
      length: 3,
      initialIndex: provider.activeSageTab,
      child: Container(
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
                    TabBar(
                      onTap: provider.setActiveSageTab,
                      indicatorColor: Colors.blueAccent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: const [
                        Tab(text: 'Sage'),
                        Tab(text: 'Summary'),
                        Tab(text: 'History'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          // Sage chat tab: SelectionArea lets the whole
                          // conversation be drag-selected in one gesture.
                          SelectionArea(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              cacheExtent: 4000,
                              children: [
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
                                        'Sage Business Assistant',
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
                          // Summary tab: latest briefing report + metrics.
                          SelectionArea(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              cacheExtent: 4000,
                              children: [
                                if (provider.latestBriefing != null) ...[
                                  buildLatestBriefingCard(
                                      provider.latestBriefing!),
                                  const SizedBox(height: 16),
                                ],
                                buildSummarySection(provider),
                                const SizedBox(height: 16),
                                buildInsightsSection(provider),
                              ],
                            ),
                          ),
                          // History tab: dedicated report history only.
                          ListView(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            children:
                                buildBriefingHistoryContent(context, provider),
                          ),
                        ],
                      ),
                    ),
                    if (provider.activeSageTab == 0) _buildInputBar(provider),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AIAssistantProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 4, 8),
      child: Row(
        children: [
          SageAvatar(
            size: 40,
            showBadge: provider.hasNewImportantInsight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sageGreeting()},',
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
          ),
          IconButton(
            onPressed: () => provider.setFullScreen(true),
            icon: const Icon(Icons.open_in_full,
                color: Colors.white70, size: 20),
            tooltip: 'Expand to full screen',
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
              'No messages yet — I\'m all ears! 🌿 Ask me how sales are '
              'trending, what\'s running low, or which dishes are flying off '
              'the shelf.',
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

    // While streaming, the reply bubble grows in place, so only show the
    // "thinking" placeholder until the first token actually lands.
    final lastMsg = history.isNotEmpty ? history.last : null;
    final streamingHasContent = lastMsg != null &&
        lastMsg['role'] == 'assistant' &&
        (lastMsg['content'] as String? ?? '').isNotEmpty;
    final showThinking =
        provider.isGeneratingResponse && !streamingHasContent;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length + (showThinking ? 1 : 0),
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
                  'Sage is thinking...',
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

        // The provider parks an empty assistant bubble in history while
        // waiting for the first token; the thinking bubble above stands in
        // for it, so skip it instead of rendering a second empty bubble.
        if (!isUser &&
            showThinking &&
            index == history.length - 1 &&
            (msg['content'] as String? ?? '').isEmpty) {
          return const SizedBox.shrink();
        }

        if (isUser) {
          return _buildUserBubble(msg['content'] ?? '');
        } else {
          return _buildAssistantBubble(
            child: SageMarkdown(
              (msg['content'] ?? '').toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.4,
              ),
              highlightColor: Colors.blueAccent.shade100,
              bulletColor: Colors.blueAccent.shade100,
              calloutBackground: Colors.blueAccent.withValues(alpha: 0.14),
              calloutBorder: Colors.blueAccent.shade100,
              codeColor: Colors.lightBlueAccent.shade100,
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
                  hintText: 'Ask Sage...',
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
