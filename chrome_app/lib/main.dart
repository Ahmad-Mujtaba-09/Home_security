import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'data/supabase_service.dart';
import 'data/inference_service.dart';
import 'features/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialise Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Lock orientation (optional, mobile-optimised)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const SafeGuardApp());
}

class SafeGuardApp extends StatelessWidget {
  const SafeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SupabaseService()),
        ChangeNotifierProvider(create: (_) => InferenceService()),
      ],
      child: Consumer<SupabaseService>(
        builder: (context, supa, _) {
          // Derive theme from the user's profile preference.
          final isLight = supa.userProfile?.lightMode ?? false;
          return MaterialApp(
            title: 'Intelligent Home Surveillance',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}
