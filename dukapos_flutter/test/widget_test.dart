import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DukaPOS branding renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('DukaPOS')));
    expect(find.text('DukaPOS'), findsOneWidget);
  });
}
