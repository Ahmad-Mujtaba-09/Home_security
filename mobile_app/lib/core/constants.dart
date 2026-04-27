/// Application-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'IHS Surveillance';

  // Supabase table names
  static const String profilesTable = 'profiles';
  static const String historyTable  = 'history';

  // Notification throttle duration (seconds)
  static const int notificationThrottleSecs = 60;
}
