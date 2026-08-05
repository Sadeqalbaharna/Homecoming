/// Pure request assembly so capability guarantees can be behavior-tested
/// without making a network call or source-grepping AIService.
Map<String, dynamic> buildOpenAIToolRequest({
  required String model,
  required List<Map<String, dynamic>> messages,
  required List<Map<String, dynamic>> tools,
  required Map<String, dynamic> lengthParameters,
}) {
  return {
    'model': model,
    'messages': messages,
    if (tools.isNotEmpty) 'tools': tools,
    if (tools.isNotEmpty) 'tool_choice': 'auto',
    ...lengthParameters,
  };
}
