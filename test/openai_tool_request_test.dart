import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/openai_tool_request.dart';

void main() {
  const messages = <Map<String, dynamic>>[
    {'role': 'user', 'content': 'hello'},
  ];

  test('tool-less request omits both schemas and tool_choice', () {
    final request = buildOpenAIToolRequest(
      model: 'test-model',
      messages: messages,
      tools: const [],
      lengthParameters: const {'max_tokens': 120},
    );

    expect(request, isNot(contains('tools')));
    expect(request, isNot(contains('tool_choice')));
    expect(request['max_tokens'], 120);
  });

  test('capable request sends schemas with automatic tool choice', () {
    final request = buildOpenAIToolRequest(
      model: 'test-model',
      messages: messages,
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'read_file'},
        },
      ],
      lengthParameters: const {'max_completion_tokens': 8000},
    );

    expect(request['tools'], hasLength(1));
    expect(request['tool_choice'], 'auto');
  });
}
