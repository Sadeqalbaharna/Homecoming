import 'package:flutter/material.dart';
import '../screens/voice_training_screen.dart';
import '../services/voice/voice_training_service.dart';
import '../widgets/animated_button.dart';

class VoiceSetupDialog extends StatefulWidget {
  final bool isFirstSetup;
  
  const VoiceSetupDialog({
    super.key,
    this.isFirstSetup = false,
  });

  @override
  State<VoiceSetupDialog> createState() => _VoiceSetupDialogState();
}

class _VoiceSetupDialogState extends State<VoiceSetupDialog> {
  final VoiceTrainingService _trainingService = VoiceTrainingService();
  Map<String, dynamic>? _currentProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  void _loadCurrentProfile() async {
    await _trainingService.initialize();
    final profile = await _trainingService.getCurrentProfile();
    setState(() {
      _currentProfile = profile;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: const Color(0xFFD4AF37).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFD4AF37).withOpacity(0.3),
                        const Color(0xFFD4AF37).withOpacity(0.1),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.record_voice_over,
                    color: Color(0xFFD4AF37),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isFirstSetup ? 'Welcome to Kai' : 'Voice Recognition',
                        style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Personalize your voice interaction',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFD4AF37),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: _buildContent(),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_currentProfile != null) {
      return _buildExistingProfileUI();
    } else {
      return _buildSetupUI();
    }
  }

  Widget _buildSetupUI() {
    return Column(
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFD4AF37).withOpacity(0.3),
                const Color(0xFFD4AF37).withOpacity(0.1),
              ],
            ),
          ),
          child: const Icon(
            Icons.mic,
            size: 40,
            color: Color(0xFFD4AF37),
          ),
        ),
        
        const SizedBox(height: 24),
        
        const Text(
          'Train Kai to Recognize Your Voice',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 16),
        
        const Text(
          'Kai will learn your unique voice patterns to better distinguish your commands from background noise and other voices.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 32),
        
        // Benefits list
        _buildBenefitsList(),
        
        const SizedBox(height: 32),
        
        // Action buttons
        Row(
          children: [
            if (!widget.isFirstSetup)
              Expanded(
                child: AnimatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  backgroundColor: Colors.grey[800],
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            
            if (!widget.isFirstSetup) const SizedBox(width: 16),
            
            Expanded(
              child: AnimatedButton(
                onPressed: _startTraining,
                backgroundColor: const Color(0xFFD4AF37),
                child: const Text(
                  'Start Training',
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

  Widget _buildExistingProfileUI() {
    final confidence = (_currentProfile!['confidence'] ?? 0.0) * 100;
    final sampleCount = _currentProfile!['sampleCount'] ?? 0;
    
    return Column(
      children: [
        // Success icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFD4AF37).withOpacity(0.2),
                const Color(0xFFD4AF37).withOpacity(0.05),
              ],
            ),
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 40,
            color: Color(0xFF4CAF50),
          ),
        ),
        
        const SizedBox(height: 24),
        
        const Text(
          'Voice Training Complete',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          'Recognition Accuracy: ${confidence.toInt()}%',
          style: const TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        Text(
          'Trained with $sampleCount voice samples',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Profile stats
        _buildProfileStats(),
        
        const SizedBox(height: 32),
        
        // Action buttons
        Row(
          children: [
            Expanded(
              child: AnimatedButton(
                onPressed: _retrainVoice,
                backgroundColor: Colors.grey[800],
                child: const Text(
                  'Retrain',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            Expanded(
              child: AnimatedButton(
                onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildBenefitsList() {
    final benefits = [
      'Better wake word detection',
      'Reduced false activations',
      'Improved accuracy in noisy environments',
      'Personalized voice recognition',
    ];

    return Column(
      children: benefits.map((benefit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Color(0xFFD4AF37),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                benefit,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildProfileStats() {
    final stats = _trainingService.getTrainingStats();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD4AF37).withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          _buildStatRow('Voice Samples', '${stats['confidence_samples']}'),
          const SizedBox(height: 8),
          _buildStatRow('Custom Wake Words', '${stats['custom_wake_words']}'),
          const SizedBox(height: 8),
          _buildStatRow('Learned Corrections', '${stats['corrections_learned']}'),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _startTraining() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const VoiceTrainingScreen(),
      ),
    );

    if (result == true) {
      // Training completed successfully
      _loadCurrentProfile(); // Refresh the profile
    }
  }

  void _retrainVoice() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Retrain Voice',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will clear your current voice profile and start fresh. Are you sure?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Retrain',
              style: TextStyle(color: Color(0xFFD4AF37)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _trainingService.clearProfile();
      _startTraining();
    }
  }
}