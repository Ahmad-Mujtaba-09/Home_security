// Unit tests for data/models.dart — UserProfile and HistoryEvent.

import 'package:flutter_test/flutter_test.dart';
import 'package:safeguard_mobile/data/models.dart';

void main() {
  group('UserProfile', () {
    test('fromJson parses all fields', () {
      final p = UserProfile.fromJson({
        'id': 'user-1',
        'light_mode': true,
        'child_module_enabled': false,
        'elderly_module_enabled': true,
      });
      expect(p.id, 'user-1');
      expect(p.lightMode, true);
      expect(p.childModuleEnabled, false);
      expect(p.elderlyModuleEnabled, true);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final p = UserProfile.fromJson({'id': 'u'});
      expect(p.lightMode, false);
      expect(p.childModuleEnabled, true);
      expect(p.elderlyModuleEnabled, true);
    });

    test('toJson round-trips', () {
      const original = UserProfile(
        id: 'u',
        lightMode: true,
        childModuleEnabled: false,
        elderlyModuleEnabled: false,
      );
      final restored = UserProfile.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.lightMode, original.lightMode);
      expect(restored.childModuleEnabled, original.childModuleEnabled);
      expect(restored.elderlyModuleEnabled, original.elderlyModuleEnabled);
    });

    test('copyWith preserves id and only changes given fields', () {
      const p = UserProfile(id: 'u');
      final p2 = p.copyWith(childModuleEnabled: false);
      expect(p2.id, 'u');
      expect(p2.childModuleEnabled, false);
      expect(p2.elderlyModuleEnabled, true);
      expect(p2.lightMode, false);
    });
  });

  group('HistoryEvent', () {
    HistoryEvent make({String type = 'FALL'}) => HistoryEvent.fromJson({
          'id': 'e1',
          'user_id': 'u1',
          'event_type': type,
          'confidence': 0.87,
          'frame_count': 42,
          'timestamp': '2026-05-05T12:00:00Z',
        });

    test('fromJson parses fields', () {
      final e = make();
      expect(e.id, 'e1');
      expect(e.userId, 'u1');
      expect(e.eventType, 'FALL');
      expect(e.confidence, closeTo(0.87, 1e-9));
      expect(e.frameCount, 42);
      expect(e.timestamp.toUtc().year, 2026);
    });

    test('displayLabel renders known event types', () {
      expect(make(type: 'FALL').displayLabel, contains('Fall'));
      expect(make(type: 'INACTIVITY').displayLabel, contains('Inactivity'));
      expect(make(type: 'CHILD_HAZARD').displayLabel, contains('Child'));
    });

    test('displayLabel falls back to humanised event type', () {
      expect(make(type: 'CUSTOM_THING').displayLabel, 'CUSTOM THING');
    });

    test('notificationBody differs per type', () {
      final fall = make(type: 'FALL').notificationBody;
      final inactivity = make(type: 'INACTIVITY').notificationBody;
      expect(fall, isNot(equals(inactivity)));
      expect(fall.toLowerCase(), contains('fall'));
    });

    test('notificationBody has default for unknown types', () {
      expect(make(type: 'OTHER').notificationBody, isNotEmpty);
    });

    test('fromJson handles null confidence and frame_count', () {
      final e = HistoryEvent.fromJson({
        'id': 'e2',
        'user_id': 'u1',
        'event_type': 'FALL',
        'confidence': null,
        'frame_count': null,
        'timestamp': '2026-05-05T12:00:00Z',
      });
      expect(e.confidence, isNull);
      expect(e.frameCount, isNull);
    });
  });

  // ─── Device ──────────────────────────────────────────────────────────────

  group('Device', () {
    test('fromJson parses all fields', () {
      final d = Device.fromJson({
        'device_id': 'd1',
        'user_id': 'u1',
        'device_name': 'Living Room',
        'device_type': 'rtsp',
        'stream_url': 'rtsp://camera.local',
        'location': 'Living room',
        'status': 'active',
        'last_seen': '2026-05-05T12:00:00Z',
        'created_at': '2026-05-01T10:00:00Z',
      });
      expect(d.deviceId, 'd1');
      expect(d.userId, 'u1');
      expect(d.deviceName, 'Living Room');
      expect(d.deviceType, 'rtsp');
      expect(d.streamUrl, 'rtsp://camera.local');
      expect(d.location, 'Living room');
      expect(d.status, 'active');
      expect(d.lastSeen, isNotNull);
      expect(d.createdAt, isNotNull);
    });

    test('fromJson applies defaults for optional fields', () {
      final d = Device.fromJson({
        'device_id': 'd2',
        'user_id': 'u1',
        'device_name': 'Cam',
      });
      expect(d.deviceType, 'camera');
      expect(d.status, 'inactive');
      expect(d.streamUrl, isNull);
      expect(d.location, isNull);
      expect(d.lastSeen, isNull);
    });

    test('toCreateJson omits empty stream_url and location', () {
      const d = Device(
        deviceId: '',
        userId: 'u1',
        deviceName: 'Test',
        streamUrl: '',
        location: '',
      );
      final json = d.toCreateJson();
      expect(json.containsKey('stream_url'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json['user_id'], 'u1');
      expect(json['device_name'], 'Test');
    });

    test('toCreateJson includes non-empty stream_url', () {
      const d = Device(
        deviceId: '',
        userId: 'u1',
        deviceName: 'Cam',
        streamUrl: 'rtsp://x',
      );
      expect(d.toCreateJson()['stream_url'], 'rtsp://x');
    });
  });

  // ─── NotificationItem ───────────────────────────────────────────────────

  group('NotificationItem', () {
    test('fromJson parses all fields', () {
      final n = NotificationItem.fromJson({
        'notification_id': 'n1',
        'user_id': 'u1',
        'event_id': 'e1',
        'title': 'Fall Detected',
        'message': 'Confidence: 95%',
        'notification_type': 'FALL',
        'sent_at': '2026-05-05T12:00:00Z',
        'read_status': true,
      });
      expect(n.notificationId, 'n1');
      expect(n.eventId, 'e1');
      expect(n.title, 'Fall Detected');
      expect(n.readStatus, true);
    });

    test('fromJson defaults read_status to false', () {
      final n = NotificationItem.fromJson({
        'notification_id': 'n2',
        'user_id': 'u1',
        'title': 'Alert',
        'message': 'Body',
        'sent_at': '2026-05-05T12:00:00Z',
      });
      expect(n.readStatus, false);
      expect(n.eventId, isNull);
    });

    test('copyWith updates read_status only', () {
      final n = NotificationItem.fromJson({
        'notification_id': 'n1',
        'user_id': 'u1',
        'title': 'T',
        'message': 'M',
        'sent_at': '2026-05-05T12:00:00Z',
        'read_status': false,
      });
      final updated = n.copyWith(readStatus: true);
      expect(updated.readStatus, true);
      expect(updated.notificationId, 'n1');
      expect(updated.title, 'T');
    });
  });

  // ─── IncidentSummary ────────────────────────────────────────────────────

  group('IncidentSummary', () {
    test('fromJson parses fields', () {
      final s = IncidentSummary.fromJson({
        'summary_id': 's1',
        'user_id': 'u1',
        'start_time': '2026-05-04T00:00:00Z',
        'end_time': '2026-05-05T00:00:00Z',
        'summary_text': 'No incidents today.',
        'incident_count': 3,
        'generated_at': '2026-05-05T01:00:00Z',
      });
      expect(s.summaryId, 's1');
      expect(s.summaryText, 'No incidents today.');
      expect(s.incidentCount, 3);
    });

    test('fromJson defaults incident_count to 0', () {
      final s = IncidentSummary.fromJson({
        'summary_id': 's2',
        'user_id': 'u1',
        'start_time': '2026-05-04T00:00:00Z',
        'end_time': '2026-05-05T00:00:00Z',
        'summary_text': 'Report',
        'generated_at': '2026-05-05T01:00:00Z',
      });
      expect(s.incidentCount, 0);
    });
  });

  // ─── ChatSession ────────────────────────────────────────────────────────

  group('ChatSession', () {
    test('fromJson parses fields', () {
      final cs = ChatSession.fromJson({
        'session_id': 'cs1',
        'user_id': 'u1',
        'title': 'First aid',
        'started_at': '2026-05-05T12:00:00Z',
        'ended_at': '2026-05-05T13:00:00Z',
      });
      expect(cs.sessionId, 'cs1');
      expect(cs.title, 'First aid');
      expect(cs.endedAt, isNotNull);
    });

    test('fromJson handles null optional fields', () {
      final cs = ChatSession.fromJson({
        'session_id': 'cs2',
        'user_id': 'u1',
        'started_at': '2026-05-05T12:00:00Z',
      });
      expect(cs.title, isNull);
      expect(cs.endedAt, isNull);
    });
  });

  // ─── ChatMessage ────────────────────────────────────────────────────────

  group('ChatMessage', () {
    test('fromJson parses all fields', () {
      final cm = ChatMessage.fromJson({
        'message_id': 'm1',
        'session_id': 'cs1',
        'sender': 'user',
        'message_text': 'How to treat a burn?',
        'sources': [{'book': 'FirstAid', 'page': 1}],
        'timestamp': '2026-05-05T12:05:00Z',
      });
      expect(cm.messageId, 'm1');
      expect(cm.sender, 'user');
      expect(cm.messageText, 'How to treat a burn?');
      expect(cm.sources, isNotNull);
      expect(cm.sources!.length, 1);
    });

    test('fromJson handles null sources', () {
      final cm = ChatMessage.fromJson({
        'message_id': 'm2',
        'session_id': 'cs1',
        'sender': 'bot',
        'message_text': 'Run cool water.',
        'timestamp': '2026-05-05T12:06:00Z',
      });
      expect(cm.sources, isNull);
    });
  });
}
