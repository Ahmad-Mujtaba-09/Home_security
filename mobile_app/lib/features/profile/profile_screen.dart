import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';
import '../../data/models.dart';
import '../../data/notification_manager.dart';
import '../../data/api_service.dart';
import '../../theme/theme_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String _serverUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await context.read<SupabaseService>().fetchProfile();
    final url = await ApiService.getServerUrl();
    if (mounted) {
      setState(() {
        _profile = p;
        _serverUrl = url;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(UserProfile updated) async {
    setState(() => _profile = updated);

    // Sync theme provider
    context.read<ThemeProvider>().setLight(updated.lightMode);

    await context.read<SupabaseService>().updateProfile(updated);
  }

  Future<void> _editServerUrl() async {
    final controller = TextEditingController(text: _serverUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
        title: const Text('Server URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste your ngrok URL here.\nExample: https://abc123.ngrok-free.app',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://your-url.ngrok-free.app',
                filled: true,
                fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Text(
              'Leave empty to use default (localhost)',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentPrimary,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await ApiService.setServerUrl(result);
      setState(() => _serverUrl = result.trim().replaceAll(RegExp(r'/+$'), ''));
    }
  }

  Future<void> _logout() async {
    NotificationManager.reset();
    await context.read<SupabaseService>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email =
        context.read<SupabaseService>().currentUser?.email ?? 'Unknown';

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final p = _profile;
    if (p == null) {
      return const Center(
        child: Text('Unable to load your profile. Please try again.'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ── Avatar & name ──────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.accentPrimary, AppColors.accentPink],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentPrimary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              email,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 32),

            // ── Appearance ─────────────────────────────────────────────
            _SectionTitle(title: 'Appearance'),
            const SizedBox(height: 8),
            _SettingTile(
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              trailing: Switch.adaptive(
                value: !p.lightMode,
                activeTrackColor: AppColors.accentPrimary,
                onChanged: (val) => _toggle(p.copyWith(lightMode: !val)),
              ),
            ),
            const SizedBox(height: 24),

            // ── Detection Modules ──────────────────────────────────────
            _SectionTitle(title: 'Detection Modules'),
            const SizedBox(height: 8),
            _SettingTile(
              icon: Icons.child_care,
              label: 'Child Surveillance',
              subtitle: 'Hazard proximity detection for children',
              trailing: Switch.adaptive(
                value: p.childModuleEnabled,
                activeTrackColor: AppColors.accentPink,
                onChanged: (val) =>
                    _toggle(p.copyWith(childModuleEnabled: val)),
              ),
            ),
            const SizedBox(height: 10),
            _SettingTile(
              icon: Icons.elderly,
              label: 'Elderly Care',
              subtitle: 'Fall & inactivity detection for elderly',
              trailing: Switch.adaptive(
                value: p.elderlyModuleEnabled,
                activeTrackColor: AppColors.accentGreen,
                onChanged: (val) =>
                    _toggle(p.copyWith(elderlyModuleEnabled: val)),
              ),
            ),
            const SizedBox(height: 24),

            // ── Server Connection ──────────────────────────────────────
            _SectionTitle(title: 'Server Connection'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _editServerUrl,
              child: Container(
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
                    Icon(Icons.dns_outlined, size: 22,
                        color: AppColors.accentPrimary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Server URL',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            _serverUrl.isEmpty
                                ? 'Using default (localhost)'
                                : _serverUrl,
                            style: TextStyle(
                              fontSize: 12,
                              color: _serverUrl.isEmpty
                                  ? (isDark ? Colors.white38 : Colors.black38)
                                  : AppColors.accentGreen,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined, size: 18,
                        color: isDark ? Colors.white38 : Colors.black38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),

            // ── Logout ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(color: AppColors.danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper widgets ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.accentPrimary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget trailing;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.accentPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
