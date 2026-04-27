import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailC.text.trim();
    final pass = _passC.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _showError('Please enter both your email and password.');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<SupabaseService>().signIn(email, pass);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().toLowerCase();
      if (message.contains('invalid') || message.contains('credentials')) {
        _showError('Incorrect email or password. Please try again.');
      } else if (message.contains('network') || message.contains('socket')) {
        _showError(
            'Unable to connect. Please check your internet connection.');
      } else {
        _showError('Something went wrong. Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo / Branding ──────────────────────────────────────
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.accentPrimary.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'IHS\nSurveillance',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitor. Protect. Respond.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.accentSecondary,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 48),

                  // ── Fields ───────────────────────────────────────────────
                  TextField(
                    controller: _emailC,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passC,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Login button ─────────────────────────────────────────
                  _loading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _login,
                          child: const Text('Sign In'),
                        ),
                  const SizedBox(height: 20),

                  // ── Signup link ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignupScreen()),
                        ),
                        style: TextButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign Up',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.accentPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
