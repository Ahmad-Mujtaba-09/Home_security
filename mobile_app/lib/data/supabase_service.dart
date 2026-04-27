import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'models.dart';

/// Wraps all Supabase interactions (auth + database + realtime).
class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  /// Cached profile so the app can read theme preference synchronously.
  UserProfile? _cachedProfile;
  UserProfile? get userProfile => _cachedProfile;

  /// Real-time history stream.
  final _historyController = StreamController<HistoryEvent>.broadcast();
  Stream<HistoryEvent> get historyStream => _historyController.stream;
  RealtimeChannel? _historyChannel;

  // ── Current session helpers ──────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  String? get userId => currentUser?.id;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Auth ─────────────────────────────────────────────────────────────────

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
    unsubscribeHistory();
    await _client.auth.signOut();
    _cachedProfile = null;
    notifyListeners();
  }

  // ── Profile ──────────────────────────────────────────────────────────────

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
      debugPrint('fetchProfile error: $e — creating default profile');
      try {
        final defaultProfile = UserProfile(id: userId!);
        await _client
            .from(AppConstants.profilesTable)
            .upsert(defaultProfile.toJson());
        _cachedProfile = defaultProfile;
        return defaultProfile;
      } catch (createErr) {
        debugPrint('createProfile error: $createErr');
        _cachedProfile = UserProfile(id: userId!);
        return _cachedProfile;
      }
    }
  }

  Future<void> updateProfile(UserProfile profile) async {
    _cachedProfile = profile;
    notifyListeners();
    await _client
        .from(AppConstants.profilesTable)
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  // ── History ──────────────────────────────────────────────────────────────

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

  // ── Realtime ─────────────────────────────────────────────────────────────

  /// Start listening to INSERT events on the history table for the current user.
  void subscribeToHistory() {
    if (userId == null) return;

    _historyChannel = _client
        .channel('history_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: AppConstants.historyTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId!,
          ),
          callback: (payload) {
            try {
              final event = HistoryEvent.fromJson(payload.newRecord);
              _historyController.add(event);
              notifyListeners();
            } catch (e) {
              debugPrint('Realtime parse error: $e');
            }
          },
        )
        .subscribe();
  }

  /// Stop the realtime listener.
  void unsubscribeHistory() {
    if (_historyChannel != null) {
      _client.removeChannel(_historyChannel!);
      _historyChannel = null;
    }
  }

  @override
  void dispose() {
    unsubscribeHistory();
    _historyController.close();
    super.dispose();
  }
}
