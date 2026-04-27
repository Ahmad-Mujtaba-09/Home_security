// Data models for the IHS Surveillance App.

class UserProfile {
  final String id;
  final bool lightMode;
  final bool childModuleEnabled;
  final bool elderlyModuleEnabled;

  const UserProfile({
    required this.id,
    this.lightMode = false,
    this.childModuleEnabled = true,
    this.elderlyModuleEnabled = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      lightMode: json['light_mode'] as bool? ?? false,
      childModuleEnabled: json['child_module_enabled'] as bool? ?? true,
      elderlyModuleEnabled: json['elderly_module_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'light_mode': lightMode,
        'child_module_enabled': childModuleEnabled,
        'elderly_module_enabled': elderlyModuleEnabled,
      };

  UserProfile copyWith({
    bool? lightMode,
    bool? childModuleEnabled,
    bool? elderlyModuleEnabled,
  }) =>
      UserProfile(
        id: id,
        lightMode: lightMode ?? this.lightMode,
        childModuleEnabled: childModuleEnabled ?? this.childModuleEnabled,
        elderlyModuleEnabled:
            elderlyModuleEnabled ?? this.elderlyModuleEnabled,
      );
}

class HistoryEvent {
  final String id;
  final String userId;
  final String eventType;
  final double? confidence;
  final int? frameCount;
  final DateTime timestamp;

  const HistoryEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    this.confidence,
    this.frameCount,
    required this.timestamp,
  });

  factory HistoryEvent.fromJson(Map<String, dynamic> json) {
    return HistoryEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      eventType: json['event_type'] as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
      frameCount: json['frame_count'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Human-readable label for the UI.
  String get displayLabel {
    switch (eventType) {
      case 'FALL':
        return '⚠️ Fall Detected';
      case 'INACTIVITY':
        return '🔴 Prolonged Inactivity';
      case 'CHILD_HAZARD':
        return '🚸 Child Near Hazard';
      default:
        return eventType.replaceAll('_', ' ');
    }
  }

  /// Short notification body text.
  String get notificationBody {
    switch (eventType) {
      case 'FALL':
        return 'A fall has been detected. Please check on your family member immediately.';
      case 'INACTIVITY':
        return 'Unusual inactivity detected. Consider checking in.';
      case 'CHILD_HAZARD':
        return 'A child was spotted near a potentially dangerous object.';
      default:
        return 'A new event was recorded in your monitoring history.';
    }
  }
}
