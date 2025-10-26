import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/usage_tracking_service.dart';

/// Full-screen locked expanded window with tabs: Chat, Personality, Analytics
/// Unmovable and fills entire screen for stable interaction
class ExpandedWindow extends StatefulWidget {
  final String personaId;
  final VoidCallback onClose;
  final Function(String) onSendMessage;
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final ScrollController scrollController;
  final int initialTab; // NEW: Which tab to show initially

  const ExpandedWindow({
    super.key,
    required this.personaId,
    required this.onClose,
    required this.onSendMessage,
    required this.messages,
    required this.isLoading,
    required this.scrollController,
    this.initialTab = 0, // Default to Chat tab
  });

  @override
  State<ExpandedWindow> createState() => _ExpandedWindowState();
}

class _ExpandedWindowState extends State<ExpandedWindow> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Personality state
  Map<String, int> _personality = {};
  Map<String, int> _mood = {};
  String _mbti = 'ENFP';
  bool _loadingPersonality = true;
  
  // Analytics state
  Map<String, dynamic> _usageStats = {};
  bool _loadingAnalytics = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab, // Start at specified tab
    );
    _tabController.addListener(_onTabChanged);
    _loadPersonalityData();
    _loadAnalyticsData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      _loadPersonalityData(); // Refresh when switching to personality
    } else if (_tabController.index == 2) {
      _loadAnalyticsData(); // Refresh when switching to analytics
    }
  }

  Future<void> _loadPersonalityData() async {
    setState(() => _loadingPersonality = true);
    try {
      final aiService = AIService();
      final personality = await aiService.getPersonality(widget.personaId);
      final mood = await aiService.getMood(widget.personaId);
      final mbti = aiService.calculateMBTI(personality);
      
      setState(() {
        _personality = personality;
        _mood = mood;
        _mbti = mbti;
        _loadingPersonality = false;
      });
    } catch (e) {
      print('❌ Failed to load personality: $e');
      setState(() => _loadingPersonality = false);
    }
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _loadingAnalytics = true);
    try {
      final stats = await UsageTrackingService.getUsageStats();
      setState(() {
        _usageStats = stats;
        _loadingAnalytics = false;
      });
    } catch (e) {
      print('❌ Failed to load analytics: $e');
      setState(() => _loadingAnalytics = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Column(
        children: [
          // Header with close button
          _buildHeader(),
          
          // Tab bar
          _buildTabBar(),
          
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChatTab(),
                _buildPersonalityTab(),
                _buildAnalyticsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(color: Colors.purple.withOpacity(0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purple, size: 24),
          const SizedBox(width: 12),
          const Text(
            'Kai AI Companion',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: widget.onClose,
            tooltip: 'Close expanded view',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.grey[900],
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.purple,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(
            icon: Icon(Icons.chat_bubble_outline),
            text: 'Chat',
          ),
          Tab(
            icon: Icon(Icons.psychology_outlined),
            text: 'Personality',
          ),
          Tab(
            icon: Icon(Icons.analytics_outlined),
            text: 'Analytics',
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Messages list
          Expanded(
            child: widget.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation with Kai',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final msg = widget.messages[index];
                      final isUser = msg['role'] == 'user';
                      return _buildMessageBubble(
                        msg['content'] as String,
                        isUser,
                        msg['timestamp'] as DateTime?,
                        msg['memoriesUsed'] as List<String>?,
                      );
                    },
                  ),
          ),
          
          // Loading indicator
          if (widget.isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Kai is thinking...',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          
          // Input field
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    String content,
    bool isUser,
    DateTime? timestamp,
    List<String>? memoriesUsed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Timestamp
          if (timestamp != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _formatTimestamp(timestamp),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ),
          
          // Message bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? Colors.purple.withOpacity(0.2)
                  : Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUser
                    ? Colors.purple.withOpacity(0.5)
                    : Colors.grey[800]!,
                width: 1,
              ),
            ),
            child: Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
          
          // Memory badge
          if (!isUser && memoriesUsed != null && memoriesUsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.memory,
                      size: 12,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Used ${memoriesUsed.length} ${memoriesUsed.length == 1 ? 'memory' : 'memories'}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildMessageInput() {
    final controller = TextEditingController();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          top: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Message Kai...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  widget.onSendMessage(text.trim());
                  controller.clear();
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  widget.onSendMessage(text);
                  controller.clear();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalityTab() {
    if (_loadingPersonality) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.purple),
      );
    }

    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // MBTI Type
            _buildSectionHeader('Personality Type'),
            _buildMBTICard(),
            const SizedBox(height: 24),
            
            // Personality Traits
            _buildSectionHeader('Core Traits'),
            _buildTraitsList(_personality, PersonalityTraits.personality),
            const SizedBox(height: 24),
            
            // Mood
            _buildSectionHeader('Current Mood'),
            _buildTraitsList(_mood, PersonalityTraits.mood),
            const SizedBox(height: 24),
            
            // Actions
            _buildActionsRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMBTICard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withOpacity(0.2),
            Colors.blue.withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.purple.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            _mbti,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getMBTIDescription(_mbti),
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getMBTIDescription(String mbti) {
    final descriptions = {
      'ENFP': 'The Campaigner - Enthusiastic, creative, and sociable',
      'INFP': 'The Mediator - Poetic, kind, and altruistic',
      'ENFJ': 'The Protagonist - Charismatic and inspiring leaders',
      'INFJ': 'The Advocate - Quiet and mystical, yet inspiring',
      'ENTP': 'The Debater - Smart and curious thinkers',
      'INTP': 'The Logician - Innovative inventors with unquenchable thirst',
      'ENTJ': 'The Commander - Bold, imaginative, and strong-willed',
      'INTJ': 'The Architect - Strategic, rational problem-solvers',
      'ESFP': 'The Entertainer - Spontaneous, energetic, and enthusiastic',
      'ISFP': 'The Adventurer - Flexible and charming artists',
      'ESFJ': 'The Consul - Caring, social, and popular',
      'ISFJ': 'The Defender - Dedicated and warm protectors',
      'ESTP': 'The Entrepreneur - Perceptive, direct, and bold',
      'ISTP': 'The Virtuoso - Bold and practical experimenters',
      'ESTJ': 'The Executive - Excellent administrators',
      'ISTJ': 'The Logistician - Practical and fact-minded',
    };
    return descriptions[mbti] ?? 'Unique personality type';
  }

  Widget _buildTraitsList(Map<String, int> traits, List<String> traitNames) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Column(
        children: traitNames.map((trait) {
          final value = traits[trait] ?? 50;
          return _buildTraitItem(trait, value);
        }).toList(),
      ),
    );
  }

  Widget _buildTraitItem(String trait, int value) {
    final color = _getTraitColor(value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _capitalize(trait),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTraitColor(int value) {
    if (value >= 70) return Colors.green;
    if (value >= 50) return Colors.blue;
    if (value >= 30) return Colors.orange;
    return Colors.red;
  }

  String _capitalize(String text) {
    return text[0].toUpperCase() + text.substring(1);
  }

  Widget _buildActionsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _loadPersonalityData,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsTab() {
    if (_loadingAnalytics) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.purple),
      );
    }

    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Usage Statistics'),
            _buildStatCard(
              'Total Messages',
              _usageStats['totalMessages']?.toString() ?? '0',
              Icons.chat_bubble_outline,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'OpenAI Cost',
              '\$${(_usageStats['openaiCost'] ?? 0.0).toStringAsFixed(4)}',
              Icons.attach_money,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'ElevenLabs Characters',
              _usageStats['elevenlabsChars']?.toString() ?? '0',
              Icons.record_voice_over,
              Colors.purple,
            ),
            const SizedBox(height: 24),
            
            _buildSectionHeader('Recent Activity'),
            _buildActivityList(),
            const SizedBox(height: 24),
            
            ElevatedButton.icon(
              onPressed: _loadAnalyticsData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Stats'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    // Mock data - replace with real activity from Firebase
    final activities = [
      {'action': 'Message sent', 'time': '2 min ago', 'icon': Icons.send},
      {'action': 'Personality updated', 'time': '15 min ago', 'icon': Icons.psychology},
      {'action': 'Voice generated', 'time': '1 hour ago', 'icon': Icons.volume_up},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Column(
        children: activities.map((activity) {
          return ListTile(
            leading: Icon(
              activity['icon'] as IconData,
              color: Colors.purple,
            ),
            title: Text(
              activity['action'] as String,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              activity['time'] as String,
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }).toList(),
      ),
    );
  }
}
