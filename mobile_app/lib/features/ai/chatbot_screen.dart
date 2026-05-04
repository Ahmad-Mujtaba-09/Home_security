import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/api_service.dart';
import '../../data/models.dart';
import '../../data/supabase_service.dart';

/// WhatsApp-style First Aid Chatbot screen with session persistence.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});
  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _messages.add(const _ChatMessage(
      role: 'assistant',
      text: 'Hello! I\'m your First Aid assistant. '
          'Describe any emergency or health concern and I\'ll provide guidance.',
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
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

  void _newChat() {
    setState(() {
      _sessionId = null;
      _messages.clear();
      _messages.add(const _ChatMessage(
        role: 'assistant',
        text: 'Starting a new conversation. How can I help?',
      ));
    });
  }

  Future<void> _loadSession(ChatSession session) async {
    setState(() {
      _sessionId = session.sessionId;
      _messages.clear();
      _messages.add(const _ChatMessage(role: 'assistant', text: 'Loading messages…'));
    });

    final msgs = await ApiService.listChatMessages(session.sessionId);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      for (final m in msgs) {
        _messages.add(_ChatMessage(
          role: m.sender == 'user' ? 'user' : 'assistant',
          text: m.messageText,
        ));
      }
      if (_messages.isEmpty) {
        _messages.add(_ChatMessage(
          role: 'assistant',
          text: 'Session: ${session.title ?? 'Untitled'}',
        ));
      }
    });
    _scrollToBottom();
  }

  void _openSessionDrawer() {
    final userId = context.read<SupabaseService>().userId;
    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionDrawer(
        userId: userId,
        currentSessionId: _sessionId,
        onSelect: (s) {
          Navigator.pop(context);
          _loadSession(s);
        },
        onNewChat: () {
          Navigator.pop(context);
          _newChat();
        },
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final userId = context.read<SupabaseService>().userId ?? 'anonymous';

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final result = await ApiService.sendChatMessage(
        message: text,
        userId: userId,
        sessionId: _sessionId,
      );

      if (result.sessionId != null) _sessionId = result.sessionId;

      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', text: result.reply));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            text: 'Something went wrong. Please try again.',
          ));
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.greenGradient,
                  ),
                  child: const Icon(Icons.local_hospital_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('First Aid Assistant',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        _sessionId != null ? 'Session active' : 'New session',
                        style: TextStyle(fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined, size: 22),
                  tooltip: 'New chat',
                  onPressed: _newChat,
                ),
                IconButton(
                  icon: const Icon(Icons.history, size: 22),
                  tooltip: 'Chat history',
                  onPressed: _openSessionDrawer,
                ),
              ],
            ),
          ),
          Divider(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            height: 1,
          ),

          // ── Messages list ─────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
            ),
          ),

          // ── Input ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Describe your emergency…',
                      filled: true,
                      fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.primaryGradient,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 20),
                          onPressed: _send,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat data & bubble ──────────────────────────────────────────────────────

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const _ChatMessage({required this.role, required this.text});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [AppColors.accentPrimary, Color(0xFF5A54E6)],
                )
              : null,
          color: isUser
              ? null
              : (isDark ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Session history drawer ──────────────────────────────────────────────────

class _SessionDrawer extends StatefulWidget {
  final String userId;
  final String? currentSessionId;
  final void Function(ChatSession) onSelect;
  final VoidCallback onNewChat;

  const _SessionDrawer({
    required this.userId,
    this.currentSessionId,
    required this.onSelect,
    required this.onNewChat,
  });

  @override
  State<_SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<_SessionDrawer> {
  List<ChatSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.listChatSessions(widget.userId);
    if (mounted) setState(() { _sessions = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Text('Chat History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.onNewChat,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New chat'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentPrimary),
                ),
              ],
            ),
          ),
          Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? Center(child: Text('No past sessions',
                        style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _sessions.length,
                        itemBuilder: (_, i) {
                          final s = _sessions[i];
                          final isCurrent =
                              s.sessionId == widget.currentSessionId;
                          return ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            selected: isCurrent,
                            selectedTileColor:
                                AppColors.accentPrimary.withValues(alpha: 0.1),
                            leading: Icon(
                              isCurrent
                                  ? Icons.chat
                                  : Icons.chat_bubble_outline,
                              size: 20,
                              color: isCurrent
                                  ? AppColors.accentPrimary
                                  : null,
                            ),
                            title: Text(
                              s.title ?? 'Untitled',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            subtitle: Text(
                              DateFormat('MMM d, h:mm a')
                                  .format(s.startedAt.toLocal()),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.black26,
                              ),
                            ),
                            onTap: () => widget.onSelect(s),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
