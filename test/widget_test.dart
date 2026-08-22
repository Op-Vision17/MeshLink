import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshlink/main.dart';

void main() {
  testWidgets('MeshLink renders home screen without crash', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MeshLinkApp(),
      ),
    );

    expect(find.text('MeshLink'), findsOneWidget);
  });
}
