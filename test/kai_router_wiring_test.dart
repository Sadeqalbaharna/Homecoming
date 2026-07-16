import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AIService injects KaiRouterService route context into the system prompt', () {
    final source = File('lib/services/ai/ai_service.dart').readAsStringSync();

    expect(source, contains("import '../core/kai_router_service.dart';"));
    expect(source, contains('const KaiRouterService().decide('));
    expect(source, contains('routeDecision.promptBlock()'));
    expect(source, contains('hasImage: image != null && image.isNotEmpty'));
  });
}
