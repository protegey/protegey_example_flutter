import 'package:flutter_test/flutter_test.dart';

import 'package:protegey_example_flutter/main.dart';

void main() {
  testWidgets('renders the demo page title and action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const ProtegeyExampleApp());
    await tester.pump();

    expect(find.text('Protegey — Flutter example'), findsWidgets);
    expect(find.text('Report a test transaction'), findsOneWidget);
    expect(find.text('Verify my identity'), findsOneWidget);
  });
}
