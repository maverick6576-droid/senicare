import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/firebase/firestore_chat_repository.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends StatefulWidget {
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  final String? caregiverImageUrl;
  final String? clientName;

  const ChatScreen({
    super.key,
    required this.clientId,
    required this.caregiverId,
    required this.caregiverName,
    this.caregiverImageUrl,
    this.clientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  late Future<ClientProfile?> _peerClientFuture;
  late Future<CaregiverProfile?> _peerCaregiverFuture;
  late Stream<ChatConversation?> _conversationStream;
  Stream<List<ChatMessage>>? _messagesStream;
  Stream<List<Booking>>? _bookingsStream;
  String? _bookingsStreamKey;

  int _limit = 30;
  bool _hasComposerText = false;
  bool _isUploadingMedia = false;
  bool _isSearching = false;
  String _searchQuery = '';
  bool _showScrollToBottom = false;
  int _unreadWhileScrolled = 0;
  String? _lastSeenTopMessageId;
  String _cachedRole = 'client';
  String? _resolvedClientName;
  String? _resolvedCaregiverImage;

  // Reply state
  ChatMessage? _replyingTo;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  // Read-receipt tracking
  final Set<String> _markingReadIds = {};
  bool _initialUnreadResetDone = false;

  // Typing status
  DateTime? _lastTypingSentAt;
  Timer? _typingStopTimer;
  Timer? _peerTypingExpiryTimer;

  // Voice recording
  AudioRecorder? _audioRecorder;
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  Timer? _recordTimer;

  // Voice playback
  AudioPlayer? _audioPlayer;
  String? _playingMessageId;
  PlayerState _playerState = PlayerState.stopped;
  Duration _playPosition = Duration.zero;
  Duration _playDuration = Duration.zero;
  double _playbackRate = 1.0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onComposerChanged);

    _resolvedClientName = widget.clientName;
    _resolvedCaregiverImage = widget.caregiverImageUrl;

    _peerClientFuture =
        DependencyInjection.clients.getClient(widget.clientId).then((profile) {
      if (mounted && profile != null && profile.name.isNotEmpty) {
        _resolvedClientName = profile.name;
      }
      return profile;
    });
    _peerCaregiverFuture = DependencyInjection.caregivers
        .getCaregiver(widget.caregiverId)
        .then((profile) {
      if (mounted && profile != null && profile.imageUrl.isNotEmpty) {
        _resolvedCaregiverImage = profile.imageUrl;
      }
      return profile;
    });

    _conversationStream = DependencyInjection.chats
        .streamConversation(widget.clientId, widget.caregiverId);
    _ensureMessagesStream();
  }

  @override
  void dispose() {
    if (_lastTypingSentAt != null) {
      DependencyInjection.chats.setTypingStatus(
        widget.clientId,
        widget.caregiverId,
        _cachedRole,
        false,
      );
    }
    _recordTimer?.cancel();
    _typingStopTimer?.cancel();
    _peerTypingExpiryTimer?.cancel();
    _highlightTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer?.dispose();
    _audioRecorder?.dispose();
    _scrollController.dispose();
    _controller.dispose();
    _searchController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _ensureMessagesStream() {
    _messagesStream = DependencyInjection.chats.streamMessages(
      widget.clientId,
      widget.caregiverId,
      limit: _limit,
    );
  }

  Stream<List<Booking>> _ensureBookingsStream(String userId, String role) {
    final key = '${userId}_$role';
    if (_bookingsStream == null || _bookingsStreamKey != key) {
      _bookingsStreamKey = key;
      if (userId.isEmpty) {
        _bookingsStream = Stream.value(const []);
      } else {
        _bookingsStream = DependencyInjection.bookings.streamBookings(
          userId,
          role,
        );
      }
    }
    return _bookingsStream!;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollController.position.pixels;
    final shouldShow = pixels > 240;
    if (shouldShow != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = shouldShow;
        if (!shouldShow) _unreadWhileScrolled = 0;
      });
    }
    if (pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _limit += 25;
        _ensureMessagesStream();
      });
    }
  }

  void _onComposerChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasComposerText) {
      setState(() => _hasComposerText = hasText);
    }

    if (hasText) {
      final now = DateTime.now();
      if (_lastTypingSentAt == null ||
          now.difference(_lastTypingSentAt!).inSeconds >= 3) {
        _lastTypingSentAt = now;
        DependencyInjection.chats.setTypingStatus(
          widget.clientId,
          widget.caregiverId,
          _cachedRole,
          true,
        );
      }
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(seconds: 4), () {
        _lastTypingSentAt = null;
        DependencyInjection.chats.setTypingStatus(
          widget.clientId,
          widget.caregiverId,
          _cachedRole,
          false,
        );
      });
    } else if (_lastTypingSentAt != null) {
      _typingStopTimer?.cancel();
      _lastTypingSentAt = null;
      DependencyInjection.chats.setTypingStatus(
        widget.clientId,
        widget.caregiverId,
        _cachedRole,
        false,
      );
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (_unreadWhileScrolled > 0) {
      setState(() => _unreadWhileScrolled = 0);
    }
  }

  void _markVisibleMessagesAsRead(
    List<ChatMessage> messages,
    bool isClient,
  ) {
    final viewerRole = isClient ? 'client' : 'caregiver';
    final expectedIncomingSender =
        isClient ? ChatSender.Caregiver : ChatSender.Client;

    final unreadIds = <String>[];
    for (final m in messages) {
      if (m.sender == expectedIncomingSender &&
          !m.isRead &&
          m.id.isNotEmpty &&
          !_markingReadIds.contains(m.id)) {
        unreadIds.add(m.id);
      }
    }

    if (unreadIds.isEmpty && _initialUnreadResetDone) return;
    _initialUnreadResetDone = true;
    _markingReadIds.addAll(unreadIds);

    Future.microtask(() async {
      await DependencyInjection.chats.markMessagesAsRead(
        widget.clientId,
        widget.caregiverId,
        viewerRole,
        unreadIds,
      );
    });
  }

  Future<void> _sendMessageObject(
    ChatMessage message, {
    required bool allowContactSharing,
  }) async {
    try {
      await DependencyInjection.chats.sendMessage(
        widget.clientId,
        widget.caregiverId,
        widget.caregiverName,
        message,
        clientName: _resolvedClientName,
        caregiverImageUrl: _resolvedCaregiverImage,
        allowContactSharing: allowContactSharing,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al enviar el mensaje: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _sendTextMessage({
    required bool isClient,
    required bool allowContactSharing,
  }) async {
    final rawText = _controller.text.trim();
    if (rawText.isEmpty) return;

    final sender = isClient ? ChatSender.Client : ChatSender.Caregiver;
    final senderId = context.read<AuthNotifier>().currentUserId ??
        (isClient ? widget.clientId : widget.caregiverId);
    final receiverId = isClient ? widget.caregiverId : widget.clientId;
    final reply = _replyingTo;

    _controller.clear();
    _typingStopTimer?.cancel();
    _lastTypingSentAt = null;
    if (reply != null) {
      setState(() => _replyingTo = null);
    }

    final cleanPreview = FirestoreChatRepository.sanitizeMessageText(
      rawText,
      allowContactSharing: allowContactSharing,
    );
    if (!allowContactSharing && cleanPreview != rawText && mounted) {
      CustomSnackBar.show(
        context,
        message:
            'Teléfonos y emails se ocultan automáticamente hasta confirmar la reserva.',
        type: SnackBarType.warning,
      );
    }

    await _sendMessageObject(
      ChatMessage(
        sender: sender,
        text: rawText,
        timestamp: DateTime.now(),
        senderId: senderId,
        receiverId: receiverId,
        type: ChatMessageType.text,
        replyToMessageId: reply?.id,
        replyToText: reply?.previewSummary,
        replyToSender: reply?.sender,
      ),
      allowContactSharing: allowContactSharing,
    );
  }

  Future<void> _startVoiceRecording() async {
    try {
      _audioRecorder ??= AudioRecorder();
      final hasPerm = await _audioRecorder!.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          CustomSnackBar.show(
            context,
            message: 'Activa el permiso del micrófono para enviar notas de voz.',
            type: SnackBarType.warning,
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final filePath = p.join(
        dir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await _audioRecorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: filePath,
      );

      HapticFeedback.mediumImpact();
      setState(() {
        _isRecordingVoice = true;
        _recordingSeconds = 0;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo iniciar la grabación de voz: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder?.cancel();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
      });
    }
  }

  Future<void> _finishAndSendVoiceRecording({
    required bool isClient,
    required bool allowContactSharing,
  }) async {
    final currentAuthUid = context.read<AuthNotifier>().currentUserId;
    _recordTimer?.cancel();
    final duration = max(1, _recordingSeconds);
    String? path;
    try {
      path = await _audioRecorder?.stop();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
      });
    }

    if (path == null || path.isEmpty) return;

    setState(() => _isUploadingMedia = true);
    try {
      final bytes = await XFile(path).readAsBytes();
      final roomId = FirestoreChatRepository.roomIdFor(
        widget.clientId,
        widget.caregiverId,
      );
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_media/$roomId/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await ref.putData(bytes, SettableMetadata(contentType: 'audio/mp4'));
      final url = await ref.getDownloadURL();

      final sender = isClient ? ChatSender.Client : ChatSender.Caregiver;
      final mins = duration ~/ 60;
      final secs = (duration % 60).toString().padLeft(2, '0');
      final reply = _replyingTo;
      if (reply != null && mounted) {
        setState(() => _replyingTo = null);
      }

      await _sendMessageObject(
        ChatMessage(
          sender: sender,
          text: '🎤 Nota de voz ($mins:$secs)',
          timestamp: DateTime.now(),
          senderId: currentAuthUid ??
              (isClient ? widget.clientId : widget.caregiverId),
          receiverId: isClient ? widget.caregiverId : widget.clientId,
          type: ChatMessageType.audio,
          mediaUrl: url,
          audioDurationSeconds: duration,
          replyToMessageId: reply?.id,
          replyToText: reply?.previewSummary,
          replyToSender: reply?.sender,
        ),
        allowContactSharing: allowContactSharing,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo enviar la nota de voz: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _toggleAudioPlayback(ChatMessage m, String msgKey) async {
    final url = m.mediaUrl;
    if (url == null || url.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Esta nota de voz no tiene archivo de audio reproducible.',
        type: SnackBarType.info,
      );
      return;
    }

    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayer();
      _posSub = _audioPlayer!.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _playPosition = pos);
      });
      _durSub = _audioPlayer!.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _playDuration = dur);
      });
      _stateSub = _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() {
          _playerState = state;
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            _playingMessageId = null;
            _playPosition = Duration.zero;
          }
        });
      });
    }

    try {
      HapticFeedback.selectionClick();
      if (_playingMessageId == msgKey && _playerState == PlayerState.playing) {
        await _audioPlayer!.pause();
        return;
      }
      if (_playingMessageId == msgKey && _playerState == PlayerState.paused) {
        await _audioPlayer!.resume();
        return;
      }

      await _audioPlayer!.stop();
      setState(() {
        _playingMessageId = msgKey;
        _playPosition = Duration.zero;
        _playDuration = Duration(seconds: m.audioDurationSeconds ?? 0);
      });
      await _audioPlayer!.setPlaybackRate(_playbackRate);
      await _audioPlayer!.play(UrlSource(url));
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al reproducir audio: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    final next = _playbackRate == 1.0 ? 1.5 : 1.0;
    setState(() => _playbackRate = next);
    await _audioPlayer?.setPlaybackRate(next);
  }

  void _showAttachmentSheet({
    required bool isClient,
    required bool hasConfirmedBooking,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachmentOption(
                      icon: Icons.camera_alt_rounded,
                      color: const Color(0xFFEC4899),
                      label: 'Cámara',
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _pickAndSendImage(
                          ImageSource.camera,
                          isClient: isClient,
                          allowContactSharing: hasConfirmedBooking,
                        );
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF8B5CF6),
                      label: 'Galería',
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _pickAndSendImage(
                          ImageSource.gallery,
                          isClient: isClient,
                          allowContactSharing: hasConfirmedBooking,
                        );
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.location_on_rounded,
                      color: const Color(0xFF10B981),
                      label: 'Ubicación',
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _sendCurrentLocation(
                          isClient: isClient,
                          hasConfirmedBooking: hasConfirmedBooking,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendImage(
    ImageSource source, {
    required bool isClient,
    required bool allowContactSharing,
  }) async {
    final currentAuthUid = context.read<AuthNotifier>().currentUserId;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      final captionController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Enviar fotografía'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    bytes,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionController,
                  decoration: const InputDecoration(
                    hintText: 'Añade un comentario (opcional)...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogCtx, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
            ),
          ],
        ),
      );

      final caption = captionController.text.trim();
      captionController.dispose();
      if (confirmed != true || !mounted) return;

      setState(() => _isUploadingMedia = true);
      final roomId = FirestoreChatRepository.roomIdFor(
        widget.clientId,
        widget.caregiverId,
      );
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_media/$roomId/img_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      final sender = isClient ? ChatSender.Client : ChatSender.Caregiver;
      final reply = _replyingTo;
      if (reply != null && mounted) setState(() => _replyingTo = null);

      await _sendMessageObject(
        ChatMessage(
          sender: sender,
          text: caption.isNotEmpty ? caption : '📷 Foto',
          timestamp: DateTime.now(),
          senderId: currentAuthUid ??
              (isClient ? widget.clientId : widget.caregiverId),
          receiverId: isClient ? widget.caregiverId : widget.clientId,
          type: ChatMessageType.image,
          mediaUrl: url,
          replyToMessageId: reply?.id,
          replyToText: reply?.previewSummary,
          replyToSender: reply?.sender,
        ),
        allowContactSharing: allowContactSharing,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo enviar la imagen: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _sendCurrentLocation({
    required bool isClient,
    required bool hasConfirmedBooking,
  }) async {
    final currentAuthUid = context.read<AuthNotifier>().currentUserId;
    if (!hasConfirmedBooking) {
      CustomSnackBar.show(
        context,
        message:
            'Por seguridad, compartir ubicación exacta se desbloquea cuando confirmas la reserva.',
        type: SnackBarType.warning,
      );
      return;
    }

    setState(() => _isUploadingMedia = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Activa el GPS del dispositivo.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado.');
      }

      final pos = await Geolocator.getCurrentPosition();
      final sender = isClient ? ChatSender.Client : ChatSender.Caregiver;
      await _sendMessageObject(
        ChatMessage(
          sender: sender,
          text: '📍 Ubicación compartida',
          timestamp: DateTime.now(),
          senderId: currentAuthUid ??
              (isClient ? widget.clientId : widget.caregiverId),
          receiverId: isClient ? widget.caregiverId : widget.clientId,
          type: ChatMessageType.location,
          latitude: pos.latitude,
          longitude: pos.longitude,
        ),
        allowContactSharing: true,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo compartir la ubicación: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  void _setReplyTo(ChatMessage message) {
    if (message.isDeleted) return;
    HapticFeedback.lightImpact();
    setState(() => _replyingTo = message);
    _inputFocusNode.requestFocus();
  }

  void _showMessageActions(
    ChatMessage message, {
    required bool isMe,
    required String viewerUserId,
  }) {
    if (message.isDeleted) return;
    HapticFeedback.mediumImpact();
    const emojis = ['❤️', '👍', '😂', '😮', '🙏'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.id.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: emojis.map((emoji) {
                        final isSelected =
                            message.reactions[viewerUserId] == emoji;
                        return InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            DependencyInjection.chats.toggleReaction(
                              widget.clientId,
                              widget.caregiverId,
                              message.id,
                              viewerUserId,
                              emoji,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primarySurface
                                  : Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Responder'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _setReplyTo(message);
                  },
                ),
                if (message.type == ChatMessageType.text ||
                    message.type == ChatMessageType.image)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copiar texto'),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Clipboard.setData(ClipboardData(text: message.text));
                      CustomSnackBar.show(
                        context,
                        message: 'Mensaje copiado al portapapeles.',
                        type: SnackBarType.info,
                      );
                    },
                  ),
                if (isMe && message.id.isNotEmpty)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    title: const Text(
                      'Eliminar para todos',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      DependencyInjection.chats.deleteMessageForEveryone(
                        widget.clientId,
                        widget.caregiverId,
                        message.id,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _jumpToQuotedMessage(
    String? replyId,
    List<ChatMessage> loadedMessages,
  ) {
    if (replyId == null || replyId.isEmpty) return;
    final idx = loadedMessages.indexWhere((m) => m.id == replyId);
    if (idx == -1) {
      CustomSnackBar.show(
        context,
        message: 'Desliza hacia arriba para ver mensajes más antiguos.',
        type: SnackBarType.info,
      );
      return;
    }
    if (_scrollController.hasClients) {
      final approxOffset = (idx * 72.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        approxOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = replyId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  void _openFullImageViewer(String url, String caption) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              caption == '📷 Foto' ? 'Fotografía' : caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => const CircularProgressIndicator(
                  color: Colors.white,
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) return 'HOY';
    if (msgDay == yesterday) return 'AYER';
    return DateFormat('d MMM y').format(date).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    _cachedRole = auth.currentRole;
    final isClient = auth.currentRole == 'client';
    final viewerUserId =
        auth.currentUserId ?? (isClient ? widget.clientId : widget.caregiverId);

    return StreamBuilder<ChatConversation?>(
      stream: _conversationStream,
      builder: (context, convSnap) {
        final conv = convSnap.data;
        final isPeerTyping = conv?.isPeerTyping(isClient) ?? false;

        if (isPeerTyping) {
          _peerTypingExpiryTimer?.cancel();
          _peerTypingExpiryTimer = Timer(const Duration(seconds: 7), () {
            if (mounted) setState(() {});
          });
        }

        return StreamBuilder<List<Booking>>(
          stream: _ensureBookingsStream(
            isClient ? widget.clientId : viewerUserId,
            auth.currentRole,
          ),
          builder: (context, bookingSnap) {
            final bookings = bookingSnap.data ?? const [];
            final hasConfirmedBooking = bookings.any(
              (b) =>
                  b.clientId == widget.clientId &&
                  b.caregiverId == widget.caregiverId &&
                  (b.status == BookingStatus.confirmed ||
                      b.status == BookingStatus.completed),
            );

            return Scaffold(
              backgroundColor: const Color(0xFFEFEAE2),
              appBar: _buildAppBar(
                isClient: isClient,
                conv: conv,
                isPeerTyping: isPeerTyping,
                hasConfirmedBooking: hasConfirmedBooking,
              ),
              body: Column(
                children: [
                  if (_isSearching) _buildSearchBar(),
                  if (!hasConfirmedBooking) _buildSecurityBanner(),
                  Expanded(
                    child: Stack(
                      children: [
                        StreamBuilder<List<ChatMessage>>(
                          stream: _messagesStream,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'No se pudieron cargar los mensajes',
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        setState(() => _ensureMessagesStream());
                                      },
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final allMessages = snapshot.data ?? const [];
                            if (allMessages.isNotEmpty) {
                              final topId = allMessages.first.id.isNotEmpty
                                  ? allMessages.first.id
                                  : allMessages.first.timestamp.toString();
                              if (_lastSeenTopMessageId != null &&
                                  topId != _lastSeenTopMessageId &&
                                  _showScrollToBottom) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() => _unreadWhileScrolled++);
                                  }
                                });
                              }
                              _lastSeenTopMessageId = topId;
                              _markVisibleMessagesAsRead(allMessages, isClient);
                            }

                            final query = _searchQuery.trim().toLowerCase();
                            final messages = query.isEmpty
                                ? allMessages
                                : allMessages
                                    .where((m) =>
                                        m.text.toLowerCase().contains(query))
                                    .toList();

                            if (messages.isEmpty) {
                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.all(24),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    query.isNotEmpty
                                        ? 'No se encontraron mensajes con "$query".'
                                        : 'Inicia la conversación con un saludo.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppTheme.slateMuted,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                16,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final m = messages[index];
                                final older = index + 1 < messages.length
                                    ? messages[index + 1]
                                    : null;
                                final newer =
                                    index - 1 >= 0 ? messages[index - 1] : null;

                                final showDateHeader = older == null ||
                                    !_isSameDay(older.timestamp, m.timestamp);
                                final isFirstInGroup = older == null ||
                                    older.sender != m.sender ||
                                    !_isSameDay(older.timestamp, m.timestamp);
                                final isLastInGroup = newer == null ||
                                    newer.sender != m.sender ||
                                    !_isSameDay(newer.timestamp, m.timestamp);

                                final isMe = isClient
                                    ? m.sender == ChatSender.Client
                                    : m.sender == ChatSender.Caregiver;

                                return Column(
                                  children: [
                                    if (showDateHeader)
                                      _buildDateHeader(m.timestamp),
                                    _buildMessageRow(
                                      m,
                                      isMe: isMe,
                                      isFirstInGroup: isFirstInGroup,
                                      isLastInGroup: isLastInGroup,
                                      viewerUserId: viewerUserId,
                                      loadedMessages: allMessages,
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        if (_showScrollToBottom)
                          Positioned(
                            right: 16,
                            bottom: 14,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'chat_scroll_bottom',
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppTheme.darkSlate,
                                  onPressed: _scrollToBottom,
                                  child: const Icon(
                                    Icons.keyboard_double_arrow_down_rounded,
                                  ),
                                ),
                                if (_unreadWhileScrolled > 0)
                                  Positioned(
                                    top: -6,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _unreadWhileScrolled.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_isUploadingMedia)
                    const LinearProgressIndicator(
                      minHeight: 3,
                      color: AppTheme.primary,
                    ),
                  if (_replyingTo != null) _buildReplyComposerPreview(),
                  _buildComposer(
                    isClient: isClient,
                    hasConfirmedBooking: hasConfirmedBooking,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar({
    required bool isClient,
    required ChatConversation? conv,
    required bool isPeerTyping,
    required bool hasConfirmedBooking,
  }) {
    final statusLabel = isPeerTyping
        ? 'escribiendo...'
        : (hasConfirmedBooking
            ? 'Reserva confirmada'
            : 'Entrevista previa segura');
    final statusColor = isPeerTyping
        ? const Color(0xFF16A34A)
        : (hasConfirmedBooking ? AppTheme.primary : AppTheme.slateMuted);

    return AppBar(
      titleSpacing: 0,
      backgroundColor: Colors.white,
      foregroundColor: AppTheme.darkSlate,
      elevation: 0.5,
      title: Row(
        children: [
          _buildHeaderAvatar(isClient, conv),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isClient)
                  Text(
                    widget.caregiverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  FutureBuilder<ClientProfile?>(
                    future: _peerClientFuture,
                    builder: (context, snap) {
                      final name = conv != null
                          ? conv.familyDisplayName(snap.data?.name)
                          : (snap.data?.name.isNotEmpty == true
                              ? 'Familia ${snap.data!.name}'
                              : 'Familia');
                      return Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle:
                        isPeerTyping ? FontStyle.italic : FontStyle.normal,
                    fontWeight:
                        isPeerTyping ? FontWeight.w600 : FontWeight.normal,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Buscar mensajes',
          icon: Icon(
            _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
          ),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
              }
            });
          },
        ),
        IconButton(
          tooltip: 'Videollamada 15 min',
          icon: const Icon(Icons.videocam_rounded, color: AppTheme.primary),
          onPressed: () {
            HapticFeedback.lightImpact();
            final senderId = context.read<AuthNotifier>().currentUserId ??
                (isClient ? widget.clientId : widget.caregiverId);
            final receiverId = isClient ? widget.caregiverId : widget.clientId;
            _sendMessageObject(
              ChatMessage(
                sender: isClient ? ChatSender.Client : ChatSender.Caregiver,
                text:
                    '📹 Ha iniciado una sala de entrevista por videollamada (15 min gratis)',
                timestamp: DateTime.now(),
                senderId: senderId,
                receiverId: receiverId,
                type: ChatMessageType.call,
              ),
              allowContactSharing: hasConfirmedBooking,
            );
            VideoCallModal.show(
              context,
              participantName: isClient ? widget.caregiverName : 'Familia',
              participantImageUrl: _resolvedCaregiverImage,
              isCaregiver: !isClient,
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeaderAvatar(bool isClient, ChatConversation? conv) {
    if (!isClient) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: const Color(0xFFE0F2FE),
        child: const Icon(
          Icons.family_restroom_rounded,
          color: Color(0xFF0369A1),
          size: 20,
        ),
      );
    }

    final initialUrl = _resolvedCaregiverImage ?? conv?.caregiverImageUrl ?? '';
    if (initialUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: AppTheme.primarySurface,
        backgroundImage: CachedNetworkImageProvider(initialUrl),
      );
    }

    return FutureBuilder<CaregiverProfile?>(
      future: _peerCaregiverFuture,
      builder: (context, snap) {
        final url = snap.data?.imageUrl ?? '';
        if (url.isNotEmpty) {
          return CircleAvatar(
            radius: 19,
            backgroundColor: AppTheme.primarySurface,
            backgroundImage: CachedNetworkImageProvider(url),
          );
        }
        final initial = widget.caregiverName.isNotEmpty
            ? widget.caregiverName[0].toUpperCase()
            : 'C';
        return CircleAvatar(
          radius: 19,
          backgroundColor: AppTheme.primarySurface,
          child: Text(
            initial,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Buscar en esta conversación...',
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFFFFF7ED),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: Colors.orange.shade800,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Por tu seguridad, teléfonos y emails se desbloquean al confirmar la reserva.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _formatDateHeader(date),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.slateMuted,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageRow(
    ChatMessage m, {
    required bool isMe,
    required bool isFirstInGroup,
    required bool isLastInGroup,
    required String viewerUserId,
    required List<ChatMessage> loadedMessages,
  }) {
    final msgKey = m.id.isNotEmpty
        ? m.id
        : '${m.timestamp.millisecondsSinceEpoch}_${m.text.hashCode}';
    final isHighlighted =
        _highlightedMessageId != null && _highlightedMessageId == m.id;
    final bubbleColor =
        isMe ? const Color(0xFFD9F3F0) : Colors.white;

    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(!isMe && isFirstInGroup ? 4 : 16),
      topRight: Radius.circular(isMe && isFirstInGroup ? 4 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    final bottomSpacing = isLastInGroup ? 8.0 : 2.5;

    Widget bubble = Container(
      margin: EdgeInsets.only(bottom: bottomSpacing),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: EdgeInsets.fromLTRB(
        m.type == ChatMessageType.image && !m.isDeleted ? 6 : 12,
        m.type == ChatMessageType.image && !m.isDeleted ? 6 : 8,
        m.type == ChatMessageType.image && !m.isDeleted ? 6 : 12,
        6,
      ),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFFEF08A) : bubbleColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: isMe
              ? AppTheme.primary.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.replyToText != null && !m.isDeleted)
            _buildQuotedSnippet(m, loadedMessages),
          _buildMessageBody(m, msgKey, isMe),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                DateFormat('HH:mm').format(m.timestamp),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.slateMuted,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  m.isPending
                      ? Icons.access_time_rounded
                      : (m.isRead ? Icons.done_all_rounded : Icons.done_rounded),
                  size: 15,
                  color: m.isRead
                      ? const Color(0xFF0284C7)
                      : AppTheme.slateMuted,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (m.reactions.isNotEmpty && !m.isDeleted) {
      bubble = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Wrap(
                spacing: 4,
                children: m.reactions.values
                    .toSet()
                    .map((emoji) => Text(emoji, style: const TextStyle(fontSize: 14)))
                    .toList(),
              ),
            ),
          ),
        ],
      );
    }

    return Dismissible(
      key: ValueKey('swipe_$msgKey'),
      direction: m.isDeleted ? DismissDirection.none : DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        _setReplyTo(m);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.reply_rounded, color: AppTheme.primary),
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showMessageActions(
            m,
            isMe: isMe,
            viewerUserId: viewerUserId,
          ),
          child: bubble,
        ),
      ),
    );
  }

  Widget _buildQuotedSnippet(
    ChatMessage m,
    List<ChatMessage> loadedMessages,
  ) {
    final senderTitle = m.replyToSender == ChatSender.Caregiver
        ? widget.caregiverName
        : 'Familia';

    return InkWell(
      onTap: () => _jumpToQuotedMessage(m.replyToMessageId, loadedMessages),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: AppTheme.primary, width: 3.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            Text(
              m.replyToText ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBody(ChatMessage m, String msgKey, bool isMe) {
    if (m.isDeleted) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 15, color: AppTheme.slateMuted),
          SizedBox(width: 6),
          Text(
            'Mensaje eliminado',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: AppTheme.slateMuted,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    switch (m.type) {
      case ChatMessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.mediaUrl != null && m.mediaUrl!.isNotEmpty)
              GestureDetector(
                onTap: () => _openFullImageViewer(m.mediaUrl!, m.text),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      minWidth: 180,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: m.mediaUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        height: 160,
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => Container(
                        height: 120,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (m.text.trim().isNotEmpty && m.text.trim() != '📷 Foto')
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                child: Text(
                  m.text,
                  style: const TextStyle(
                    color: AppTheme.darkSlate,
                    fontSize: 15,
                  ),
                ),
              ),
          ],
        );

      case ChatMessageType.audio:
        final isPlayingThis =
            _playingMessageId == msgKey && _playerState == PlayerState.playing;
        final totalSecs = _playingMessageId == msgKey && _playDuration.inSeconds > 0
            ? _playDuration.inSeconds
            : (m.audioDurationSeconds ?? 1);
        final posSecs = _playingMessageId == msgKey ? _playPosition.inSeconds : 0;
        final progress =
            totalSecs > 0 ? (posSecs / totalSecs).clamp(0.0, 1.0) : 0.0;

        String formatDur(int s) =>
            '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _toggleAudioPlayback(m, msgKey),
              icon: Icon(
                isPlayingThis
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: AppTheme.primary,
                size: 36,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 135,
                  child: LinearProgressIndicator(
                    value: isPlayingThis || _playingMessageId == msgKey
                        ? progress
                        : 0,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playingMessageId == msgKey
                      ? '${formatDur(posSecs)} / ${formatDur(totalSecs)}'
                      : formatDur(m.audioDurationSeconds ?? 0),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.slateMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _cyclePlaybackSpeed,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _playbackRate == 1.5 ? '1.5x' : '1x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
            ),
          ],
        );

      case ChatMessageType.location:
        return InkWell(
          onTap: () async {
            if (m.latitude == null || m.longitude == null) return;
            final uri = Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=${m.latitude},${m.longitude}',
            );
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF15803D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ubicación compartida',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    Text(
                      'Toca para abrir en el mapa',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case ChatMessageType.call:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                m.text,
                style: const TextStyle(
                  color: AppTheme.darkSlate,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );

      case ChatMessageType.system:
      case ChatMessageType.text:
        return Text(
          m.text,
          style: const TextStyle(
            color: AppTheme.darkSlate,
            fontSize: 15.5,
            height: 1.32,
          ),
        );
    }
  }

  Widget _buildReplyComposerPreview() {
    final reply = _replyingTo!;
    final senderLabel = reply.sender == ChatSender.Caregiver
        ? widget.caregiverName
        : 'Familia';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: const Border(
            left: BorderSide(color: AppTheme.primary, width: 4),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Respondiendo a $senderLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    reply.previewSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _replyingTo = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer({
    required bool isClient,
    required bool hasConfirmedBooking,
  }) {
    if (_isRecordingVoice) {
      final mins = _recordingSeconds ~/ 60;
      final secs = (_recordingSeconds % 60).toString().padLeft(2, '0');
      return SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancelar grabación',
                onPressed: _cancelVoiceRecording,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.fiber_manual_record_rounded,
                        color: Colors.red.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Grabando $mins:$secs',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 23,
                backgroundColor: AppTheme.primary,
                child: IconButton(
                  tooltip: 'Enviar nota de voz',
                  onPressed: () => _finishAndSendVoiceRecording(
                    isClient: isClient,
                    allowContactSharing: hasConfirmedBooking,
                  ),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Adjuntar foto o ubicación',
              onPressed: () => _showAttachmentSheet(
                isClient: isClient,
                hasConfirmedBooking: hasConfirmedBooking,
              ),
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppTheme.slateMuted,
                size: 26,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _inputFocusNode,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (_hasComposerText) {
                    _sendTextMessage(
                      isClient: isClient,
                      allowContactSharing: hasConfirmedBooking,
                    );
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Mensaje',
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 23,
              backgroundColor: AppTheme.primary,
              child: IconButton(
                tooltip: _hasComposerText ? 'Enviar' : 'Grabar nota de voz',
                onPressed: _hasComposerText
                    ? () => _sendTextMessage(
                          isClient: isClient,
                          allowContactSharing: hasConfirmedBooking,
                        )
                    : _startVoiceRecording,
                icon: Icon(
                  _hasComposerText ? Icons.send_rounded : Icons.mic_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
