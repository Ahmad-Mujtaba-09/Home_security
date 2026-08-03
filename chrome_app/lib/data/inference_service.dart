import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Manages the WebSocket connection to the FastAPI inference backend.
class InferenceService extends ChangeNotifier {
  WebSocketChannel? _channel;
  WebSocketChannel? _videoChannel;
  bool _connected = false;
  bool _processingVideo = false;
  final List<DetectionAlert> _alerts = [];

  /// Camera mode: 'mobile' (eye-level) or 'cctv' (top-down).
  String _cameraMode = 'mobile';

  /// Latest annotated frame from the backend (JPEG bytes).
  Uint8List? _latestFrame;
  int _currentFrame = 0;
  int _totalFrames = 0;

  bool get connected => _connected;
  bool get processingVideo => _processingVideo;
  String get cameraMode => _cameraMode;
  set cameraMode(String mode) {
    _cameraMode = mode;
    notifyListeners();
  }
  List<DetectionAlert> get alerts => List.unmodifiable(_alerts);
  DetectionAlert? get latestAlert => _alerts.isNotEmpty ? _alerts.last : null;
  Uint8List? get latestFrame => _latestFrame;
  int get currentFrame => _currentFrame;
  int get totalFrames => _totalFrames;

  final _alertController = StreamController<DetectionAlert>.broadcast();
  Stream<DetectionAlert> get alertStream => _alertController.stream;

  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  String get _baseUrl =>
      dotenv.env['INFERENCE_API_URL'] ?? 'ws://10.0.2.2:8000';

  String? _userId; // Stored for auto-reconnect
  Timer? _reconnectTimer;
  int _reconnectDelay = 2; // seconds, grows with backoff
  bool _intentionalDisconnect = false;

  /// Connect to the FastAPI WebSocket inference endpoint.
  void connect(String userId) {
    _userId = userId;
    _intentionalDisconnect = false;
    _doConnect(userId);
  }

  void _doConnect(String userId) {
    if (_connected) return;
    final uri = Uri.parse('$_baseUrl/ws/inference/$userId?camera_mode=$_cameraMode');
    debugPrint('InferenceService: connecting to $uri');

    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      debugPrint('InferenceService: connect failed: $e');
      _scheduleReconnect();
      return;
    }

    _connected = true;
    _reconnectDelay = 2; // Reset backoff on successful connect
    notifyListeners();

    _channel!.stream.listen(
      (message) => _handleMessage(message as String),
      onDone: () {
        debugPrint('InferenceService: WS closed');
        _connected = false;
        notifyListeners();
        _scheduleReconnect();
      },
      onError: (e) {
        debugPrint('InferenceService: WS error: $e');
        _connected = false;
        notifyListeners();
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _userId == null) return;
    _reconnectTimer?.cancel();
    debugPrint('InferenceService: reconnecting in ${_reconnectDelay}s...');
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      if (!_connected && _userId != null && !_intentionalDisconnect) {
        _doConnect(_userId!);
      }
    });
    // Exponential backoff capped at 30s
    _reconnectDelay = (_reconnectDelay * 2).clamp(2, 30);
  }

  /// Send a JPEG-encoded frame to the backend.
  void sendFrame(Uint8List jpegBytes) {
    if (!_connected || _channel == null) return;
    _channel!.sink.add(jpegBytes);
  }

  /// Send a video file to the backend for server-side processing.
  /// Annotated frames will stream back in real-time.
  void sendVideoFile(Uint8List videoBytes, String filename, String userId) {
    // Connect to the video processing WebSocket
    final uri = Uri.parse('$_baseUrl/ws/process-video/$userId');
    _videoChannel = WebSocketChannel.connect(uri);
    _processingVideo = true;
    _currentFrame = 0;
    _totalFrames = 0;
    notifyListeners();

    _videoChannel!.stream.listen(
      (message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;

        if (data.containsKey('status') && data['status'] == 'done') {
          _processingVideo = false;
          notifyListeners();
          return;
        }

        _handleMessage(message);

        if (data.containsKey('total_frames')) {
          _totalFrames = data['total_frames'] as int? ?? 0;
        }
      },
      onDone: () {
        _processingVideo = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Video WS error: $e');
        _processingVideo = false;
        notifyListeners();
      },
    );

    // Send the video as base64 JSON
    final videoB64 = base64Encode(videoBytes);
    _videoChannel!.sink.add(jsonEncode({
      'video': videoB64,
      'filename': filename,
      'camera_mode': _cameraMode,
    }));
  }

  /// Stop video processing.
  void stopVideoProcessing() {
    _videoChannel?.sink.close();
    _videoChannel = null;
    _processingVideo = false;
    notifyListeners();
  }

  /// Connect to an RTSP/HTTP stream via the backend.
  /// The backend opens the stream server-side and streams annotated frames back.
  void connectStream(String streamUrl, String userId) {
    final uri = Uri.parse('$_baseUrl/ws/stream/$userId');
    _videoChannel = WebSocketChannel.connect(uri);
    _processingVideo = true;
    _currentFrame = 0;
    _totalFrames = 0;
    notifyListeners();

    _videoChannel!.stream.listen(
      (message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;

        if (data.containsKey('error')) {
          debugPrint('Stream error: ${data['error']}');
          _processingVideo = false;
          notifyListeners();
          return;
        }

        if (data.containsKey('status') && data['status'] == 'done') {
          _processingVideo = false;
          notifyListeners();
          return;
        }

        _handleMessage(message);
      },
      onDone: () {
        _processingVideo = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Stream WS error: $e');
        _processingVideo = false;
        notifyListeners();
      },
    );

    // Send the stream URL as the first message
    _videoChannel!.sink.add(jsonEncode({
      'url': streamUrl,
      'camera_mode': _cameraMode,
    }));
  }

  /// Stop RTSP stream processing.
  void stopStream() {
    _videoChannel?.sink.close();
    _videoChannel = null;
    _processingVideo = false;
    notifyListeners();
  }

  // ─── Detection overlay metadata ────────────────────────────────────────────
  List<Map<String, dynamic>> _detections = [];
  Timer? _detectionExpiry; // Auto-clear stale overlays
  List<Map<String, dynamic>> get detections => _detections;

  final _detectionsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get detectionsStream => _detectionsController.stream;

  /// Parse a WebSocket message (shared between live and video channels).
  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;

      // Parse alerts
      if (data.containsKey('alerts')) {
        for (final a in (data['alerts'] as List)) {
          final alert = DetectionAlert.fromJson(a as Map<String, dynamic>);
          _alerts.add(alert);
          _alertController.add(alert);
        }
      }

      // Parse detection overlays (camera mode — lightweight metadata)
      if (data.containsKey('detections')) {
        _detections = List<Map<String, dynamic>>.from(
          (data['detections'] as List).map((d) => Map<String, dynamic>.from(d as Map)),
        );
        _detectionsController.add(_detections);
        // Trigger frame stream for flow control (even without annotated_frame)
        _frameController.add(Uint8List(0));

        // Auto-expire detections after 800ms if no new response
        _detectionExpiry?.cancel();
        _detectionExpiry = Timer(const Duration(milliseconds: 800), () {
          _detections = [];
          notifyListeners();
        });
      }

      // Parse annotated frame (file/stream mode)
      if (data.containsKey('annotated_frame')) {
        final frameB64 = data['annotated_frame'] as String;
        _latestFrame = base64Decode(frameB64);
        _frameController.add(_latestFrame!);
      }

      // Parse frame counter
      if (data.containsKey('frame')) {
        _currentFrame = data['frame'] as int? ?? _currentFrame;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('WS parse error: $e');
    }
  }

  /// Disconnect the WebSocket (stops auto-reconnect).
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _videoChannel?.sink.close();
    _connected = false;
    _processingVideo = false;
    _latestFrame = null;
    notifyListeners();
  }

  void clearAlerts() {
    _alerts.clear();
    _latestFrame = null;
    _currentFrame = 0;
    _totalFrames = 0;
    notifyListeners();
  }

  // ─── REST helpers ──────────────────────────────────────────────────────────

  /// Fetch a Gemini daily summary report via the backend REST API.
  static Future<String> fetchGeminiReport(String userId) async {
    final baseUrl =
        (dotenv.env['INFERENCE_API_URL'] ?? 'http://10.0.2.2:8000')
            .replaceFirst('ws://', 'http://')
            .replaceFirst('wss://', 'https://');
    final uri =
        Uri.parse('$baseUrl/api/gemini-report').replace(queryParameters: {
      'user_id': userId,
    });
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['report'] as String? ?? 'No report generated.';
    }
    throw Exception('Gemini report failed: ${resp.statusCode}');
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _detectionExpiry?.cancel();
    disconnect();
    _alertController.close();
    _frameController.close();
    _detectionsController.close();
    super.dispose();
  }
}
