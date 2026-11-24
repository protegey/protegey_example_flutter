import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:protegey_example_flutter/main.dart';

void main() {
  testWidgets('renders the demo page title and action buttons', (WidgetTester tester) async {
    // A phone-sized surface: the buttons sit below the customer ID field, beyond the default
    // 800x600 test surface, where the lazy list doesn't build them.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProtegeyExampleApp());
    await tester.pump();

    expect(find.text('Protegey — Flutter example'), findsWidgets);
    expect(find.text('Report a behavioral event'), findsOneWidget);
    expect(find.text('Verify my identity'), findsOneWidget);
  });
}
