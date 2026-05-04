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
}
