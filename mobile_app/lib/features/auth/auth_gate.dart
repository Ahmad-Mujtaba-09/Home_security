import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Routes the user to [HomeShell] if authenticated, [LoginScreen] otherwise.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const HomeShell();
        }
        return const LoginScreen();
      },
    );
  }
}
