import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../data/supabase_service.dart';
import '../../data/inference_service.dart';
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
  bool _reportLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Fetch from Supabase (may return empty if credentials not configured)
    final dbEvents = await context.read<SupabaseService>().fetchHistory();
    // Also merge local session alerts from inference service
    final inference = context.read<InferenceService>();
    final localAlerts = inference.alerts.asMap().entries.map((entry) {
      final a = entry.value;
      return HistoryEvent(
        id: 'local_${entry.key}',
        userId: context.read<SupabaseService>().userId ?? 'local',
        eventType: a.type,
        confidence: a.prob,
        frameCount: a.frame,
        timestamp: DateTime.now(), // Local alerts don't have DB timestamps
      );
    }).toList();
    // Combine: DB events first, then local (avoiding duplicates by checking if DB is empty)
    final combined = dbEvents.isNotEmpty ? dbEvents : localAlerts;
    if (mounted) setState(() { _events = combined; _loading = false; });
  }

  List<HistoryEvent> get _filtered {
    if (_filter == 'ALL') return _events;
    return _events.where((e) => e.eventType == _filter).toList();
  }

  Future<void> _generateReport() async {
    final userId = context.read<SupabaseService>().userId;
    if (userId == null) return;

    setState(() => _reportLoading = true);
    try {
      final report = await InferenceService.fetchGeminiReport(userId);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => _ReportDialog(report: report),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report error: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
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
                const Spacer(),
                _reportLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Generate AI Summary',
                        onPressed: _generateReport,
                        icon: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              AppColors.accentPrimary,
                              AppColors.accentSecondary,
                            ],
                          ).createShader(bounds),
                          child: const Icon(Icons.auto_awesome,
                              color: Colors.white),
                        ),
                      ),
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
                          label: Text(f),
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
                          child: Text(
                            'No events found',
                            style: TextStyle(
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
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
                              final isHigh = e.eventType == 'FALL' ||
                                  e.eventType == 'INACTIVITY';
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCard
                                      : AppColors.lightCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isHigh
                                        ? AppColors.danger
                                            .withValues(alpha: 0.25)
                                        : (isDark
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isHigh
                                              ? [
                                                  AppColors.danger
                                                      .withValues(alpha: 0.2),
                                                  AppColors.accentOrange
                                                      .withValues(alpha: 0.1),
                                                ]
                                              : [
                                                  AppColors.warning
                                                      .withValues(alpha: 0.2),
                                                  AppColors.accentPrimary
                                                      .withValues(alpha: 0.1),
                                                ],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        isHigh
                                            ? Icons.warning_amber
                                            : Icons.child_care,
                                        size: 20,
                                        color: isHigh
                                            ? AppColors.danger
                                            : AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.eventType
                                                .replaceAll('_', ' '),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dateFmt.format(
                                                e.timestamp.toLocal()),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white38
                                                  : Colors.black38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (e.confidence != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isHigh
                                              ? AppColors.danger
                                                  .withValues(alpha: 0.1)
                                              : AppColors.accentPrimary
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${(e.confidence! * 100).toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isHigh
                                                ? AppColors.danger
                                                : AppColors.accentPrimary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
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
}

// ─── Gemini Report Dialog ────────────────────────────────────────────────────

class _ReportDialog extends StatelessWidget {
  final String report;
  const _ReportDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(colors: [
                    AppColors.accentPrimary,
                    AppColors.accentSecondary,
                  ]).createShader(b),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI Daily Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  report,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Missing API Key Dialog ──────────────────────────────────────────────────

class _ApiKeyMissingDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warning.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.key_off, color: AppColors.warning, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Gemini API Key Not Set',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'To generate AI summaries, you need to set your Gemini API key.\n\n'
              '1. Go to https://aistudio.google.com/apikey\n'
              '2. Create or copy your API key\n'
              '3. Open chrome_app/.env\n'
              '4. Replace YOUR_GEMINI_API_KEY with your actual key\n'
              '5. Also create Engine/.env with GEMINI_API_KEY=your_key\n'
              '6. Restart the app and backend',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
