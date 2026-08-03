import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

/// REST API client for the FastAPI backend.
///
/// URL priority: .env INFERENCE_API_URL → fallback (localhost / 10.0.2.2).
class ApiService {
  ApiService._();

  /// Returns the base HTTP URL for the backend.
  static String _getBaseUrl() {
    final envUrl = (dotenv.env['INFERENCE_API_URL'] ?? '')
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
    if (envUrl.isNotEmpty) return envUrl;
    return kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
  }

  // ─── AI Summary (generate on demand) ────────────────────────────────────

  static Future<String> getSummary(String userId) async {
    try {
      final base = _getBaseUrl();
      final resp = await http.get(
        Uri.parse('$base/api/gemini-report')
            .replace(queryParameters: {'user_id': userId}),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['report'] as String? ??
            'Could not generate a summary right now.';
      }
      return 'Unable to reach the backend (${resp.statusCode}).';
    } catch (e) {
      debugPrint('getSummary error: $e');
      return 'Could not connect to the backend.\n\n'
          'Make sure the backend is running (python Engine/main.py)\n\n'
          'Error: $e';
    }
  }

  // ─── Chat with session support ──────────────────────────────────────────

  static Future<ChatTurnResult> sendChatMessage({
    required String message,
    required String userId,
    String? sessionId,
    List<Map<String, String>>? history,
  }) async {
    try {
      final base = _getBaseUrl();
      final resp = await http.post(
        Uri.parse('$base/api/chat'),
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
        reply: 'Could not reach the assistant.\n\nError: $e',
        rawReply: '',
        sessionId: sessionId,
      );
    }
  }

  // ─── Devices ────────────────────────────────────────────────────────────

  static Future<List<Device>> listDevices(String userId) async {
    final base = _getBaseUrl();
    final resp = await http.get(
      Uri.parse('$base/api/devices')
          .replace(queryParameters: {'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((j) => Device.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<Device?> createDevice(Device d) async {
    final base = _getBaseUrl();
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

  static Future<bool> updateDevice(
      String deviceId, Map<String, dynamic> patch) async {
    final base = _getBaseUrl();
    final resp = await http.patch(
      Uri.parse('$base/api/devices/$deviceId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    ).timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  static Future<bool> deleteDevice(String deviceId) async {
    final base = _getBaseUrl();
    final resp = await http
        .delete(Uri.parse('$base/api/devices/$deviceId'))
        .timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  // ─── Device monitoring control ────────────────────────────────────────

  static Future<bool> startDeviceMonitor(String deviceId) async {
    final base = _getBaseUrl();
    final resp = await http
        .post(Uri.parse('$base/api/devices/$deviceId/start'))
        .timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  static Future<bool> stopDeviceMonitor(String deviceId) async {
    final base = _getBaseUrl();
    final resp = await http
        .post(Uri.parse('$base/api/devices/$deviceId/stop'))
        .timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  static Future<String> getDeviceMonitorStatus(String deviceId) async {
    final base = _getBaseUrl();
    try {
      final resp = await http
          .get(Uri.parse('$base/api/devices/$deviceId/status'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['monitor_status'] as String? ?? 'stopped';
      }
    } catch (_) {}
    return 'stopped';
  }

  // ─── Notifications inbox ────────────────────────────────────────────────

  static Future<List<NotificationItem>> listNotifications(
    String userId, {
    bool unreadOnly = false,
    int limit = 100,
  }) async {
    final base = _getBaseUrl();
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
    final base = _getBaseUrl();
    final resp = await http.patch(
      Uri.parse('$base/api/notifications/$notificationId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'read_status': read}),
    ).timeout(const Duration(seconds: 15));
    return resp.statusCode == 200;
  }

  // ─── Cached incident summaries ──────────────────────────────────────────

  static Future<List<IncidentSummary>> listSummaries(String userId,
      {int limit = 50}) async {
    final base = _getBaseUrl();
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

  // ─── Chat history ──────────────────────────────────────────────────────

  static Future<List<ChatSession>> listChatSessions(String userId) async {
    final base = _getBaseUrl();
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
    final base = _getBaseUrl();
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

/// Result from a single chat turn.
class ChatTurnResult {
  final String reply; // formatted (with sources block)
  final String rawReply; // unformatted, for conversation history
  final String? sessionId;
  const ChatTurnResult({
    required this.reply,
    required this.rawReply,
    required this.sessionId,
  });
}
