import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// API service that connects to the FastAPI backend.
///
/// Priority for server URL:
/// 1. SharedPreferences (set in-app via Profile → Server URL)
/// 2. .env file (INFERENCE_API_URL / CHATBOT_API_URL)
/// 3. Fallback defaults (localhost for web, 10.0.2.2 for emulator)
class ApiService {
  ApiService._();

  static const _serverUrlKey = 'custom_server_url';

  /// Save a custom server URL (e.g. ngrok URL) from within the app.
  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.trim().isEmpty) {
      await prefs.remove(_serverUrlKey);
    } else {
      // Normalize: remove trailing slash
      await prefs.setString(_serverUrlKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
    }
  }

  /// Get the currently saved custom server URL (empty if not set).
  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? '';
  }

  /// Returns the base HTTP URL for the backend.
  /// Priority: SharedPreferences > .env > default fallback
  static Future<String> _getBaseUrl() async {
    // 1. Check in-app override (SharedPreferences)
    final customUrl = await getServerUrl();
    if (customUrl.isNotEmpty) {
      return customUrl
          .replaceFirst('ws://', 'http://')
          .replaceFirst('wss://', 'https://');
    }

    // 2. Check .env
    final envUrl = (dotenv.env['INFERENCE_API_URL'] ?? '')
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
    if (envUrl.isNotEmpty) return envUrl;

    // 3. Fallback
    return kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
  }

  /// Generate an AI-powered daily summary for the given user.
  static Future<String> getSummary(String userId) async {
    try {
      final baseUrl = await _getBaseUrl();
      final url = Uri.parse('$baseUrl/api/gemini-report')
          .replace(queryParameters: {'user_id': userId});

      final resp = await http.get(url).timeout(
        const Duration(seconds: 30),
      );

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['report'] as String? ??
            'Could not generate a summary right now.';
      }
      return 'Unable to reach the backend (${resp.statusCode}).';
    } catch (e) {
      debugPrint('getSummary error: $e');
      return 'Could not connect to the backend.\n\n'
          'Make sure:\n'
          '• The backend is running (python Engine/main.py)\n'
          '• ${kIsWeb ? "You\'re on localhost" : "Your server URL is correct (check Profile → Server URL)"}\n\n'
          'Error: $e';
    }
  }

  /// Send a chat turn to the First Aid RAG chatbot.
  ///
  /// Pass `sessionId` to continue an existing session, or null to start one.
  /// Returns the reply text, formatted source list, and the (possibly new)
  /// session id assigned by the backend.
  static Future<ChatTurnResult> sendChatMessage({
    required String message,
    required String userId,
    String? sessionId,
    List<Map<String, String>>? history,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'user_id': userId,
          if (sessionId != null) 'session_id': sessionId,
          if (history != null) 'history': history,
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = (body['reply'] as String?) ?? 'No response received.';

        String formatted = reply;
        if (body['sources'] is List) {
          final sources = (body['sources'] as List)
              .map((s) => '📖 ${s['book']} (p.${s['page']})')
              .toSet()
              .join('\n');
          if (sources.isNotEmpty) {
            formatted = '$reply\n\n─── Sources ───\n$sources';
          }
        }
        return ChatTurnResult(
          reply: formatted,
          rawReply: reply,
          sessionId: body['session_id'] as String?,
        );
      }
      return ChatTurnResult(
        reply: 'The assistant is temporarily unavailable (${resp.statusCode}).',
        rawReply: '',
        sessionId: sessionId,
      );
    } catch (e) {
      debugPrint('Chatbot API error: $e');
      return ChatTurnResult(
        reply: 'Could not reach the assistant.\n\n'
            'Make sure:\n'
            '• The backend is running\n'
            '• ${kIsWeb ? "You\'re on localhost" : "Your server URL is correct (check Profile → Server URL)"}\n\n'
            'Error: $e',
        rawReply: '',
        sessionId: sessionId,
      );
    }
  }

  // ─── Devices ─────────────────────────────────────────────────────────────

  static Future<List<Device>> listDevices(String userId) async {
    final base = await _getBaseUrl();
    final resp = await http.get(
      Uri.parse('$base/api/devices').replace(queryParameters: {'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => Device.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<Device?> createDevice(Device d) async {
    final base = await _getBaseUrl();
    final resp = await http.post(
      Uri.parse('$base/api/devices'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(d.toCreateJson()),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['data'] == null) return null;
    return Device.fromJson(body['data'] as Map<String, dynamic>);
  }

  static Future<bool> updateDevice(String deviceId, Map<String, dynamic> patch) async {
    final base = await _getBaseUrl();
    final resp = await http.patch(
      Uri.parse('$base/api/devices/$deviceId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    ).timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  static Future<bool> deleteDevice(String deviceId) async {
    final base = await _getBaseUrl();
    final resp = await http.delete(Uri.parse('$base/api/devices/$deviceId'))
        .timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  // ─── Notifications inbox ─────────────────────────────────────────────────

  static Future<List<NotificationItem>> listNotifications(
    String userId, {
    bool unreadOnly = false,
    int limit = 100,
  }) async {
    final base = await _getBaseUrl();
    final resp = await http.get(
      Uri.parse('$base/api/notifications').replace(queryParameters: {
        'user_id': userId,
        'unread_only': unreadOnly.toString(),
        'limit': limit.toString(),
      }),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => NotificationItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> markNotificationRead(
    String notificationId, {
    bool read = true,
  }) async {
    final base = await _getBaseUrl();
    final resp = await http.patch(
      Uri.parse('$base/api/notifications/$notificationId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'read_status': read}),
    ).timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  // ─── Cached incident summaries ───────────────────────────────────────────

  static Future<List<IncidentSummary>> listSummaries(String userId,
      {int limit = 50}) async {
    final base = await _getBaseUrl();
    final resp = await http.get(
      Uri.parse('$base/api/summaries').replace(queryParameters: {
        'user_id': userId,
        'limit': limit.toString(),
      }),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => IncidentSummary.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ─── Chat history ────────────────────────────────────────────────────────

  static Future<List<ChatSession>> listChatSessions(String userId) async {
    final base = await _getBaseUrl();
    final resp = await http.get(
      Uri.parse('$base/api/chat/sessions')
          .replace(queryParameters: {'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => ChatSession.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<List<ChatMessage>> listChatMessages(String sessionId) async {
    final base = await _getBaseUrl();
    final resp = await http
        .get(Uri.parse('$base/api/chat/sessions/$sessionId/messages'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}

class ChatTurnResult {
  final String reply;       // formatted (with sources block) for direct display
  final String rawReply;    // unformatted, for the conversation history payload
  final String? sessionId;
  const ChatTurnResult({
    required this.reply,
    required this.rawReply,
    required this.sessionId,
  });
}
