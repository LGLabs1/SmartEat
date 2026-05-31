import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'All';

  final Map<String, List<String>> _categorySuggestions = {
    'All': [
      'How do I add a menu item?',
      'Show me sales insights',
      'Tips for inventory management',
    ],
    '💡 Help': [
      'How do I add a menu item?',
      'How do I process a refund?',
      'How do I manage staff profiles?',
    ],
    '📈 Insights': [
      'Show me sales insights',
      'What are the top selling items today?',
      'Explain today\'s revenue analytics',
    ],
    '📦 Inventory': [
      'Tips for inventory management',
      'Show low stock items',
      'How do I update inventory stock?',
    ],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().addListener(_scrollToBottom);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    // Safely remove listener using read since we don't watch in dispose
    context.read<ChatProvider>().removeListener(_scrollToBottom);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onSuggestionTap(String text) {
    context.read<ChatProvider>().sendMessage(text);
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    context.read<ChatProvider>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        leadingWidth: 44,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.smart_toy_outlined, color: primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SmartBot',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chatProvider.isCheckingStatus
                            ? Colors.orange
                            : chatProvider.ollamaOnline
                                ? Colors.green.shade500
                                : Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chatProvider.isCheckingStatus
                          ? 'Checking...'
                          : chatProvider.ollamaOnline
                              ? 'Online'
                              : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          _ActionChip(
            icon: Icons.delete_outline,
            label: 'Clear',
            onTap: chatProvider.isLoading ? null : () => chatProvider.clearHistory(),
          ),
          _ActionChip(
            icon: Icons.auto_graph_outlined,
            label: 'Insights',
            onTap: chatProvider.isLoading ? null : () => chatProvider.getAIInsights(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Subtle offline notice
          if (!chatProvider.ollamaOnline && !chatProvider.isCheckingStatus)
            Container(
              width: double.infinity,
              color: Colors.amber.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI is offline. Run: ollama serve',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: chatProvider.messages.length,
              itemBuilder: (context, index) {
                final message = chatProvider.messages[index];
                final isUser = message.role == 'user';
                final isFirst =
                    index == 0 || chatProvider.messages[index - 1].role != message.role;
                final timeStr = DateFormat('h:mm a').format(message.timestamp);

                return _MessageBubble(
                  content: message.content,
                  isUser: isUser,
                  isFirst: isFirst,
                  time: timeStr,
                );
              },
            ),
          ),

          // Category Selector
          if (!chatProvider.isLoading &&
              chatProvider.messages.isNotEmpty &&
              chatProvider.messages.last.role == 'assistant')
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categorySuggestions.keys.map((category) {
                    final isSelected = _selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          category,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: primary,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: isSelected ? primary : Colors.grey.shade200,
                        ),
                        checkmarkColor: Colors.white,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedCategory = category;
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Quick suggestions
          if (!chatProvider.isLoading &&
              chatProvider.messages.isNotEmpty &&
              chatProvider.messages.last.role == 'assistant')
            _QuickSuggestions(
              suggestions: _categorySuggestions[_selectedCategory] ?? [],
              onTap: _onSuggestionTap,
            ),

          // Loading indicator
          if (chatProvider.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TypingDots(color: primary),
                        const SizedBox(width: 8),
                        Text(
                          'SmartBot is thinking',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Input area
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Ask SmartBot...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, size: 18),
                      color: Colors.white,
                      onPressed: chatProvider.isLoading ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isFirst;
  final String time;

  const _MessageBubble({
    required this.content,
    required this.isUser,
    required this.isFirst,
    required this.time,
  });

  Widget _buildParsedContent(BuildContext context, String content, TextStyle baseStyle) {
    final primary = Theme.of(context).colorScheme.primary;
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
    int lastMatchEnd = 0;

    for (final Match match in regExp.allMatches(content)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: content.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle.copyWith(
          fontWeight: FontWeight.bold,
          color: isUser ? Colors.white : primary,
        ),
      ));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser && isFirst)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.smart_toy_outlined, color: primary, size: 16),
            )
          else if (!isUser)
            const SizedBox(width: 36),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? primary : Colors.white,
                    borderRadius: BorderRadius.circular(14).copyWith(
                      bottomRight: isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(14),
                      bottomLeft: !isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(14),
                    ),
                    border: !isUser
                        ? Border.all(color: Colors.grey.shade200)
                        : null,
                  ),
                  child: _buildParsedContent(
                    context,
                    content,
                    TextStyle(
                      color: isUser ? Colors.white : Colors.grey.shade800,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!isUser) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.copy_outlined,
                          size: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isUser && isFirst)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.person_outline,
                  color: Colors.grey.shade600, size: 16),
            )
          else if (isUser)
            const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _QuickSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _QuickSuggestions({
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: suggestions.map((text) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(Icons.flash_on, size: 14, color: primary),
                label: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.grey.shade200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => onTap(text),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final scale =
                0.5 + (value < 0.5 ? value * 2 : (1 - value) * 2) * 0.5;
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.4 + scale * 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
