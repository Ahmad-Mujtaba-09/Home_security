// Data models for the Surveillance App.

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
}

/// Real-time alert received via WebSocket from the inference backend.
class DetectionAlert {
  final String type;
  final int? pid;
  final double? prob;
  final int frame;
  final String? hazard;
  final double? dist;

  const DetectionAlert({
    required this.type,
    this.pid,
    this.prob,
    required this.frame,
    this.hazard,
    this.dist,
  });

  factory DetectionAlert.fromJson(Map<String, dynamic> json) {
    return DetectionAlert(
      type: json['type'] as String? ?? 'UNKNOWN',
      pid: json['pid'] as int?,
      prob: (json['prob'] as num?)?.toDouble(),
      frame: json['frame'] as int? ?? 0,
      hazard: json['hazard'] as String?,
      dist: (json['dist'] as num?)?.toDouble(),
    );
  }

  /// Human-readable label for the UI.
  String get displayLabel {
    switch (type) {
      case 'FALL':
        return '⚠️ Fall Detected';
      case 'INACTIVITY':
        return '🔴 Inactivity Alert';
      case 'CHILD_HAZARD':
        return '🚸 Child Near ${hazard?.toUpperCase() ?? "HAZARD"}';
      default:
        return type;
    }
  }
}

// ─── Devices ─────────────────────────────────────────────────────────────────

class Device {
  final String deviceId;
  final String userId;
  final String deviceName;
  final String deviceType; // 'camera' | 'mobile' | 'rtsp' | 'other'
  final String? streamUrl;
  final String? location;
  final String status; // 'active' | 'inactive' | 'offline'
  final DateTime? lastSeen;
  final DateTime? createdAt;

  const Device({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    this.deviceType = 'camera',
    this.streamUrl,
    this.location,
    this.status = 'inactive',
    this.lastSeen,
    this.createdAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        deviceId: json['device_id'] as String,
        userId: json['user_id'] as String,
        deviceName: json['device_name'] as String,
        deviceType: json['device_type'] as String? ?? 'camera',
        streamUrl: json['stream_url'] as String?,
        location: json['location'] as String?,
        status: json['status'] as String? ?? 'inactive',
        lastSeen: json['last_seen'] == null
            ? null
            : DateTime.parse(json['last_seen'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toCreateJson() => {
        'user_id': userId,
        'device_name': deviceName,
        'device_type': deviceType,
        if (streamUrl != null && streamUrl!.isNotEmpty) 'stream_url': streamUrl,
        if (location != null && location!.isNotEmpty) 'location': location,
        'status': status,
      };
}

// ─── Notifications (in-app inbox) ────────────────────────────────────────────

class NotificationItem {
  final String notificationId;
  final String userId;
  final String? eventId;
  final String title;
  final String message;
  final String notificationType;
  final DateTime sentAt;
  final bool readStatus;

  const NotificationItem({
    required this.notificationId,
    required this.userId,
    this.eventId,
    required this.title,
    required this.message,
    this.notificationType = 'alert',
    required this.sentAt,
    this.readStatus = false,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        notificationId: json['notification_id'] as String,
        userId: json['user_id'] as String,
        eventId: json['event_id'] as String?,
        title: json['title'] as String,
        message: json['message'] as String,
        notificationType: json['notification_type'] as String? ?? 'alert',
        sentAt: DateTime.parse(json['sent_at'] as String),
        readStatus: json['read_status'] as bool? ?? false,
      );

  NotificationItem copyWith({bool? readStatus}) => NotificationItem(
        notificationId: notificationId,
        userId: userId,
        eventId: eventId,
        title: title,
        message: message,
        notificationType: notificationType,
        sentAt: sentAt,
        readStatus: readStatus ?? this.readStatus,
      );
}

// ─── Incident Summaries (cached AI reports) ──────────────────────────────────

class IncidentSummary {
  final String summaryId;
  final String userId;
  final DateTime startTime;
  final DateTime endTime;
  final String summaryText;
  final int incidentCount;
  final DateTime generatedAt;

  const IncidentSummary({
    required this.summaryId,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.summaryText,
    required this.incidentCount,
    required this.generatedAt,
  });

  factory IncidentSummary.fromJson(Map<String, dynamic> json) =>
      IncidentSummary(
        summaryId: json['summary_id'] as String,
        userId: json['user_id'] as String,
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: DateTime.parse(json['end_time'] as String),
        summaryText: json['summary_text'] as String,
        incidentCount: (json['incident_count'] as num?)?.toInt() ?? 0,
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}

// ─── Chat sessions / messages ────────────────────────────────────────────────

class ChatSession {
  final String sessionId;
  final String userId;
  final String? title;
  final DateTime startedAt;
  final DateTime? endedAt;

  const ChatSession({
    required this.sessionId,
    required this.userId,
    this.title,
    required this.startedAt,
    this.endedAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        sessionId: json['session_id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String?,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String),
      );
}

class ChatMessage {
  final String messageId;
  final String sessionId;
  final String sender; // 'user' | 'bot'
  final String messageText;
  final List<dynamic>? sources;
  final DateTime timestamp;

  const ChatMessage({
    required this.messageId,
    required this.sessionId,
    required this.sender,
    required this.messageText,
    this.sources,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        messageId: json['message_id'] as String,
        sessionId: json['session_id'] as String,
        sender: json['sender'] as String,
        messageText: json['message_text'] as String,
        sources: json['sources'] as List<dynamic>?,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
