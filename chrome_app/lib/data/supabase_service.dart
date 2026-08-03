import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'models.dart';

/// Wraps all Supabase interactions (auth + database).
class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  /// Cached profile so the top-level MaterialApp can read theme preference.
  UserProfile? _cachedProfile;
  UserProfile? get userProfile => _cachedProfile;

  // ── Current session helpers ────────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  String? get userId => currentUser?.id;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<AuthResponse> signUp(String email, String password) async {
    final res = await _client.auth.signUp(email: email, password: password);
    notifyListeners();
    return res;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    notifyListeners();
    return res;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    notifyListeners();
  }

  // ── Profile ────────────────────────────────────────────────────────────────

  Future<UserProfile?> fetchProfile() async {
    if (userId == null) return null;
    try {
      final res = await _client
          .from(AppConstants.profilesTable)
          .select()
          .eq('id', userId!)
          .single();
      _cachedProfile = UserProfile.fromJson(res);
      return _cachedProfile;
    } catch (e) {
      debugPrint('fetchProfile error: $e — attempting to create default profile');
      // Profile row doesn't exist yet (new user) — create one
      try {
        final defaultProfile = UserProfile(id: userId!);
        await _client
            .from(AppConstants.profilesTable)
            .upsert(defaultProfile.toJson());
        _cachedProfile = defaultProfile;
        return defaultProfile;
      } catch (createErr) {
        debugPrint('createProfile error: $createErr');
        // Even if DB insert fails, return a local default so the UI works
        _cachedProfile = UserProfile(id: userId!);
        return _cachedProfile;
      }
    }
  }

  Future<void> updateProfile(UserProfile profile) async {
    _cachedProfile = profile;
    notifyListeners(); // Notify immediately so theme switches instantly
    await _client
        .from(AppConstants.profilesTable)
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  // ── History ────────────────────────────────────────────────────────────────

  Future<List<HistoryEvent>> fetchHistory({int limit = 200}) async {
    if (userId == null) return [];
    try {
      final res = await _client
          .from(AppConstants.historyTable)
          .select()
          .eq('user_id', userId!)
          .order('timestamp', ascending: false)
          .limit(limit);
      return (res as List).map((e) => HistoryEvent.fromJson(e)).toList();
    } catch (e) {
      debugPrint('fetchHistory error: $e');
      return [];
    }
  }
}
