import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/api_service.dart';
import '../../data/models.dart';
import '../../data/supabase_service.dart';

/// In-app notification inbox for the mobile app.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = [];
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final uid = context.read<SupabaseService>().userId;
    if (uid == null) return;
    setState(() => _loading = true);
    final items = await ApiService.listNotifications(uid);
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
  }

  Future<void> _markRead(int i) async {
    final n = _items[i];
    if (n.readStatus) return;
    setState(() => _items[i] = n.copyWith(readStatus: true));
    await ApiService.markNotificationRead(n.notificationId);
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    _markingAll = true;
    final unread = _items.where((x) => !x.readStatus).toList();
    if (mounted) setState(() => _items = _items.map((n) => n.copyWith(readStatus: true)).toList());
    for (final n in unread) {
      await ApiService.markNotificationRead(n.notificationId);
    }
    _markingAll = false;
  }

  int get _unreadCount => _items.where((n) => !n.readStatus).length;

  IconData _icon(String t) {
    switch (t) {
      case 'fall': return Icons.warning_amber_rounded;
      case 'inactivity': return Icons.hourglass_bottom;
      case 'child_hazard': return Icons.child_care;
      default: return Icons.notifications_outlined;
    }
  }

  Color _color(String t) {
    switch (t) {
      case 'fall': return AppColors.danger;
      case 'inactivity': return AppColors.accentOrange;
      case 'child_hazard': return AppColors.warning;
      default: return AppColors.accentPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Read all'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accentPrimary),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.notifications_none, size: 64,
                        color: isDark ? Colors.white24 : Colors.black26),
                    const SizedBox(height: 16),
                    Text('No notifications yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black54)),
                    const SizedBox(height: 6),
                    Text('Alerts will appear here when events are detected.',
                        style: TextStyle(fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      final c = _color(item.notificationType);
                      final time = DateFormat('MMM d, h:mm a').format(item.sentAt.toLocal());

                      return GestureDetector(
                        onTap: () => _markRead(i),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : AppColors.lightCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: item.readStatus
                                  ? (isDark ? AppColors.darkBorder : AppColors.lightBorder)
                                  : c.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_icon(item.notificationType),
                                    color: c, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      if (!item.readStatus)
                                        Container(
                                          width: 8, height: 8,
                                          margin: const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                              color: c, shape: BoxShape.circle),
                                        ),
                                      Expanded(
                                        child: Text(item.title,
                                            style: TextStyle(
                                              fontWeight: item.readStatus
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              fontSize: 14,
                                            )),
                                      ),
                                    ]),
                                    const SizedBox(height: 4),
                                    Text(item.message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                            height: 1.4)),
                                    const SizedBox(height: 6),
                                    Text(time,
                                        style: TextStyle(fontSize: 11,
                                            color: isDark ? Colors.white30 : Colors.black26)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
