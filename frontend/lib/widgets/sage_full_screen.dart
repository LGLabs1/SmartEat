import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';
import 'floating_ai_button.dart';
import 'sage_markdown.dart';
import 'sage_shared_views.dart';

/// Immersive full-screen Sage workspace.
///
/// Shares [AIAssistantProvider] with the side panel and the floating button,
/// so chat history, briefings and insights carry across all three modes.
/// Minimizing returns to the side panel; closing returns to the floating
/// button; the Escape key minimizes.
class SageFullScreen extends StatefulWidget {
  const SageFullScreen({super.key});

  @override
  State<SageFullScreen> createState() => _SageFullScreenState();
}

class _SageFullScreenState extends State<SageFullScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _keyboardFocusNode = FocusNode();
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
    _keyboardFocusNode.dispose();
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
    final width = MediaQuery.of(context).size.width;

    if (provider.isGeneratingResponse || provider.chatHistory.isNotEmpty) {
      _scrollToBottom();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => provider.setFullScreen(false),
      },
      child: Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        child: Material(
          color: const Color(0xFF0B1220),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(provider),
                Divider(
                  color: Colors.white.withValues(alpha: 0.08),
                  height: 1,
                ),
                Expanded(child: _buildBody(provider, width)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AIAssistantProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          SageAvatar(
            size: 44,
            showBadge: provider.hasNewImportantInsight,
          ),
          const SizedBox(width: 12),
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
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => provider.setFullScreen(false),
            icon: const Icon(Icons.close_fullscreen,
                color: Colors.white70, size: 20),
            tooltip: 'Minimize to side panel (Esc)',
          ),
          IconButton(
            onPressed: provider.exitFullScreen,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Close Sage',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AIAssistantProvider provider, double width) {
    // Wide (≥1000px): History | Chat | Summary columns.
    if (width >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 300, child: _buildHistoryPane(provider)),
          _paneDivider(),
          Expanded(child: _buildChatPane(provider)),
          _paneDivider(),
          SizedBox(width: 340, child: _buildSummaryPane(provider)),
        ],
      );
    }
    // Medium (≥680px): Chat | right pane with Summary above History.
    if (width >= 680) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildChatPane(provider)),
          _paneDivider(),
          SizedBox(
            width: (width * 0.42).clamp(300.0, 400.0),
            child: _buildSummaryAndHistoryPane(provider),
          ),
        ],
      );
    }
    // Narrow: tabbed fallback.
    return _buildTabbedBody(provider);
  }

  Widget _paneDivider() =>
      Container(width: 1, color: Colors.white.withValues(alpha: 0.08));

  Widget _paneHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildHistoryPane(AIAssistantProvider provider) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      cacheExtent: 4000,
      children: [
        _paneHeading('REPORT HISTORY'),
        ...buildBriefingHistoryContent(context, provider),
      ],
    );
  }

  Widget _buildSummaryPane(AIAssistantProvider provider) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        cacheExtent: 4000,
        children: [
          _paneHeading('SUMMARY'),
          if (provider.latestBriefing != null) ...[
            buildLatestBriefingCard(provider.latestBriefing!),
            const SizedBox(height: 16),
          ],
          buildSummarySection(provider),
          const SizedBox(height: 16),
          buildInsightsSection(provider),
        ],
      ),
    );
  }

  Widget _buildSummaryAndHistoryPane(AIAssistantProvider provider) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        cacheExtent: 4000,
        children: [
          _paneHeading('SUMMARY'),
          if (provider.latestBriefing != null) ...[
            buildLatestBriefingCard(provider.latestBriefing!),
            const SizedBox(height: 16),
          ],
          buildSummarySection(provider),
          const SizedBox(height: 16),
          buildInsightsSection(provider),
          const SizedBox(height: 24),
          _paneHeading('REPORT HISTORY'),
          ...buildBriefingHistoryContent(context, provider),
        ],
      ),
    );
  }

  Widget _buildTabbedBody(AIAssistantProvider provider) {
    return DefaultTabController(
      key: ValueKey(provider.activeSageTab),
      length: 3,
      initialIndex: provider.activeSageTab,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                _buildChatPane(provider),
                _buildSummaryPane(provider),
                _buildHistoryPane(provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPane(AIAssistantProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SelectionArea(
            child: ListView(
              controller: _chatScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              cacheExtent: 4000,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assistant_outlined,
                        color: Colors.blueAccent.shade100,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Sage Business Assistant',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
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
        ),
        _buildInputBar(provider),
      ],
    );
  }

  Widget _buildChatHistory(AIAssistantProvider provider) {
    final history = provider.chatHistory;

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.03),
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: Colors.white30, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No messages yet — I\'m all ears! 🌿 Ask me how sales are '
              'trending, what\'s running low, or which dishes are flying off '
              'the shelf.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x61FFFFFF),
                fontSize: 13,
                height: 1.5,
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
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Sage is thinking...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
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
                fontSize: 14,
                height: 1.5,
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
              height: 48,
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask Sage...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Colors.blueAccent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: provider.isGeneratingResponse
                    ? null
                    : (v) => _handleSend(provider),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: provider.isGeneratingResponse
                ? null
                : () => _handleSend(provider),
            icon: Icon(
              Icons.send_rounded,
              color: provider.isGeneratingResponse
                  ? Colors.white30
                  : Colors.blueAccent.shade100,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
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
