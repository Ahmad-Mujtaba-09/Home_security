/// Application-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Intelligent Home Surveillance';

  // Supabase table names
  static const String profilesTable = 'profiles';
  static const String historyTable = 'history';

  // WebSocket paths
  static const String wsInferencePath = '/ws/inference';

  // REST paths
  static const String historyPath = '/api/history';
  static const String geminiReportPath = '/api/gemini-report';
  static const String profilePath = '/api/profile';
}
