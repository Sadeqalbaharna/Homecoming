import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

void main() {
  test('job_done says when there was no open job', () async {
    final result = await ToolExecutorService().execute('job_done', const {});

    expect(result, 'No open job to close.');
  });

  test('scout_score forwards operatorFit instead of silently killing candidates', () async {
    final result = await ToolExecutorService().execute('scout_score', {
      'candidates': [
        {
          'name': 'boring checklist template',
          'market': 'small operators',
          'distribution': 3,
          'monetization': 3,
          'headroom': 3,
          'feasibility': 3,
          'operatorFit': 3,
          'evidence': [
            {
              'kind': 'paidPrice',
              'source': 'https://example.com/listing',
              'claim': 'A comparable checklist template is sold for a small price.',
              'value': 5,
            },
            {
              'kind': 'complaint',
              'source': 'https://forum.example.org/thread',
              'claim': 'A buyer complained existing templates are too complicated.',
            },
            {
              'kind': 'salesCount',
              'source': 'https://market.example.net/stats',
              'claim': 'Comparable product has visible sales/review traction.',
              'value': 12,
            },
          ],
        }
      ],
    });

    expect(result, contains('STRONG — boring checklist template'));
    expect(result, isNot(contains('operatorFit 0/5')));
  });
}
