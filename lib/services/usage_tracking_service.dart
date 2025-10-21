import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to track API usage, tokens, and costs
class UsageTrackingService {
  static const String _storageKey = 'api_usage_tracking';
  
  // OpenAI Pricing (as of October 2025)
  static const Map<String, Map<String, double>> openAIPricing = {
    'gpt-4o': {
      'input': 2.50 / 1000000,  // $2.50 per 1M input tokens
      'output': 10.00 / 1000000, // $10.00 per 1M output tokens
    },
    'gpt-4o-mini': {
      'input': 0.150 / 1000000,  // $0.15 per 1M input tokens
      'output': 0.600 / 1000000, // $0.60 per 1M output tokens
    },
    'gpt-4-turbo': {
      'input': 10.00 / 1000000,  // $10.00 per 1M input tokens
      'output': 30.00 / 1000000, // $30.00 per 1M output tokens
    },
    'gpt-3.5-turbo': {
      'input': 0.50 / 1000000,   // $0.50 per 1M input tokens
      'output': 1.50 / 1000000,  // $1.50 per 1M output tokens
    },
    'text-embedding-3-small': {
      'input': 0.020 / 1000000,  // $0.02 per 1M tokens
      'output': 0.0,
    },
    'text-embedding-3-large': {
      'input': 0.130 / 1000000,  // $0.13 per 1M tokens
      'output': 0.0,
    },
  };

  // ElevenLabs Pricing (characters, not tokens)
  static const double elevenlabsCharacterCost = 0.30 / 1000; // $0.30 per 1000 characters

  /// Track OpenAI API usage
  static Future<void> trackOpenAI({
    required String model,
    required int inputTokens,
    required int outputTokens,
    required String operation, // 'chat', 'embedding', 'tags'
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);

    final pricing = openAIPricing[model] ?? openAIPricing['gpt-4o-mini']!;
    final inputCost = inputTokens * pricing['input']!;
    final outputCost = outputTokens * pricing['output']!;
    final totalCost = inputCost + outputCost;

    // Update totals
    data['total_tokens'] = (data['total_tokens'] as int) + inputTokens + outputTokens;
    data['total_cost'] = (data['total_cost'] as double) + totalCost;
    data['openai_cost'] = (data['openai_cost'] as double) + totalCost;

    // Update model-specific stats
    final models = data['models'] as Map<String, dynamic>;
    if (!models.containsKey(model)) {
      models[model] = {
        'input_tokens': 0,
        'output_tokens': 0,
        'total_cost': 0.0,
        'call_count': 0,
      };
    }
    
    final modelData = models[model] as Map<String, dynamic>;
    modelData['input_tokens'] = (modelData['input_tokens'] as int) + inputTokens;
    modelData['output_tokens'] = (modelData['output_tokens'] as int) + outputTokens;
    modelData['total_cost'] = (modelData['total_cost'] as double) + totalCost;
    modelData['call_count'] = (modelData['call_count'] as int) + 1;

    // Update operation-specific stats
    final operations = data['operations'] as Map<String, dynamic>;
    if (!operations.containsKey(operation)) {
      operations[operation] = {
        'count': 0,
        'tokens': 0,
        'cost': 0.0,
      };
    }
    
    final opData = operations[operation] as Map<String, dynamic>;
    opData['count'] = (opData['count'] as int) + 1;
    opData['tokens'] = (opData['tokens'] as int) + inputTokens + outputTokens;
    opData['cost'] = (opData['cost'] as double) + totalCost;

    // Update session stats
    final session = data['current_session'] as Map<String, dynamic>;
    session['tokens'] = (session['tokens'] as int) + inputTokens + outputTokens;
    session['cost'] = (session['cost'] as double) + totalCost;
    session['api_calls'] = (session['api_calls'] as int) + 1;

    await _saveUsageData(prefs, data);
  }

  /// Track ElevenLabs TTS usage
  static Future<void> trackElevenLabs({
    required int characterCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);

    final cost = characterCount * elevenlabsCharacterCost;

    data['elevenlabs_characters'] = (data['elevenlabs_characters'] as int) + characterCount;
    data['elevenlabs_cost'] = (data['elevenlabs_cost'] as double) + cost;
    data['total_cost'] = (data['total_cost'] as double) + cost;

    // Update session stats
    final session = data['current_session'] as Map<String, dynamic>;
    session['tts_characters'] = (session['tts_characters'] as int) + characterCount;
    session['cost'] = (session['cost'] as double) + cost;

    await _saveUsageData(prefs, data);
  }

  /// Get current usage statistics
  static Future<Map<String, dynamic>> getUsageStats() async {
    final prefs = await SharedPreferences.getInstance();
    return await _loadUsageData(prefs);
  }

  /// Get session statistics
  static Future<Map<String, dynamic>> getSessionStats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    return data['current_session'] as Map<String, dynamic>;
  }

  /// Reset session stats (call when app starts)
  static Future<void> resetSession() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    
    data['current_session'] = {
      'tokens': 0,
      'tts_characters': 0,
      'cost': 0.0,
      'api_calls': 0,
      'started_at': DateTime.now().toIso8601String(),
    };

    await _saveUsageData(prefs, data);
  }

  /// Reset all usage data
  static Future<void> resetAllStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Estimate cost for a message (before sending)
  static double estimateMessageCost({
    required String userMessage,
    required String systemPrompt,
    required String model,
    int estimatedResponseTokens = 150,
  }) {
    // Rough token estimation: 1 token ≈ 4 characters
    final inputTokens = ((userMessage.length + systemPrompt.length) / 4).ceil();
    final outputTokens = estimatedResponseTokens;

    final pricing = openAIPricing[model] ?? openAIPricing['gpt-4o-mini']!;
    final inputCost = inputTokens * pricing['input']!;
    final outputCost = outputTokens * pricing['output']!;
    
    return inputCost + outputCost;
  }

  /// Estimate TTS cost
  static double estimateTTSCost(String text) {
    return text.length * elevenlabsCharacterCost;
  }

  /// Get cost breakdown by category
  static Future<Map<String, double>> getCostBreakdown() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);

    return {
      'openai': data['openai_cost'] as double,
      'elevenlabs': data['elevenlabs_cost'] as double,
      'total': data['total_cost'] as double,
    };
  }

  /// Get usage by model
  static Future<Map<String, dynamic>> getModelUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    return data['models'] as Map<String, dynamic>;
  }

  /// Get usage by operation type
  static Future<Map<String, dynamic>> getOperationUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    return data['operations'] as Map<String, dynamic>;
  }

  /// Private: Load usage data
  static Future<Map<String, dynamic>> _loadUsageData(SharedPreferences prefs) async {
    final jsonStr = prefs.getString(_storageKey);
    
    if (jsonStr == null) {
      return _createEmptyUsageData();
    }

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      print('Error loading usage data: $e');
      return _createEmptyUsageData();
    }
  }

  /// Private: Save usage data
  static Future<void> _saveUsageData(SharedPreferences prefs, Map<String, dynamic> data) async {
    final jsonStr = jsonEncode(data);
    await prefs.setString(_storageKey, jsonStr);
  }

  /// Private: Create empty usage data structure
  static Map<String, dynamic> _createEmptyUsageData() {
    return {
      'total_tokens': 0,
      'total_cost': 0.0,
      'openai_cost': 0.0,
      'elevenlabs_cost': 0.0,
      'elevenlabs_characters': 0,
      'models': <String, dynamic>{},
      'operations': <String, dynamic>{},
      'current_session': {
        'tokens': 0,
        'tts_characters': 0,
        'cost': 0.0,
        'api_calls': 0,
        'started_at': DateTime.now().toIso8601String(),
      },
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// Get average cost per conversation
  static Future<double> getAverageCostPerConversation() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    
    final operations = data['operations'] as Map<String, dynamic>;
    final chatOp = operations['chat'] as Map<String, dynamic>?;
    
    if (chatOp == null || chatOp['count'] == 0) {
      return 0.0;
    }
    
    return (chatOp['cost'] as double) / (chatOp['count'] as int);
  }

  /// Get total API calls
  static Future<int> getTotalAPICalls() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _loadUsageData(prefs);
    
    int total = 0;
    final models = data['models'] as Map<String, dynamic>;
    for (final model in models.values) {
      total += (model as Map<String, dynamic>)['call_count'] as int;
    }
    
    return total;
  }

  /// Format cost as currency string
  static String formatCost(double cost) {
    if (cost < 0.01) {
      return '\$${(cost * 100).toStringAsFixed(4)}¢';
    }
    return '\$${cost.toStringAsFixed(4)}';
  }

  /// Format tokens with commas
  static String formatTokens(int tokens) {
    return tokens.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
