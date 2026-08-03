import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/app_theme.dart';
import '../../data/supabase_service.dart';
import '../../data/inference_service.dart';
import '../../data/api_service.dart';
import '../../data/models.dart';
import '../history/history_screen.dart';
import '../profile/profile_screen.dart';
import '../chatbot/chatbot_screen.dart';
import '../notifications/notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _navIndex = 0;
  int _unreadNotifCount = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      _LiveFeedPage(),
      HistoryScreen(),
      ChatbotScreen(),
      ProfileScreen(),
    ];

    // Auto-connect WebSocket for inference
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<SupabaseService>().userId;
      if (userId != null) {
        context.read<InferenceService>().connect(userId);
        _refreshUnread(userId);
      }
    });
  }

  Future<void> _refreshUnread(String userId) async {
    final items = await ApiService.listNotifications(userId, unreadOnly: true);
    if (mounted) setState(() => _unreadNotifCount = items.length);
  }

  void _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    final userId = context.read<SupabaseService>().userId;
    if (userId != null) _refreshUnread(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _navIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: (i) => setState(() => _navIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_outlined),
              activeIcon: Icon(Icons.videocam),
              label: 'Live',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'First Aid',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Feed Page (Tab 0)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveFeedPage extends StatefulWidget {
  const _LiveFeedPage();

  @override
  State<_LiveFeedPage> createState() => _LiveFeedPageState();
}

class _LiveFeedPageState extends State<_LiveFeedPage> {
  String _source = 'camera'; // 'camera' | 'stream' | 'file'
  CameraController? _cameraController;
  bool _isCameraActive = false;
  bool _isStreaming = false;
  bool _isFilePlaying = false;
  bool _isCapturing = false;
  bool _waitingForResponse = false; // Flow control: wait for backend before sending next
  bool _cameraStreamActive = false; // Controls the send loop
  String? _selectedFileName;
  Timer? _frameTimer;
  String? _streamUrl;
  StreamSubscription? _frameSub; // Listen for backend responses

  @override
  void dispose() {
    _stopFeed();
    super.dispose();
  }

  Future<void> _startFeed() async {
    switch (_source) {
      case 'camera':
        await _startCameraFeed();
        break;
      case 'stream':
        await _startStreamFeed();
        break;
      case 'file':
        await _startFileFeed();
        break;
    }
  }

  Future<void> _startCameraFeed() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No cameras available on this device'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium, // 720p — good local preview, sent frames are still compressed JPEG
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isCameraActive = true);

        // Start sending frames to inference backend
        _startFrameStreaming();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera feed started — streaming to inference engine'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _startFrameStreaming() {
    final inference = context.read<InferenceService>();
    if (!inference.connected) {
      debugPrint('Camera: inference not connected, cannot stream frames');
      return;
    }

    _cameraStreamActive = true;
    _waitingForResponse = false;

    // Listen for backend responses — each response unblocks the next frame send
    _frameSub = inference.frameStream.listen((_) {
      _waitingForResponse = false;
      // Immediately send the next frame
      if (_cameraStreamActive) _captureAndSend(inference);
    });

    // Send the first frame to kick off the loop
    _captureAndSend(inference);
  }

  Future<void> _captureAndSend(InferenceService inference) async {
    if (!_cameraStreamActive || _isCapturing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (!inference.connected) return;

    _isCapturing = true;
    _waitingForResponse = true;
    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      inference.sendFrame(bytes);
    } catch (e) {
      debugPrint('Camera: frame capture error: $e');
      _waitingForResponse = false;
      // Retry after a short delay on error
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_cameraStreamActive) _captureAndSend(inference);
      });
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _startStreamFeed() async {
    final urlController = TextEditingController(text: _streamUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          title: Row(
            children: [
              Icon(Icons.wifi_tethering, color: AppColors.accentPrimary, size: 22),
              const SizedBox(width: 10),
              const Text('Stream URL', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the RTSP or HTTP stream URL from your IP camera:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: 'rtsp://192.168.1.x:554/stream',
                  prefixIcon: const Icon(Icons.link, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, urlController.text.trim()),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(100, 40),
              ),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _streamUrl = result;
        _isStreaming = true;
      });

      // Send stream URL to backend for server-side processing
      final inference = context.read<InferenceService>();
      final userId = context.read<SupabaseService>().userId ?? 'anonymous';
      inference.connectStream(result, userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connecting to stream: $result'),
            backgroundColor: AppColors.info,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _startFileFeed() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true, // Load bytes directly
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final pickedFile = result.files.single;
      final bytes = pickedFile.bytes;

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not read the selected file'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }

      setState(() {
        _isFilePlaying = true;
        _selectedFileName = pickedFile.name;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing video: ${pickedFile.name}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      // Send video to backend for server-side processing
      final inference = context.read<InferenceService>();
      final userId = context.read<SupabaseService>().userId ?? 'anonymous';
      inference.sendVideoFile(Uint8List.fromList(bytes), pickedFile.name, userId);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File picker error: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _stopFeed() {
    _cameraStreamActive = false;
    _frameSub?.cancel();
    _frameSub = null;
    _frameTimer?.cancel();
    _frameTimer = null;
    _cameraController?.dispose();
    _cameraController = null;
    // Stop video/stream processing if active
    final inference = context.read<InferenceService>();
    inference.stopVideoProcessing();
    inference.stopStream();
    if (mounted) {
      setState(() {
        _isCameraActive = false;
        _isStreaming = false;
        _isFilePlaying = false;
        _selectedFileName = null;
      });
    }
  }

  /// Build the video display area based on current state.
  Widget _buildVideoArea(InferenceService inference, bool isDark, bool feedActive) {
    final hasAnnotatedFrame = inference.latestFrame != null;
    final bool isActive = _isCameraActive || _isStreaming || _isFilePlaying;

    // ── Camera mode: smooth local preview + detection overlays ──
    if (_isCameraActive && _cameraController != null && _cameraController!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Live camera preview + detection overlay (same coordinate space)
          Center(
            child: AspectRatio(
              aspectRatio: _cameraController!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_cameraController!),
                  // Detection overlay (boxes from backend)
                  Consumer<InferenceService>(
                    builder: (_, inf, __) => CustomPaint(
                      painter: _DetectionOverlayPainter(inf.detections),
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // LIVE badge (top-left)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Stop button
          Positioned(
            bottom: 16,
            left: 0, right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _stopFeed,
                icon: const Icon(Icons.stop, size: 20),
                label: const Text('Stop Feed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(160, 42),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── File/Stream mode with annotated frames from backend ──
    if (isActive && hasAnnotatedFrame) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Annotated frame from the backend
          Image.memory(
            inference.latestFrame!,
            fit: BoxFit.contain,
            gaplessPlayback: true, // prevents flicker between frames
          ),
          // LIVE badge (top-left)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isFilePlaying ? 'PROCESSING' : 'LIVE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Frame counter (top-right) for file mode
          if (_isFilePlaying && inference.totalFrames > 0)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Frame ${inference.currentFrame}/${inference.totalFrames}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // Stop button (bottom)
          Positioned(
            bottom: 16,
            left: 0, right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _stopFeed,
                icon: const Icon(Icons.stop, size: 20),
                label: Text(_isFilePlaying ? 'Stop' : 'Stop Feed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(160, 42),
                ),
              ),
            ),
          ),
          // Progress bar (bottom, above stop button) for file mode
          if (_isFilePlaying && inference.totalFrames > 0)
            Positioned(
              bottom: 70,
              left: 16, right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: inference.currentFrame / inference.totalFrames,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentPrimary),
                ),
              ),
            ),
        ],
      );
    }

    // ── Active feed but waiting for first annotated frame ──
    if (isActive && !hasAnnotatedFrame) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _isFilePlaying
                      ? 'Processing video file...'
                      : _isCameraActive
                          ? 'Starting camera inference...'
                          : 'Connecting to stream...',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isFilePlaying
                      ? (_selectedFileName ?? '')
                      : (_streamUrl ?? ''),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0, right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _stopFeed,
                icon: const Icon(Icons.stop, size: 20),
                label: Text(_isFilePlaying ? 'Stop' : 'Disconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(160, 42),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── Idle state ──
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _source == 'camera'
                ? Icons.videocam_outlined
                : _source == 'stream'
                    ? Icons.cast_connected
                    : Icons.video_file_outlined,
            size: 56,
            color: AppColors.accentPrimary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _source == 'camera'
                ? 'Camera feed will appear here'
                : _source == 'stream'
                    ? 'Enter remote stream URL'
                    : 'Select a local video file',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _startFeed,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(
              _source == 'camera'
                  ? 'Start Camera'
                  : _source == 'stream'
                      ? 'Enter Stream URL'
                      : 'Pick Video File',
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(200, 44),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inference = context.watch<InferenceService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool feedActive = _isCameraActive || _isStreaming || _isFilePlaying;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      AppColors.accentPrimary,
                      AppColors.accentSecondary,
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'IHS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Surveillance',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const Spacer(),
                _StatusBadge(connected: inference.connected),
                const SizedBox(width: 8),
                _NotifBell(count: (context.findAncestorStateOfType<_DashboardScreenState>()?._unreadNotifCount ?? 0), onTap: () => context.findAncestorStateOfType<_DashboardScreenState>()?._openNotifications()),
              ],
            ),
            const SizedBox(height: 16),

            // ── Source selector ────────────────────────────────────────────
            Row(
              children: [
                _SourceChip(
                  label: 'Camera',
                  icon: Icons.camera_alt_outlined,
                  selected: _source == 'camera',
                  onTap: () {
                    if (feedActive) _stopFeed();
                    setState(() => _source = 'camera');
                  },
                ),
                const SizedBox(width: 8),
                _SourceChip(
                  label: 'Stream',
                  icon: Icons.wifi_tethering,
                  selected: _source == 'stream',
                  onTap: () {
                    if (feedActive) _stopFeed();
                    setState(() => _source = 'stream');
                  },
                ),
                const SizedBox(width: 8),
                _SourceChip(
                  label: 'File',
                  icon: Icons.folder_open_outlined,
                  selected: _source == 'file',
                  onTap: () {
                    if (feedActive) _stopFeed();
                    setState(() => _source = 'file');
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Camera mode toggle ─────────────────────────────────────────
            Consumer<InferenceService>(
              builder: (_, inf, __) {
                final isDarkMode = Theme.of(context).brightness == Brightness.dark;
                return Row(
                  children: [
                    Icon(
                      Icons.tune,
                      size: 16,
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mode:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      label: 'Mobile / Webcam',
                      icon: Icons.smartphone,
                      selected: inf.cameraMode == 'mobile',
                      onTap: () => inf.cameraMode = 'mobile',
                    ),
                    const SizedBox(width: 6),
                    _ModeChip(
                      label: 'CCTV',
                      icon: Icons.videocam,
                      selected: inf.cameraMode == 'cctv',
                      onTap: () => inf.cameraMode = 'cctv',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // ── Video area ────────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: feedActive
                        ? AppColors.accentPrimary.withValues(alpha: 0.4)
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: feedActive
                          ? AppColors.accentPrimary.withValues(alpha: 0.12)
                          : AppColors.accentPrimary.withValues(alpha: 0.06),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildVideoArea(inference, isDark, feedActive),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Alert feed ────────────────────────────────────────────────
            Text(
              'Detection Alerts',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: inference.alerts.isEmpty
                  ? Center(
                      child: Text(
                        'No alerts yet',
                        style: TextStyle(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: inference.alerts.length,
                      reverse: true,
                      itemBuilder: (_, i) {
                        final alert = inference.alerts[
                            inference.alerts.length - 1 - i];
                        return _AlertTile(alert: alert);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small widgets ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool connected;
  const _StatusBadge({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (connected ? AppColors.success : AppColors.danger)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (connected ? AppColors.success : AppColors.danger)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Live' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connected ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifBell extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _NotifBell({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.notifications_outlined, size: 24,
              color: count > 0 ? AppColors.accentPrimary : (Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black45)),
          ),
          if (count > 0)
            Positioned(
              right: 0, top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 14),
                child: Text('${count > 99 ? '99+' : count}', textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SourceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentPrimary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.accentPrimary
                : Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? AppColors.accentPrimary
                    : Theme.of(context).iconTheme.color?.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.accentPrimary
                    : Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSecondary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.accentSecondary
                : Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? AppColors.accentSecondary
                    : Theme.of(context).iconTheme.color?.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.accentSecondary
                    : Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final DetectionAlert alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHighSev = alert.type == 'FALL' || alert.type == 'INACTIVITY';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighSev
            ? AppColors.danger.withValues(alpha: 0.08)
            : (isDark ? AppColors.darkCard : AppColors.lightCard),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighSev
              ? AppColors.danger.withValues(alpha: 0.3)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isHighSev
                  ? AppColors.danger.withValues(alpha: 0.15)
                  : AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isHighSev ? Icons.warning_amber : Icons.child_care,
              size: 20,
              color: isHighSev ? AppColors.danger : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.displayLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Frame ${alert.frame}'
                  '${alert.prob != null ? '  •  ${(alert.prob! * 100).toStringAsFixed(0)}% conf' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
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

// ─── Detection Overlay Painter ───────────────────────────────────────────────

class _DetectionOverlayPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  _DetectionOverlayPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    for (final det in detections) {
      final bbox = det['bbox'] as List<dynamic>?;
      if (bbox == null || bbox.length < 4) continue;

      // Normalized coords (0-1) → pixel coords
      final x1 = (bbox[0] as num).toDouble() * size.width;
      final y1 = (bbox[1] as num).toDouble() * size.height;
      final x2 = (bbox[2] as num).toDouble() * size.width;
      final y2 = (bbox[3] as num).toDouble() * size.height;

      final type = det['type'] as String? ?? '';
      final label = det['label'] as String? ?? '';
      final colorCat = det['color'] as String? ?? 'normal';
      final conf = det['conf'] as num?;

      // Color based on category from engine
      Color boxColor;
      switch (colorCat) {
        case 'fall':
          boxColor = const Color(0xFFFF2222); // Red — fall/inactivity
          break;
        case 'warning':
          boxColor = const Color(0xFFFF8800); // Orange — pre-fall/falling
          break;
        case 'child':
          boxColor = const Color(0xFF22AAFF); // Blue — child
          break;
        default:
          boxColor = type == 'hazard'
            ? const Color(0xFFFF4444)  // Red for hazards
            : const Color(0xFF44FF44); // Green for normal persons
      }

      // Draw bounding box
      final paint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(Rect.fromLTRB(x1, y1, x2, y2), paint);

      // Build label text (engine sends rich label with ID, type, prob, etc.)
      String labelText = label;
      if (conf != null && type == 'hazard') {
        labelText += ' ${(conf * 100).toStringAsFixed(0)}%';
      }

      // Draw label background + text
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = Rect.fromLTWH(
        x1, y1 - textPainter.height - 4,
        textPainter.width + 8, textPainter.height + 4,
      );
      canvas.drawRect(bgRect, Paint()..color = boxColor.withValues(alpha: 0.75));
      textPainter.paint(canvas, Offset(x1 + 4, y1 - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
