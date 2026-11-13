import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senicare/core/core.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoCallModal extends StatefulWidget {
  final String peerName;
  final String? roomId;
  final VoidCallback? onCallEnded;

  const VideoCallModal({
    super.key,
    required this.peerName,
    this.roomId,
    this.onCallEnded,
  });

  static Future<void> show(
    BuildContext context, {
    required String participantName,
    String? participantImageUrl,
    String? roomId,
    bool isCaregiver = false,
    VoidCallback? onCallEnded,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoCallModal(
          peerName: participantName,
          roomId: roomId,
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
  bool _hasLaunchedRoom = false;
  bool _isLaunching = false;
  late final String _roomUrl;

  @override
  void initState() {
    super.initState();
    final safePeer = widget.peerName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    final safeRoom = (widget.roomId != null && widget.roomId!.trim().isNotEmpty)
        ? widget.roomId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
        : 'entrevista-${safePeer.isEmpty ? "senicare" : safePeer}-${DateTime.now().millisecondsSinceEpoch % 100000}';
    _roomUrl = 'https://meet.jit.si/SeniCare-$safeRoom';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _launchSecureRoom() async {
    if (_isLaunching) return;
    HapticFeedback.mediumImpact();
    setState(() => _isLaunching = true);
    try {
      final uri = Uri.parse(_roomUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (opened) {
        setState(() => _hasLaunchedRoom = true);
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_remainingSeconds <= 0) {
            timer.cancel();
            _endCall();
          } else {
            setState(() => _remainingSeconds--);
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el navegador. Copia el enlace e ábrelo manualmente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  Future<void> _copyRoomLink() async {
    await Clipboard.setData(ClipboardData(text: _roomUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace de sala cifrada copiado. Compártelo en el chat.')),
    );
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    _timer?.cancel();
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              Row(
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
                          'Entrevista WebRTC Cifrada (Jitsi)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _endCall,
                  ),
                ],
              ),
              const Spacer(),
              CircleAvatar(
                radius: 52,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                child: Text(
                  widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'S',
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.peerName,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasLaunchedRoom
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.blueGrey.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _hasLaunchedRoom ? Colors.greenAccent : Colors.white38,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasLaunchedRoom ? Icons.videocam_rounded : Icons.lock_rounded,
                      color: _hasLaunchedRoom ? Colors.greenAccent : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasLaunchedRoom
                          ? 'Sala abierta • ${_formatTime(_remainingSeconds)} restantes'
                          : 'Sala privada lista para unirte',
                      style: TextStyle(
                        color: _hasLaunchedRoom ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Videollamada sin exponer tu teléfono:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Al pulsar "Abrir Videollamada", se abre una sala WebRTC cifrada donde ambas partes podéis veros y hablar.\n'
                      '• Copia el enlace y envíalo en el chat para que el cuidador/familia entre en la misma sala.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      _roomUrl,
                      style: const TextStyle(color: Colors.tealAccent, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isLaunching ? null : _launchSecureRoom,
                  icon: _isLaunching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.video_call_rounded),
                  label: Text(_hasLaunchedRoom ? 'Volver a abrir sala' : 'Abrir Videollamada Segura'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _copyRoomLink,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copiar enlace'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _endCall,
                      icon: const Icon(Icons.call_end_rounded, size: 18),
                      label: const Text('Cerrar sala'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
