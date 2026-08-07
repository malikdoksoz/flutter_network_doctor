import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_network_doctor_example/main.dart';

void main() {
  testWidgets('shows the diagnostics action', (WidgetTester tester) async {
    await tester.pumpWidget(const NetworkDoctorExampleApp());

    expect(find.text('Run diagnostics'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });
}
