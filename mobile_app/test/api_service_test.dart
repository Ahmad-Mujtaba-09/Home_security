// Integration-style tests for ApiService.
//
// SharedPreferences is replaced with the in-memory mock so URL persistence
// can be exercised without touching real platform channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safeguard_mobile/data/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ApiService server URL persistence', () {
    test('default value is empty', () async {
      expect(await ApiService.getServerUrl(), isEmpty);
    });

    test('setServerUrl stores trimmed value', () async {
      await ApiService.setServerUrl('  http://example.com  ');
      expect(await ApiService.getServerUrl(), 'http://example.com');
    });

    test('setServerUrl strips trailing slashes', () async {
      await ApiService.setServerUrl('http://example.com///');
      expect(await ApiService.getServerUrl(), 'http://example.com');
    });

    test('setServerUrl with empty string clears it', () async {
      await ApiService.setServerUrl('http://x.com');
      await ApiService.setServerUrl('   ');
      expect(await ApiService.getServerUrl(), isEmpty);
    });
  });
}
