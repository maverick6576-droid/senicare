import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senicare/core/core.dart';

class VideoCallModal extends StatefulWidget {
  final String peerName;
  final VoidCallback? onCallEnded;

  const VideoCallModal({
    super.key,
    required this.peerName,
    this.onCallEnded,
  });

  static Future<void> show(
    BuildContext context, {
    required String participantName,
    String? participantImageUrl,
    bool isCaregiver = false,
    VoidCallback? onCallEnded,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoCallModal(
          peerName: participantName,
          onCallEnded: onCallEnded,
        ),
      ),
    );
  }

  @override
  State<VideoCallModal> createState() => _VideoCallModalState();
}

class _VideoCallModalState extends State<VideoCallModal> {
  int _remainingSeconds = 15 * 60; // 15 minutes free intro call
  Timer? _timer;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() => _isConnected = true);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _endCall();
      } else if (_isConnected) {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    widget.onCallEnded?.call();
    if (mounted) Navigator.pop(context);
  }

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Stack(
          children: [
            // Main remote video view
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'S',
                        style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isConnected ? Colors.greenAccent : Colors.amberAccent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isConnected ? Icons.lock_rounded : Icons.sync_rounded,
                            color: _isConnected ? Colors.greenAccent : Colors.amberAccent,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isConnected
                                ? 'Sala privada cifrada • ${_formatTime(_remainingSeconds)} restantes'
                                : 'Conectando entrevista previa gratuita...',
                            style: TextStyle(
                              color: _isConnected ? Colors.greenAccent : Colors.amberAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_outline_rounded, color: Colors.amberAccent, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Guía para la entrevista de 15 min:',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text(
                              '• Comenta las rutinas, medicación y carácter de tu familiar.\n'
                              '• Confirma la disponibilidad de horarios y cercanía.\n'
                              '• Tu número de teléfono permanece oculto por privacidad.',
                              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Entrevista SeniCare (Gratis)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  // Self preview PIP
                  Container(
                    width: 86,
                    height: 116,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white38, width: 1.5),
                    ),
                    child: Center(
                      child: Icon(
                        _isCameraOff ? Icons.videocam_off_rounded : Icons.person_rounded,
                        color: Colors.white70,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Call Controls
            Positioned(
              bottom: 28,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isMuted ? 'Silenciado' : 'Micro',
                      active: !_isMuted,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isMuted = !_isMuted);
                      },
                    ),
                    _buildControlButton(
                      icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                      label: _isCameraOff ? 'Sin cámara' : 'Cámara',
                      active: !_isCameraOff,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isCameraOff = !_isCameraOff);
                      },
                    ),
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                      label: 'Altavoz',
                      active: _isSpeakerOn,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                      },
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: _endCall,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(height: 4),
                          const Text('Colgar', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? Colors.white.withValues(alpha: 0.12) : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : const Color(0xFF0F172A),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
