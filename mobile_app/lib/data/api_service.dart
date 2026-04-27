import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Get a chat response from the First Aid RAG chatbot.
  static Future<String> getChatResponse(String message) async {
    try {
      final baseUrl = await _getBaseUrl();
      final chatUrl = '$baseUrl/api/chat';

      final resp = await http.post(
        Uri.parse(chatUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message}),
      ).timeout(
        const Duration(seconds: 30),
      );

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = body['reply'] as String? ??
            body['response'] as String? ??
            'No response received.';

        // Append source citations if present
        if (body.containsKey('sources') && body['sources'] is List) {
          final sources = (body['sources'] as List)
              .map((s) => '📖 ${s['book']} (p.${s['page']})')
              .toSet()
              .join('\n');
          if (sources.isNotEmpty) {
            return '$reply\n\n─── Sources ───\n$sources';
          }
        }
        return reply;
      }
      return 'The assistant is temporarily unavailable (${resp.statusCode}).';
    } catch (e) {
      debugPrint('Chatbot API error: $e');
      return 'Could not reach the assistant.\n\n'
          'Make sure:\n'
          '• The backend is running\n'
          '• ${kIsWeb ? "You\'re on localhost" : "Your server URL is correct (check Profile → Server URL)"}\n\n'
          'Error: $e';
    }
  }
}
