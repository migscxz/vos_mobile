import 'package:flutter_test/flutter_test.dart';
import 'package:vos_mobile/app.dart'; // 👈 make sure path matches your lib/app.dart

void main() {
  testWidgets('VOSApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const VOSApp());

    // Basic smoke test: check if title text exists somewhere
    expect(find.text('VOS Mobile'), findsOneWidget);
  });
}
