import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../data/api_service.dart';

/// WhatsApp-style First Aid Chatbot screen using RAG.
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final reply = await ApiService.getChatResponse(text);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', text: reply));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(const _ChatMessage(
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.greenGradient,
                  ),
                  child: const Icon(Icons.local_hospital_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'First Aid Assistant',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(
                      'Powered by AI',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  color:
                      isDark ? AppColors.darkBorder : AppColors.lightBorder,
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
                      fillColor:
                          isDark ? AppColors.darkCard : AppColors.lightCard,
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
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
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
                  color: isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder),
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
