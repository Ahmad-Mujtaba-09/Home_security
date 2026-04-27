import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_colors.dart';
import '../../data/supabase_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final email = _emailC.text.trim();
    final pass = _passC.text.trim();
    final confirm = _confirmC.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }
    if (pass != confirm) {
      _showError('Passwords do not match. Please re-enter them.');
      return;
    }
    if (pass.length < 6) {
      _showError('Password must be at least 6 characters long.');
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<SupabaseService>().signUp(email, pass);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Account created! Check your email to confirm your signup.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().toLowerCase();
      if (message.contains('already') || message.contains('exists')) {
        _showError(
            'An account with this email already exists. Try signing in instead.');
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
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.pinkGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentPink.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_add_outlined,
                      color: Colors.white, size: 34),
                ),
                const SizedBox(height: 32),
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
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmC,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _signup(),
                  decoration: const InputDecoration(
                    hintText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 28),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _signup,
                        child: const Text('Create Account'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
