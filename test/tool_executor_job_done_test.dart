import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

void main() {
  test('job_done says when there was no open job', () async {
    final result = await ToolExecutorService().execute('job_done', const {});

    expect(result, 'No open job to close.');
  });
}
