import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';
import '../../data/notification_manager.dart';
import '../../theme/theme_provider.dart';
import '../history/history_screen.dart';
import '../ai/summary_screen.dart';
import '../ai/chatbot_screen.dart';
import '../profile/profile_screen.dart';

/// Main scaffold with a bottom navigation bar hosting the four tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
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
    });
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
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
