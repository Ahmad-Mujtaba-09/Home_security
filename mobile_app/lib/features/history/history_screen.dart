import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';
import '../../data/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEvent> _events = [];
  bool _loading = true;
  String _filter = 'ALL';
  int _newEventCount = 0;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Listen for realtime inserts to add a "new events" badge
    _realtimeSub = context.read<SupabaseService>().historyStream.listen((_) {
      if (mounted) setState(() => _newEventCount++);
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _newEventCount = 0;
    });
    final events = await context.read<SupabaseService>().fetchHistory();
    if (mounted) {
      setState(() {
        _events = events;
        _loading = false;
      });
    }
  }

  List<HistoryEvent> get _filtered {
    if (_filter == 'ALL') return _events;
    return _events.where((e) => e.eventType == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFmt = DateFormat('MMM dd, HH:mm');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Event History',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (_newEventCount > 0) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _load,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_newEventCount new',
                        style: const TextStyle(
                          color: AppColors.accentPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Filter chips ────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['ALL', 'FALL', 'INACTIVITY', 'CHILD_HAZARD']
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_chipLabel(f)),
                          selected: _filter == f,
                          selectedColor:
                              AppColors.accentPrimary.withValues(alpha: 0.2),
                          onSelected: (_) => setState(() => _filter = f),
                          labelStyle: TextStyle(
                            color: _filter == f
                                ? AppColors.accentPrimary
                                : null,
                            fontWeight: _filter == f
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),

            // ── List ────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_available,
                                size: 48,
                                color:
                                    isDark ? Colors.white12 : Colors.black12,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No events found',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black26,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Events will appear here as they are detected.',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final e = _filtered[i];
                              return _EventCard(
                                event: e,
                                dateFmt: dateFmt,
                                isDark: isDark,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _chipLabel(String raw) {
    switch (raw) {
      case 'ALL':
        return 'All Events';
      case 'FALL':
        return '⚠️ Falls';
      case 'INACTIVITY':
        return '🔴 Inactivity';
      case 'CHILD_HAZARD':
        return '🚸 Child Hazard';
      default:
        return raw;
    }
  }
}

// ─── Event card ──────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final HistoryEvent event;
  final DateFormat dateFmt;
  final bool isDark;

  const _EventCard({
    required this.event,
    required this.dateFmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh =
        event.eventType == 'FALL' || event.eventType == 'INACTIVITY';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHigh
              ? AppColors.danger.withValues(alpha: 0.25)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isHigh
                    ? [
                        AppColors.danger.withValues(alpha: 0.2),
                        AppColors.accentOrange.withValues(alpha: 0.1),
                      ]
                    : [
                        AppColors.warning.withValues(alpha: 0.2),
                        AppColors.accentPrimary.withValues(alpha: 0.1),
                      ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isHigh ? Icons.warning_amber : Icons.child_care,
              size: 20,
              color: isHigh ? AppColors.danger : AppColors.warning,
            ),
          ),
          const SizedBox(width: 14),

          // Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.displayLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateFmt.format(event.timestamp.toLocal()),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),

          // Confidence badge
          if (event.confidence != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isHigh
                    ? AppColors.danger.withValues(alpha: 0.1)
                    : AppColors.accentPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(event.confidence! * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      isHigh ? AppColors.danger : AppColors.accentPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
