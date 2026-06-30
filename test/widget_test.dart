import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mokoguard_ai/main.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MokoGuardApp()));

    // Verify that it loads successfully
    expect(find.text('MokoGuard AI'), findsWidgets);
  });
}
