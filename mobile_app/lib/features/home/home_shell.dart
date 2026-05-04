import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';
import '../../data/api_service.dart';
import '../../data/notification_manager.dart';
import '../../theme/theme_provider.dart';
import '../history/history_screen.dart';
import '../ai/summary_screen.dart';
import '../ai/chatbot_screen.dart';
import '../profile/profile_screen.dart';
import '../notifications/notifications_screen.dart';

/// Main scaffold with a bottom navigation bar hosting the four tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  int _unreadNotifCount = 0;
  StreamSubscription? _realtimeSub;

  final _screens = const <Widget>[
    HistoryScreen(),
    SummaryScreen(),
    ChatbotScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final supa = context.read<SupabaseService>();
    final themeProvider = context.read<ThemeProvider>();

    // Fetch profile and apply theme
    final profile = await supa.fetchProfile();
    if (profile != null && mounted) {
      themeProvider.setLight(profile.lightMode);
    }

    // Start realtime subscription
    supa.subscribeToHistory();

    // Pipe realtime events into the notification manager
    _realtimeSub = supa.historyStream.listen((event) {
      NotificationManager.notify(event);
      // Bump unread count when a new event arrives
      _refreshUnread();
    });

    // Initial unread count
    _refreshUnread();
  }

  Future<void> _refreshUnread() async {
    final uid = context.read<SupabaseService>().userId;
    if (uid == null) return;
    final items = await ApiService.listNotifications(uid, unreadOnly: true);
    if (mounted) setState(() => _unreadNotifCount = items.length);
  }

  void _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _refreshUnread();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // ── Global top bar with notification bell ─────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.primaryGradient.createShader(bounds),
                    child: const Text(
                      'IHS',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Surveillance',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  // Notification bell
                  GestureDetector(
                    onTap: _openNotifications,
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.notifications_outlined,
                            size: 24,
                            color: _unreadNotifCount > 0
                                ? AppColors.accentPrimary
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                        if (_unreadNotifCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(
                                  minWidth: 18, minHeight: 14),
                              child: Text(
                                '${_unreadNotifCount > 99 ? '99+' : _unreadNotifCount}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              activeIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: 'AI Summary',
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
