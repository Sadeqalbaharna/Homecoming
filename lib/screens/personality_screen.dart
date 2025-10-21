import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Affinity traits list
const List<String> _affinityTraits = ['intimacy', 'physicality'];

class PersonalityScreen extends StatefulWidget {
  final String personaId;

  const PersonalityScreen({
    super.key,
    this.personaId = 'truekai',
  });

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> with SingleTickerProviderStateMixin {
  final AIService _aiService = AIService();
  
  Map<String, int> _personality = {};
  Map<String, int> _mood = {};
  Map<String, int> _affinity = {};
  
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _loadState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    
    final personality = await _aiService.getPersonality(widget.personaId);
    final mood = await _aiService.getMood(widget.personaId);
    final affinity = await _aiService.getAffinity(widget.personaId);
    
    setState(() {
      _personality = personality;
      _mood = mood;
      _affinity = affinity;
      _isLoading = false;
    });
  }

  Future<void> _resetState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Personality State?'),
        content: const Text('This will reset Kai\'s personality, mood, and affinity to default values. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Clear all stored state
      final prefs = await SharedPreferences.getInstance();
      for (final trait in PersonalityTraits.personality) {
        await prefs.remove('${widget.personaId}_personality_$trait');
      }
      for (final trait in PersonalityTraits.mood) {
        await prefs.remove('${widget.personaId}_mood_$trait');
      }
      for (final trait in _affinityTraits) {
        await prefs.remove('${widget.personaId}_affinity_$trait');
      }
      
      await _loadState();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personality state has been reset to defaults')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kai\'s Personality State'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadState,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetState,
            tooltip: 'Reset to Defaults',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadState,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPersonalityCard(),
                  const SizedBox(height: 16),
                  _buildMoodCard(),
                  const SizedBox(height: 16),
                  _buildAffinityCard(),
                  const SizedBox(height: 16),
                  _buildRadarChart(),
                  const SizedBox(height: 16),
                  _buildLegendCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildPersonalityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology, size: 24, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'Personality Traits',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Core personality dimensions (0-1000)',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const Divider(height: 24),
            ..._personality.entries.map((entry) {
              return _buildTraitBar(
                entry.key,
                entry.value,
                1000,
                _getPersonalityColor(entry.key),
                _getPersonalityLabel(entry.key, entry.value),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.mood, size: 24, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Current Mood',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Emotional state (0-100)',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const Divider(height: 24),
            ..._mood.entries.map((entry) {
              return _buildTraitBar(
                entry.key,
                entry.value,
                100,
                _getMoodColor(entry.key),
                _getMoodLabel(entry.key, entry.value),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAffinityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.favorite, size: 24, color: Colors.pink),
                SizedBox(width: 8),
                Text(
                  'Affinity & Connection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Relationship depth (0-100)',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const Divider(height: 24),
            ..._affinity.entries.map((entry) {
              return _buildTraitBar(
                entry.key,
                entry.value,
                100,
                _getAffinityColor(entry.key),
                _getAffinityLabel(entry.key, entry.value),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTraitBar(String name, int value, int max, Color color, String label) {
    final percent = value / max;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FadeTransition(
        opacity: _animationController,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.2, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          )),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTraitName(name),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  Row(
                    children: [
                      // Edit button
                      IconButton(
                        icon: Icon(Icons.edit, size: 16, color: color),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _editTrait(name, value, max, color),
                        tooltip: 'Edit manually',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$value / $max',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTapDown: (details) => _handleBarTap(details, name, max, color),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTrait(String name, int currentValue, int max, Color color) async {
    final controller = TextEditingController(text: currentValue.toString());
    
    final newValue = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${_formatTraitName(name)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Value (0-$max)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Slider(
              value: int.tryParse(controller.text)?.toDouble() ?? currentValue.toDouble(),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              activeColor: color,
              label: controller.text,
              onChanged: (value) {
                controller.text = value.toInt().toString();
                setState(() {}); // Rebuild to update slider
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 0 && value <= max) {
                Navigator.pop(context, value);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Please enter a value between 0 and $max')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newValue != null) {
      await _saveTrait(name, newValue);
    }
  }

  void _handleBarTap(TapDownDetails details, String name, int max, Color color) {
    // Calculate value from tap position
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = details.localPosition;
    final width = box.size.width - 32; // Account for padding
    final percent = (localPosition.dx / width).clamp(0.0, 1.0);
    final newValue = (percent * max).round();
    
    _editTrait(name, newValue, max, color);
  }

  Future<void> _saveTrait(String name, int value) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Determine which category this trait belongs to
    String? category;
    if (PersonalityTraits.personality.contains(name)) {
      category = 'personality';
    } else if (PersonalityTraits.mood.contains(name)) {
      category = 'mood';
    } else if (_affinityTraits.contains(name)) {
      category = 'affinity';
    }

    if (category != null) {
      await prefs.setInt('${widget.personaId}_${category}_$name', value);
      await _loadState();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_formatTraitName(name)} updated to $value'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildRadarChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.radar, size: 24, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Personality Radar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: RadarChartPainter(
                  personality: _personality,
                  mood: _mood,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 24, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Understanding the Metrics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildLegendSection(
              'Personality Traits',
              [
                'Extraversion: Social energy and expressiveness',
                'Intuition: Abstract thinking and imagination',
                'Feeling: Emotional sensitivity and empathy',
                'Perceiving: Flexibility and spontaneity',
              ],
              Colors.purple,
            ),
            const SizedBox(height: 16),
            _buildLegendSection(
              'Mood States',
              [
                'Valence: Positive vs negative emotional tone',
                'Energy: Activity level and enthusiasm',
                'Warmth: Friendliness and approachability',
                'Confidence: Self-assurance and certainty',
                'Playfulness: Humor and lightheartedness',
                'Focus: Concentration and attentiveness',
              ],
              Colors.orange,
            ),
            const SizedBox(height: 16),
            _buildLegendSection(
              'Affinity Levels',
              [
                'Intimacy: Emotional closeness and trust',
                'Physicality: Comfort with physical connection',
              ],
              Colors.pink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendSection(String title, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: color)),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  String _formatTraitName(String name) {
    return name[0].toUpperCase() + name.substring(1);
  }

  Color _getPersonalityColor(String trait) {
    switch (trait) {
      case 'extraversion':
        return Colors.purple;
      case 'intuition':
        return Colors.deepPurple;
      case 'feeling':
        return Colors.purpleAccent;
      case 'perceiving':
        return Colors.indigo;
      default:
        return Colors.purple;
    }
  }

  Color _getMoodColor(String trait) {
    switch (trait) {
      case 'valence':
        return Colors.orange;
      case 'energy':
        return Colors.deepOrange;
      case 'warmth':
        return Colors.amber;
      case 'confidence':
        return Colors.orangeAccent;
      case 'playfulness':
        return Colors.yellow[700]!;
      case 'focus':
        return Colors.brown;
      default:
        return Colors.orange;
    }
  }

  Color _getAffinityColor(String trait) {
    switch (trait) {
      case 'intimacy':
        return Colors.pink;
      case 'physicality':
        return Colors.pinkAccent;
      default:
        return Colors.pink;
    }
  }

  String _getPersonalityLabel(String trait, int value) {
    final percent = (value / 1000 * 100).round();
    
    switch (trait) {
      case 'extraversion':
        if (percent <= 10) return 'Extremely Introverted';
        if (percent <= 20) return 'Very Introverted';
        if (percent <= 30) return 'Quite Introverted';
        if (percent <= 40) return 'Moderately Introverted';
        if (percent <= 45) return 'Slightly Introverted';
        if (percent <= 55) return 'Ambivert';
        if (percent <= 60) return 'Slightly Extraverted';
        if (percent <= 70) return 'Moderately Extraverted';
        if (percent <= 80) return 'Quite Extraverted';
        if (percent <= 90) return 'Very Extraverted';
        return 'Extremely Extraverted';
        
      case 'intuition':
        if (percent <= 10) return 'Extremely Sensing';
        if (percent <= 20) return 'Very Sensing';
        if (percent <= 30) return 'Quite Sensing';
        if (percent <= 40) return 'Moderately Sensing';
        if (percent <= 45) return 'Slightly Sensing';
        if (percent <= 55) return 'Balanced';
        if (percent <= 60) return 'Slightly Intuitive';
        if (percent <= 70) return 'Moderately Intuitive';
        if (percent <= 80) return 'Quite Intuitive';
        if (percent <= 90) return 'Very Intuitive';
        return 'Extremely Intuitive';
        
      case 'feeling':
        if (percent <= 10) return 'Extremely Thinking';
        if (percent <= 20) return 'Very Thinking';
        if (percent <= 30) return 'Quite Thinking';
        if (percent <= 40) return 'Moderately Thinking';
        if (percent <= 45) return 'Slightly Thinking';
        if (percent <= 55) return 'Balanced';
        if (percent <= 60) return 'Slightly Feeling';
        if (percent <= 70) return 'Moderately Feeling';
        if (percent <= 80) return 'Quite Feeling';
        if (percent <= 90) return 'Very Feeling';
        return 'Extremely Feeling';
        
      case 'perceiving':
        if (percent <= 10) return 'Extremely Judging';
        if (percent <= 20) return 'Very Judging';
        if (percent <= 30) return 'Quite Judging';
        if (percent <= 40) return 'Moderately Judging';
        if (percent <= 45) return 'Slightly Judging';
        if (percent <= 55) return 'Balanced';
        if (percent <= 60) return 'Slightly Perceiving';
        if (percent <= 70) return 'Moderately Perceiving';
        if (percent <= 80) return 'Quite Perceiving';
        if (percent <= 90) return 'Very Perceiving';
        return 'Extremely Perceiving';
        
      default:
        return 'Unknown';
    }
  }

  String _getMoodLabel(String trait, int value) {
    final percent = value;
    
    switch (trait) {
      case 'valence':
        if (percent <= 10) return 'Extremely Negative';
        if (percent <= 20) return 'Very Negative';
        if (percent <= 30) return 'Quite Negative';
        if (percent <= 40) return 'Somewhat Negative';
        if (percent <= 45) return 'Slightly Negative';
        if (percent <= 55) return 'Neutral';
        if (percent <= 60) return 'Slightly Positive';
        if (percent <= 70) return 'Somewhat Positive';
        if (percent <= 80) return 'Quite Positive';
        if (percent <= 90) return 'Very Positive';
        return 'Extremely Positive';
        
      case 'energy':
        if (percent <= 10) return 'Exhausted';
        if (percent <= 20) return 'Drained';
        if (percent <= 30) return 'Tired';
        if (percent <= 40) return 'Low Energy';
        if (percent <= 45) return 'Sluggish';
        if (percent <= 55) return 'Calm';
        if (percent <= 60) return 'Alert';
        if (percent <= 70) return 'Energetic';
        if (percent <= 80) return 'Very Energetic';
        if (percent <= 90) return 'Highly Energized';
        return 'Hyperactive';
        
      case 'warmth':
        if (percent <= 10) return 'Ice Cold';
        if (percent <= 20) return 'Very Cold';
        if (percent <= 30) return 'Cold';
        if (percent <= 40) return 'Cool';
        if (percent <= 45) return 'Slightly Aloof';
        if (percent <= 55) return 'Neutral';
        if (percent <= 60) return 'Slightly Warm';
        if (percent <= 70) return 'Warm';
        if (percent <= 80) return 'Very Warm';
        if (percent <= 90) return 'Radiantly Warm';
        return 'Glowing';
        
      case 'confidence':
        if (percent <= 10) return 'Terrified';
        if (percent <= 20) return 'Very Insecure';
        if (percent <= 30) return 'Insecure';
        if (percent <= 40) return 'Uncertain';
        if (percent <= 45) return 'Slightly Doubtful';
        if (percent <= 55) return 'Stable';
        if (percent <= 60) return 'Slightly Confident';
        if (percent <= 70) return 'Confident';
        if (percent <= 80) return 'Very Confident';
        if (percent <= 90) return 'Highly Confident';
        return 'Unshakeable';
        
      case 'playfulness':
        if (percent <= 10) return 'Stone Serious';
        if (percent <= 20) return 'Very Serious';
        if (percent <= 30) return 'Serious';
        if (percent <= 40) return 'Somewhat Serious';
        if (percent <= 45) return 'Slightly Reserved';
        if (percent <= 55) return 'Balanced';
        if (percent <= 60) return 'Slightly Playful';
        if (percent <= 70) return 'Playful';
        if (percent <= 80) return 'Very Playful';
        if (percent <= 90) return 'Highly Playful';
        return 'Wildly Playful';
        
      case 'focus':
        if (percent <= 10) return 'Completely Scattered';
        if (percent <= 20) return 'Very Distracted';
        if (percent <= 30) return 'Distracted';
        if (percent <= 40) return 'Somewhat Unfocused';
        if (percent <= 45) return 'Slightly Unfocused';
        if (percent <= 55) return 'Neutral';
        if (percent <= 60) return 'Attentive';
        if (percent <= 70) return 'Focused';
        if (percent <= 80) return 'Very Focused';
        if (percent <= 90) return 'Highly Focused';
        return 'Laser Focused';
        
      default:
        return 'Unknown';
    }
  }

  String _getAffinityLabel(String trait, int value) {
    final percent = value;
    
    switch (trait) {
      case 'intimacy':
        if (percent <= 10) return 'Strangers';
        if (percent <= 20) return 'Acquaintances';
        if (percent <= 30) return 'Casual Friends';
        if (percent <= 40) return 'Friends';
        if (percent <= 45) return 'Good Friends';
        if (percent <= 55) return 'Close Friends';
        if (percent <= 60) return 'Very Close';
        if (percent <= 70) return 'Intimate';
        if (percent <= 80) return 'Deeply Intimate';
        if (percent <= 90) return 'Soulmates';
        return 'One Soul';
        
      case 'physicality':
        if (percent <= 10) return 'No Touch';
        if (percent <= 20) return 'Minimal Touch';
        if (percent <= 30) return 'Occasional Touch';
        if (percent <= 40) return 'Comfortable Touch';
        if (percent <= 45) return 'Friendly Touch';
        if (percent <= 55) return 'Casual Affection';
        if (percent <= 60) return 'Affectionate';
        if (percent <= 70) return 'Very Affectionate';
        if (percent <= 80) return 'Highly Physical';
        if (percent <= 90) return 'Intensely Physical';
        return 'Completely Physical';
        
      default:
        return 'Unknown';
    }
  }
}

// Custom painter for radar chart
class RadarChartPainter extends CustomPainter {
  final Map<String, int> personality;
  final Map<String, int> mood;

  RadarChartPainter({
    required this.personality,
    required this.mood,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;

    // Draw background circles
    final bgPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(center, radius * i / 5, bgPaint);
    }

    // Draw personality traits
    if (personality.isNotEmpty) {
      _drawPolygon(
        canvas,
        center,
        radius,
        personality.values.map((v) => v / 1000).toList(),
        Colors.purple.withOpacity(0.3),
        Colors.purple,
      );
    }

    // Draw axes and labels
    final traits = personality.keys.toList();
    for (int i = 0; i < traits.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / traits.length);
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      // Draw axis line
      final linePaint = Paint()
        ..color = Colors.grey[400]!
        ..strokeWidth = 1;
      canvas.drawLine(center, end, linePaint);

      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: _formatLabel(traits[i]),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final labelOffset = Offset(
        center.dx + (radius + 20) * math.cos(angle) - textPainter.width / 2,
        center.dy + (radius + 20) * math.sin(angle) - textPainter.height / 2,
      );
      textPainter.paint(canvas, labelOffset);
    }
  }

  void _drawPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    List<double> values,
    Color fillColor,
    Color strokeColor,
  ) {
    if (values.isEmpty) return;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / values.length);
      final r = radius * values[i];
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    // Fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, strokePaint);

    // Draw points
    for (int i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / values.length);
      final r = radius * values[i];
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  String _formatLabel(String text) {
    if (text.length > 8) {
      return '${text.substring(0, 7)}...';
    }
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  bool shouldRepaint(RadarChartPainter oldDelegate) {
    return personality != oldDelegate.personality || mood != oldDelegate.mood;
  }
}
