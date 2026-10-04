import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_122/main.dart';

void main() {
  testWidgets('CameraApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CameraApp());

    // Verify camera app loads (may show "Không tìm thấy camera" in test env)
    await tester.pump();
  });
}
