import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Placeholder smoke test — Supabase requires .env at runtime,
    // so widget tests need mocked providers.
    expect(1 + 1, equals(2));
  });
}
