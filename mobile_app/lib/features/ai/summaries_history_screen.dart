import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/api_service.dart';
import '../../data/models.dart';
import '../../data/supabase_service.dart';

/// Cached AI incident summaries history screen.
class SummariesHistoryScreen extends StatefulWidget {
  const SummariesHistoryScreen({super.key});
  @override
  State<SummariesHistoryScreen> createState() => _SummariesHistoryScreenState();
}

class _SummariesHistoryScreenState extends State<SummariesHistoryScreen> {
  List<IncidentSummary> _summaries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final uid = context.read<SupabaseService>().userId;
    if (uid == null) return;
    setState(() => _loading = true);
    final data = await ApiService.listSummaries(uid);
    if (!mounted) return;
    setState(() { _summaries = data; _loading = false; });
  }

  void _showDetail(IncidentSummary s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final range = '${DateFormat('MMM d, yyyy').format(s.startTime.toLocal())} – '
        '${DateFormat('MMM d, yyyy').format(s.endTime.toLocal())}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 20),
              Row(children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                const Text('AI Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(range, style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38)),
              Text(
                '${s.incidentCount} incident${s.incidentCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 13, color: AppColors.accentPrimary),
              ),
              const SizedBox(height: 20),
              Text(s.summaryText, style: TextStyle(
                fontSize: 14, height: 1.7,
                color: isDark ? Colors.white70 : Colors.black87,
              )),
              const SizedBox(height: 16),
              Text(
                'Generated ${DateFormat('MMM d, h:mm a').format(s.generatedAt.toLocal())}',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white24 : Colors.black26),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Past Summaries')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.summarize_outlined, size: 64,
                      color: isDark ? Colors.white24 : Colors.black26),
                  const SizedBox(height: 16),
                  Text('No summaries yet', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black54)),
                  const SizedBox(height: 6),
                  Text('Generate a daily summary to see it here.',
                      style: TextStyle(fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38)),
                ]))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _summaries.length,
                    itemBuilder: (_, i) {
                      final s = _summaries[i];
                      final range = '${DateFormat('MMM d').format(s.startTime.toLocal())} – '
                          '${DateFormat('MMM d').format(s.endTime.toLocal())}';
                      return GestureDetector(
                        onTap: () => _showDetail(s),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : AppColors.lightCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(range, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    Text('${s.incidentCount} incident${s.incidentCount == 1 ? '' : 's'}',
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                                  ],
                                )),
                                Icon(Icons.chevron_right, size: 20,
                                    color: isDark ? Colors.white30 : Colors.black26),
                              ]),
                              const SizedBox(height: 10),
                              Text(s.summaryText, maxLines: 3, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54, height: 1.5)),
                              const SizedBox(height: 8),
                              Text(DateFormat('MMM d, h:mm a').format(s.generatedAt.toLocal()),
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white24 : Colors.black26)),
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
