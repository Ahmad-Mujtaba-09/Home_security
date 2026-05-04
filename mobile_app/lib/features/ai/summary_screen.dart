import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/api_service.dart';
import '../../data/supabase_service.dart';
import 'summaries_history_screen.dart';

/// AI Summary screen with a prominent generation card and result display.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  String? _summary;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final userId = context.read<SupabaseService>().userId;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _summary = null;
    });

    try {
      final result = await ApiService.getSummary(userId);
      if (mounted) setState(() => _summary = result);
    } catch (e) {
      if (mounted) {
        setState(() => _summary =
            'Something went wrong while generating your summary. '
            'Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Assistant',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Get an intelligent summary of your monitoring activity.',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),

            // ── Generate Card ──────────────────────────────────────────
            GestureDetector(
              onTap: _loading ? null : _generate,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final glow = _loading ? _pulseCtrl.value * 0.3 : 0.0;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentPrimary
                              .withValues(alpha: 0.25 + glow),
                          blurRadius: 24 + (glow * 20),
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          child: _loading
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome,
                                  color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loading
                              ? 'Generating your summary…'
                              : 'Generate Daily Summary',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _loading
                              ? 'This may take a few seconds.'
                              : 'Tap to get an AI-powered overview of today\'s activity.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // ── Summary Result ─────────────────────────────────────────
            if (_summary != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (b) =>
                              AppColors.primaryGradient.createShader(b),
                          child: const Icon(Icons.auto_awesome,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _summary!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Past summaries link ───────────────────────────────────────
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SummariesHistoryScreen()),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20, color: AppColors.accentPrimary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('View Past Summaries',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    Icon(Icons.chevron_right, size: 20,
                        color: isDark ? Colors.white30 : Colors.black26),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AnimatedBuilder is just an alias for [AnimatedBuilder] / [AnimatedWidget].
/// We use Flutter's built-in [AnimatedBuilder].
