import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/voice_training_service.dart';
import '../services/voice_activation_service.dart';
import '../widgets/animated_button.dart';

class VoiceTrainingScreen extends StatefulWidget {
  const VoiceTrainingScreen({super.key});

  @override
  State<VoiceTrainingScreen> createState() => _VoiceTrainingScreenState();
}

class _VoiceTrainingScreenState extends State<VoiceTrainingScreen> with TickerProviderStateMixin {
  final VoiceTrainingService _trainingService = VoiceTrainingService();
  final VoiceActivationService _voiceService = VoiceActivationService();
  
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;

  
  int _currentPhase = 0;
  int _currentSample = 0;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _trainingComplete = false;
  String _feedbackMessage = '';
  double _confidence = 0.0;
  
  // Enhanced training phrases organized by phase
  final List<List<String>> _trainingPhases = [
    // Phase 1: Core Wake Words
    [
      "Hey Kai",
      "Hey Kai", 
      "Kai",
      "Kai",
      "Hello Kai",
      "Hi Kai"
    ],
    
    // Phase 2: Wake Word with Commands
    [
      "Hey Kai, what time is it?",
      "Kai, tell me a joke",
      "Hey Kai, help me",
      "Kai, what's the weather?",
      "Hey Kai, good morning",
      "Kai, set a timer"
    ],
    
    // Phase 3: Natural Conversation Patterns
    [
      "Hello Kai, how are you today?",
      "Hey Kai, I have a question",
      "Kai, can you help me with something?",
      "Hey Kai, what do you think about this?",
      "Kai, I need some advice",
      "Hey Kai, tell me something interesting"
    ],
    
    // Phase 4: Background Noise Testing
    [
      "Hey Kai", // Test with intentional background sounds
      "Kai",     // Test distinguishing from similar sounds
      "Hey Kai, are you there?",
      "Kai, wake up"
    ]
  ];
  
  final List<String> _phaseNames = [
    "Wake Word Foundation",
    "Command Recognition", 
    "Conversational Patterns",
    "Noise Filtering Test"
  ];
  
  final List<String> _phaseDescriptions = [
    "Train Kai to recognize your basic wake words",
    "Learn how you naturally start conversations",
    "Understand your speaking patterns and style", 
    "Test recognition with background noise"
  ];
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadExistingProfile();
  }
  
  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    

  }
  
  void _loadExistingProfile() async {
    final profile = await _trainingService.getCurrentProfile();
    if (profile != null) {
      setState(() {
        _trainingComplete = true;
        _confidence = profile['confidence'] ?? 0.0;
      });
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }
  
  void _startRecording() async {
    if (_isRecording || _isProcessing) return;
    
    setState(() {
      _isRecording = true;
      _feedbackMessage = 'Listening...';
    });
    
    _pulseController.repeat(reverse: true);
    HapticFeedback.lightImpact();
    
    // Record for 3 seconds
    await Future.delayed(const Duration(milliseconds: 500));
    final audioPath = await _voiceService.startRecording();
    
    if (audioPath != null) {
      await Future.delayed(const Duration(seconds: 3));
      final finalPath = await _voiceService.stopRecording();
      
      if (finalPath != null) {
        await _processRecording(finalPath);
      }
    }
    
    _pulseController.stop();
    setState(() {
      _isRecording = false;
    });
  }
  
  Future<void> _processRecording(String audioPath) async {
    setState(() {
      _isProcessing = true;
      _feedbackMessage = 'Analyzing your voice...';
    });
    
    try {
      // Get transcription
      final transcription = await _voiceService.transcribeAudio(audioPath);
      final expectedPhrase = _trainingPhases[_currentPhase][_currentSample];
      
      // Calculate similarity
      final similarity = _calculateSimilarity(transcription.toLowerCase(), expectedPhrase.toLowerCase());
      
      if (similarity > 0.7) {
        // Good match - add to training data
        await _trainingService.addVoiceSample(
          audioPath,
          transcription,
          _currentPhase,
          similarity,
        );
        
        setState(() {
          _feedbackMessage = 'Great! Voice sample recorded successfully.';
          _currentSample++;
        });
        
        HapticFeedback.selectionClick();
        await _progressController.forward();
        
        // Check if phase complete
        if (_currentSample >= _getSamplesForPhase(_currentPhase)) {
          await _completePhase();
        }
        
      } else {
        setState(() {
          _feedbackMessage = 'Please try again. Say: "$expectedPhrase"';
        });
        HapticFeedback.heavyImpact();
      }
      
    } catch (e) {
      setState(() {
        _feedbackMessage = 'Error processing voice. Please try again.';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
      
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _feedbackMessage = '';
        });
      }
    }
  }
  
  int _getSamplesForPhase(int phase) {
    if (phase >= 0 && phase < _trainingPhases.length) {
      return _trainingPhases[phase].length;
    }
    return 2; // Fallback
  }
  
  Future<void> _completePhase() async {
    if (_currentPhase < 3) {
      setState(() {
        _currentPhase++;
        _currentSample = 0;
        _feedbackMessage = 'Phase ${_currentPhase + 1} complete! Moving to ${_phaseNames[_currentPhase]}';
      });
      
      await Future.delayed(const Duration(seconds: 2));
      
      if (_currentPhase == 2) {
        // Analysis phase
        await _analyzeVoicePattern();
      }
      
    } else {
      // Training complete
      await _completeTraining();
    }
    
    _progressController.reset();
  }
  
  Future<void> _analyzeVoicePattern() async {
    setState(() {
      _isProcessing = true;
      _feedbackMessage = 'Analyzing your unique voice pattern...';
    });
    
    // Simulate analysis process
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _confidence = i / 100.0;
        });
      }
    }
    
    await _trainingService.buildVoiceProfile();
    
    setState(() {
      _isProcessing = false;
      _feedbackMessage = 'Voice pattern analysis complete!';
      _currentSample++; // Move to next phase
    });
    
    await Future.delayed(const Duration(seconds: 2));
    await _completePhase();
  }
  
  Future<void> _completeTraining() async {
    final profile = await _trainingService.finalizeTraining();
    
    setState(() {
      _trainingComplete = true;
      _confidence = profile['confidence'] ?? 0.85;
      _feedbackMessage = 'Voice training complete! Kai now recognizes your voice.';
    });
    
    HapticFeedback.heavyImpact();
    
    // Auto-dismiss after celebration
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
  
  double _calculateSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    
    // Simple similarity calculation
    final words1 = text1.split(' ');
    final words2 = text2.split(' ');
    
    int matches = 0;
    for (String word in words1) {
      if (words2.contains(word)) {
        matches++;
      }
    }
    
    return matches / words1.length.clamp(1, double.infinity);
  }
  
  void _resetTraining() async {
    await _trainingService.clearProfile();
    setState(() {
      _currentPhase = 0;
      _currentSample = 0;
      _trainingComplete = false;
      _confidence = 0.0;
      _feedbackMessage = '';
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFD4AF37)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Voice Training',
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _trainingComplete ? _buildCompletedUI() : _buildTrainingUI(),
        ),
      ),
    );
  }
  
  Widget _buildTrainingUI() {
    final progress = (_currentPhase * _getSamplesForPhase(_currentPhase) + _currentSample) / 
                   _getTotalSamples();
    
    return Column(
      children: [
        // Progress indicator
        _buildProgressIndicator(progress),
        
        const SizedBox(height: 40),
        
        // Current phase info
        _buildPhaseInfo(),
        
        const SizedBox(height: 60),
        
        // Recording interface
        _buildRecordingInterface(),
        
        const Spacer(),
        
        // Instructions and feedback
        _buildInstructions(),
        
        const SizedBox(height: 40),
      ],
    );
  }
  
  Widget _buildCompletedUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Success icon
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Color(0xFFD4AF37).withOpacity(0.3),
                Color(0xFFD4AF37).withOpacity(0.1),
              ],
            ),
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: Color(0xFFD4AF37),
          ),
        ),
        
        const SizedBox(height: 40),
        
        const Text(
          'Training Complete!',
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 20),
        
        Text(
          'Voice Recognition Confidence: ${(_confidence * 100).toInt()}%',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
          ),
        ),
        
        const SizedBox(height: 40),
        
        // Confidence bar
        _buildConfidenceBar(),
        
        const SizedBox(height: 60),
        
        // Action buttons
        Row(
          children: [
            Expanded(
              child: AnimatedButton(
                onPressed: _resetTraining,
                child: const Text(
                  'Retrain Voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: AnimatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                backgroundColor: const Color(0xFFD4AF37),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildProgressIndicator(double progress) {
    return Column(
      children: [
        // Overall progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Training Progress',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Phase indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            Color color;
            if (index < _currentPhase) {
              color = Colors.green; // Completed
            } else if (index == _currentPhase) {
              color = const Color(0xFFD4AF37); // Current
            } else {
              color = Colors.grey; // Not started
            }
            
            return Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        
        const SizedBox(height: 4),
        
        // Phase labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            return SizedBox(
              width: 60,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: index <= _currentPhase ? Colors.white70 : Colors.grey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }),
        ),
        
        const SizedBox(height: 12),
        
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPhaseInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(0xFFD4AF37).withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            _phaseNames[_currentPhase],
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            _phaseDescriptions[_currentPhase],
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'Sample ${_currentSample + 1} of ${_getSamplesForPhase(_currentPhase)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordingInterface() {
    return Column(
      children: [
        // Microphone button
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isRecording ? _pulseAnimation.value : 1.0,
              child: GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isRecording
                          ? [
                              const Color(0xFFFF6B6B),
                              const Color(0xFFFF4757),
                            ]
                          : [
                              const Color(0xFFD4AF37),
                              const Color(0xFFFFD700),
                            ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : Color(0xFFD4AF37))
                            .withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 24),
        
        // Recording status
        if (_isRecording)
          const Text(
            'Recording...',
            style: TextStyle(
              color: Color(0xFFFF6B6B),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        
        if (_isProcessing)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Color(0xFFD4AF37),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Processing...',
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 16,
                ),
              ),
            ],
          ),
      ],
    );
  }
  
  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _currentPhase == 3 ? Colors.orange.withOpacity(0.5) : 
                 Color(0xFFD4AF37).withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          // Phase-specific instructions
          if (_currentPhase == 3) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Text(
                    '⚠️ Background Noise Test',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'For this phase, try speaking with some background noise (TV, music, etc.) to test noise filtering.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          if (_currentSample < _trainingPhases[_currentPhase].length)
            Text(
              'Say: "${_trainingPhases[_currentPhase][_currentSample]}"',
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          
          if (_feedbackMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _feedbackMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          const SizedBox(height: 16),
          
          const Text(
            'Speak clearly and naturally. The system will learn your unique voice patterns.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildConfidenceBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Voice Recognition Accuracy',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        
        const SizedBox(height: 12),
        
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(6),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _confidence,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _confidence > 0.8
                      ? [const Color(0xFF4CAF50), const Color(0xFF8BC34A)]
                      : _confidence > 0.6
                          ? [const Color(0xFFFF9800), const Color(0xFFFFC107)]
                          : [const Color(0xFFFF5722), const Color(0xFFFF7043)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  int _getTotalSamples() {
    return _getSamplesForPhase(0) + _getSamplesForPhase(1) + 
           _getSamplesForPhase(2) + _getSamplesForPhase(3);
  }
}