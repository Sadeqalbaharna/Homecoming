// Firebase Service - Integrates with existing Firebase Realtime Database
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../ai/usage_tracking_service.dart';

class FirebaseService {
  static FirebaseDatabase? _database;
  static bool _initialized = false;

  /// Initialize Firebase (call this once at app startup)
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await Firebase.initializeApp();
      _database = FirebaseDatabase.instance;
      _database!.setPersistenceEnabled(true); // offline cache — replaces SharedPreferences fallback
      _initialized = true;
      print('✅ Firebase initialized successfully');
    } catch (e) {
      print('⚠️ Firebase initialization failed: $e');
      print('📱 App will work with local storage only');
    }
  }

  /// Check if Firebase is available
  static bool get isAvailable => _initialized && _database != null;

  /// Save personality data to Firebase
  static Future<void> savePersonalityData({
    required String personaId,
    required Map<String, dynamic> personalityData,
  }) async {
    if (!isAvailable) {
      print('📱 Firebase not available, skipping cloud save');
      return;
    }

    try {
      final ref = _database!.ref('personalities/$personaId');
      await ref.set({
        ...personalityData,
        'lastUpdated': ServerValue.timestamp,
        'version': '1.0.0',
      });
      
      // Track Firebase write
      await UsageTrackingService.trackFirebaseDatabase(reads: 0, writes: 1);
      
      print('✅ Personality data saved to Firebase for $personaId');
    } catch (e) {
      print('⚠️ Failed to save to Firebase: $e');
    }
  }

  /// Load personality data from Firebase
  static Future<Map<String, dynamic>?> loadPersonalityData(String personaId) async {
    if (!isAvailable) {
      print('📱 Firebase not available, using local data only');
      return null;
    }

    try {
      final ref = _database!.ref('personalities/$personaId');
      final snapshot = await ref.get();
      
      // Track Firebase read
      await UsageTrackingService.trackFirebaseDatabase(reads: 1, writes: 0);
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print('✅ Personality data loaded from Firebase for $personaId');
        return data;
      } else {
        print('📝 No Firebase data found for $personaId');
        return null;
      }
    } catch (e) {
      print('⚠️ Failed to load from Firebase: $e');
      return null;
    }
  }

  /// Save conversation history to Firebase
  static Future<void> saveConversation({
    required String personaId,
    required String userMessage,
    required String aiResponse,
    required Map<String, int> personalityDeltas,
  }) async {
    if (!isAvailable) return;

    try {
      final ref = _database!.ref('conversations/$personaId').push();
      await ref.set({
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'personalityDeltas': personalityDeltas,
        'timestamp': ServerValue.timestamp,
      });
      
      // Track Firebase write
      await UsageTrackingService.trackFirebaseDatabase(reads: 0, writes: 1);
      
      print('✅ Conversation saved to Firebase');
    } catch (e) {
      print('⚠️ Failed to save conversation: $e');
    }
  }

  /// Get recent conversations from Firebase
  static Future<List<Map<String, dynamic>>> getRecentConversations(
    String personaId, {
    int limit = 10,
  }) async {
    if (!isAvailable) return [];

    try {
      final ref = _database!.ref('conversations/$personaId')
          .orderByChild('timestamp')
          .limitToLast(limit);
      
      final snapshot = await ref.get();
      
      // Track Firebase read
      await UsageTrackingService.trackFirebaseDatabase(reads: 1, writes: 0);
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final conversations = data.entries
            .map((e) => {
                  'id': e.key,
                  ...Map<String, dynamic>.from(e.value as Map),
                })
            .toList();
        
        // Sort by timestamp (newest first)
        conversations.sort((a, b) => 
            (b['timestamp'] as int? ?? 0).compareTo(a['timestamp'] as int? ?? 0));
        
        print('✅ Loaded ${conversations.length} conversations from Firebase');
        return conversations;
      }
    } catch (e) {
      print('⚠️ Failed to load conversations: $e');
    }
    
    return [];
  }

  /// Save app analytics/usage data
  static Future<void> logAppUsage({
    required String action,
    Map<String, dynamic>? additionalData,
  }) async {
    if (!isAvailable) return;

    try {
      final ref = _database!.ref('analytics').push();
      await ref.set({
        'action': action,
        'timestamp': ServerValue.timestamp,
        'data': additionalData ?? {},
      });
    } catch (e) {
      print('⚠️ Failed to log analytics: $e');
    }
  }

  /// Get app usage statistics
  static Future<Map<String, dynamic>> getUsageStats() async {
    if (!isAvailable) return {};

    try {
      final ref = _database!.ref('analytics')
          .orderByChild('timestamp')
          .limitToLast(100);
      
      final snapshot = await ref.get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        
        // Process analytics data
        final actions = <String, int>{};
        data.forEach((key, value) {
          final item = Map<String, dynamic>.from(value as Map);
          final action = item['action'] as String? ?? 'unknown';
          actions[action] = (actions[action] ?? 0) + 1;
        });
        
        return {
          'totalEvents': data.length,
          'actionCounts': actions,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      print('⚠️ Failed to get usage stats: $e');
    }
    
    return {};
  }

  /// Generic read — returns raw snapshot value or null.
  static Future<dynamic> readData(String path) async {
    if (!isAvailable) return null;
    try {
      await UsageTrackingService.trackFirebaseDatabase(reads: 1, writes: 0);
      final ref = _database!.ref(path);
      final snapshot = await ref.get();
      return snapshot.exists ? snapshot.value : null;
    } catch (e) {
      print('⚠️ [Firebase] readData($path) failed: $e');
      return null;
    }
  }

  /// Generic write — sets data at [path].
  static Future<void> writeData({
    required String path,
    required Map<String, dynamic> data,
  }) async {
    if (!isAvailable) return;
    try {
      await UsageTrackingService.trackFirebaseDatabase(reads: 0, writes: 1);
      await _database!.ref(path).set(data);
    } catch (e) {
      print('⚠️ [Firebase] writeData($path) failed: $e');
    }
  }

  /// Sync local data with Firebase
  static Future<void> syncWithFirebase(String personaId, Map<String, dynamic> localData) async {
    if (!isAvailable) return;

    // Load Firebase data
    final firebaseData = await loadPersonalityData(personaId);
    
    if (firebaseData != null) {
      final firebaseTimestamp = firebaseData['lastUpdated'] as int? ?? 0;
      final localTimestamp = localData['lastUpdated'] as int? ?? 0;
      
      if (firebaseTimestamp > localTimestamp) {
        print('🔄 Firebase data is newer, using cloud data');
        // Return firebase data for the app to use
      } else {
        print('🔄 Local data is newer, updating Firebase');
        await savePersonalityData(personaId: personaId, personalityData: localData);
      }
    } else {
      print('🔄 No Firebase data, uploading local data');
      await savePersonalityData(personaId: personaId, personalityData: localData);
    }
  }
}