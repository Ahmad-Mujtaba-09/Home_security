import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../data/supabase_service.dart';
import '../../data/models.dart';
import '../devices/devices_screen.dart';
import '../summaries/summaries_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await context.read<SupabaseService>().fetchProfile();
    if (mounted) {
      setState(() {
        _profile = p;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(UserProfile updated) async {
    setState(() => _profile = updated);
    await context.read<SupabaseService>().updateProfile(updated);
  }

  Future<void> _logout() async {
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
      return const Center(child: Text('Profile not found'));
    }

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

            // ── Settings ────────────────────────────────────────────────
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

            // ── Quick Access ─────────────────────────────────────────────
            _SectionTitle(title: 'Quick Access'),
            const SizedBox(height: 8),
            _NavTile(
              icon: Icons.videocam_outlined,
              label: 'Manage Devices',
              subtitle: 'Add or edit monitoring cameras',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen())),
            ),
            const SizedBox(height: 10),
            _NavTile(
              icon: Icons.summarize_outlined,
              label: 'Incident Summaries',
              subtitle: 'View past AI-generated reports',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SummariesScreen())),
            ),
            const SizedBox(height: 36),

            // ── Logout ──────────────────────────────────────────────────
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
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
            Icon(Icons.chevron_right,
                size: 20, color: isDark ? Colors.white30 : Colors.black26),
          ],
        ),
      ),
    );
  }
}
