import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/firebase/firestore_stats_repository.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/address_form_widget.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'onboarding/live_dni_scanner_screen.dart';

class CaregiverProfileEditScreen extends StatefulWidget {
  const CaregiverProfileEditScreen({super.key});

  @override
  State<CaregiverProfileEditScreen> createState() =>
      _CaregiverProfileEditScreenState();
}

class _CaregiverProfileEditScreenState
    extends State<CaregiverProfileEditScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  String? _loadError;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isSyncingKyc = false;
  bool _isResolvingGps = false;
  bool _isUploadingVoice = false;
  CaregiverProfile? _profile;

  Future<void> _uploadVoiceIntro() async {
    if (_profile == null || _isUploadingVoice) return;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes ??
          (!kIsWeb && file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('No se pudieron leer los datos del audio.');
      }

      if (mounted) setState(() => _isUploadingVoice = true);
      final ext =
          p.extension(file.name).isNotEmpty ? p.extension(file.name).toLowerCase() : '.m4a';
      String voiceUrl;
      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('caregiver_voice')
            .child(_profile!.id)
            .child('intro_${DateTime.now().millisecondsSinceEpoch}$ext');
        await ref.putData(bytes, SettableMetadata(contentType: 'audio/${ext.replaceFirst(".", "")}'));
        voiceUrl = await ref.getDownloadURL();
      } else {
        voiceUrl = 'https://senicare-3342d.web.app/mock_voice_${_profile!.id}$ext';
      }

      await DependencyInjection.caregivers
          .updateProfile(_profile!.id, {'voiceIntroUrl': voiceUrl});
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: 'Audio de presentación guardado correctamente.',
        type: SnackBarType.success,
      );
      await _loadProfile();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al subir el audio: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingVoice = false);
    }
  }

  Future<void> _removeVoiceIntro() async {
    if (_profile == null || _isUploadingVoice) return;
    setState(() => _isUploadingVoice = true);
    try {
      await DependencyInjection.caregivers
          .updateProfile(_profile!.id, {'voiceIntroUrl': ''});
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: 'Audio de presentación eliminado.',
        type: SnackBarType.info,
      );
      await _loadProfile();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo eliminar el audio: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingVoice = false);
    }
  }

  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _homeAddressCtrl = TextEditingController();

  // Document & photo draft state
  String? _dniFrontPath;
  String? _criminalPath;
  String _dniScannedText = '';
  String _criminalScannedText = '';
  bool _criminalIsPdf = false;
  String? _dniFrontUrl;
  String? _criminalUrl;
  double? _homeLat;
  double? _homeLon;
  double _maxDistanceRadius = 10.0;
  List<String> _selectedSpecialties = [];
  String? _newImageUrl;
  String _initialAddressSnapshot = '';

  static const List<String> _allSpecialties = [
    'Movilidad',
    'Cocina Médica',
    'Compañía',
    'Soporte Digital',
    'Demencia',
    'Post-operatorio',
    'Alzheimer',
    'Fisioterapia',
    'Administración',
    'Emergencias',
  ];

  static const List<String> _suggestedTitles = [
    'Auxiliar de Enfermería',
    'Enfermera Geriátrica',
    'Gerocultor/a',
    'Cuidador/a de Mayores',
    'Fisioterapeuta',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _bioCtrl.dispose();
    _priceCtrl.dispose();
    _homeAddressCtrl.dispose();
    super.dispose();
  }

  void _syncDraftFromProfile(CaregiverProfile profile) {
    _profile = profile;
    _nameCtrl.text = profile.name == 'Sin nombre' ? '' : profile.name;
    _titleCtrl.text = profile.title;
    _bioCtrl.text = profile.bio.startsWith('Nuevo cuidador registrado')
        ? ''
        : profile.bio;
    _priceCtrl.text = profile.pricePerHour > 0
        ? (profile.pricePerHour == profile.pricePerHour.roundToDouble()
            ? profile.pricePerHour.toInt().toString()
            : profile.pricePerHour.toStringAsFixed(2))
        : '';
    _homeAddressCtrl.text = profile.homeAddress;
    _initialAddressSnapshot = profile.homeAddress;
    _homeLat = profile.latitude;
    _homeLon = profile.longitude;
    _maxDistanceRadius = profile.maxDistanceRadius.clamp(1.0, 50.0);
    _selectedSpecialties = List<String>.from(profile.specialties);
    _newImageUrl = profile.imageUrl;
    _dniFrontUrl = profile.dniUrl;
    _criminalUrl = profile.criminalRecordUrl;
    _dniFrontPath = null;
    _criminalPath = null;
    _dniScannedText = '';
    _criminalScannedText = '';
    _criminalIsPdf = false;
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = 'No hay una sesión activa.';
          });
        }
        return;
      }

      final myProfile = await DependencyInjection.caregivers.getCaregiver(userId);
      if (!mounted) return;

      if (myProfile == null) {
        setState(() {
          _isLoading = false;
          _loadError =
              'No hemos encontrado tu ficha de cuidador. Pulsa Reintentar para cargarla.';
        });
        return;
      }

      setState(() {
        _syncDraftFromProfile(myProfile);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading caregiver profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'No se pudo cargar tu perfil. Comprueba tu conexión.';
        });
      }
    }
  }

  List<String> _computeMissingItems(CaregiverProfile user) {
    final List<String> missing = [];
    final hasDefaultName =
        user.name == 'Sin nombre' || user.name.trim().isEmpty;
    final hasDefaultBio = user.bio.trim().isEmpty ||
        user.bio.startsWith('Nuevo cuidador registrado');
    final hasDefaultImage = user.imageUrl.trim().isEmpty ||
        user.imageUrl.contains('unsplash.com/photo-1573496359142-b8d87734a5a2');

    if (hasDefaultName) missing.add('Nombre completo');
    if (hasDefaultBio) missing.add('Presentación ("Acerca de mí")');
    if (hasDefaultImage) missing.add('Foto de perfil');
    if (user.homeAddress.trim().isEmpty) missing.add('Dirección de residencia');
    if (user.pricePerHour < 6.0) missing.add('Tarifa por hora (mínimo 6 €)');
    if (!user.hasDni) missing.add('DNI o NIE');
    if (!user.hasCriminalRecord) {
      missing.add('Certificado de Antecedentes Penales');
    }
    if (user.stripeAccountId == null || user.stripeAccountId!.trim().isEmpty) {
      missing.add('Cuenta bancaria (Stripe)');
    }
    return missing;
  }

  double? _parsePriceInput(String raw) {
    final clean = raw
        .trim()
        .replaceAll('€', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(clean);
  }

  Future<void> _saveProfile() async {
    if (_profile == null || _isSaving) return;

    final cleanName = _nameCtrl.text.trim();
    if (cleanName.isEmpty || cleanName == 'Sin nombre') {
      CustomSnackBar.show(
        context,
        message: 'Por favor, escribe tu nombre completo.',
        type: SnackBarType.error,
      );
      return;
    }

    final cleanBio = _bioCtrl.text.trim();
    if (cleanBio.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Escribe una breve presentación para que las familias te conozcan.',
        type: SnackBarType.error,
      );
      return;
    }

    final parsedPrice = _parsePriceInput(_priceCtrl.text);
    if (parsedPrice == null || parsedPrice < 6.0) {
      CustomSnackBar.show(
        context,
        message: 'Por política de SeniCare, la tarifa mínima es de 6 €/hora.',
        type: SnackBarType.error,
      );
      return;
    }
    if (parsedPrice > 120.0) {
      CustomSnackBar.show(
        context,
        message: 'La tarifa máxima permitida es de 120 €/hora.',
        type: SnackBarType.error,
      );
      return;
    }

    final cleanAddress = _homeAddressCtrl.text.trim();
    if (cleanAddress.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Indica tu dirección de residencia o usa el botón GPS.',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Preserve existing coordinates if address text was not changed
      if (_homeLat == null || _homeLon == null) {
        if (cleanAddress == _profile!.homeAddress &&
            _profile!.latitude != null &&
            _profile!.longitude != null) {
          _homeLat = _profile!.latitude;
          _homeLon = _profile!.longitude;
        } else {
          final coords = await NominatimService.geocodeAddress(cleanAddress);
          if (coords != null) {
            _homeLat = coords.latitude;
            _homeLon = coords.longitude;
          } else if (_profile!.latitude != null && _profile!.longitude != null) {
            _homeLat = _profile!.latitude;
            _homeLon = _profile!.longitude;
          } else {
            if (mounted) {
              CustomSnackBar.show(
                context,
                message:
                    'No pudimos localizar la dirección en el mapa. Selecciónala de la lista o pulsa "Usar ubicación GPS".',
                type: SnackBarType.error,
              );
            }
            return;
          }
        }
      }

      String imageUrl = _newImageUrl ?? _profile!.imageUrl;
      String dniUrl = _dniFrontUrl ?? '';
      String criminalUrl = _criminalUrl ?? '';

      if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
        imageUrl = await _uploadAvatar(imageUrl);
      }

      if (_dniFrontPath != null) {
        dniUrl = await _uploadFile(_dniFrontPath!, 'caregiver_docs') ?? '';
      }
      if (_criminalPath != null) {
        criminalUrl = await _uploadFile(_criminalPath!, 'caregiver_docs') ?? '';
      }

      String? updatedVerificationStatus;
      if (_dniFrontPath != null || _criminalPath != null) {
        updatedVerificationStatus = _validateIdentity();
      }

      final hasImage = imageUrl.isNotEmpty &&
          !imageUrl.contains('unsplash.com/photo-1573496359142-b8d87734a5a2');
      final hasDni = dniUrl.isNotEmpty;
      final hasCriminal = criminalUrl.isNotEmpty;
      final hasStripe = _profile!.stripeAccountId != null &&
          _profile!.stripeAccountId!.isNotEmpty;

      final onboardingComplete = cleanName.isNotEmpty &&
          cleanBio.isNotEmpty &&
          cleanAddress.isNotEmpty &&
          hasImage &&
          hasDni &&
          hasCriminal &&
          hasStripe;

      final updatedData = <String, dynamic>{
        'name': cleanName,
        'title': _titleCtrl.text.trim(),
        'bio': cleanBio,
        'pricePerHour': parsedPrice,
        'homeAddress': cleanAddress,
        'latitude': _homeLat,
        'longitude': _homeLon,
        'maxDistanceRadius': _maxDistanceRadius,
        'specialties': _selectedSpecialties,
        'imageUrl': imageUrl,
        'hasDniSubmitted': hasDni,
        'hasCriminalSubmitted': hasCriminal,
        if (!useFirebaseBackend || Firebase.apps.isEmpty) ...{
          'dniUrl': dniUrl,
          'criminalRecordUrl': criminalUrl,
        },
        'verificationStatus': ?updatedVerificationStatus,
        'onboardingComplete': onboardingComplete,
      };

      await DependencyInjection.caregivers
          .updateProfile(_profile!.id, updatedData);

      if (useFirebaseBackend &&
          Firebase.apps.isNotEmpty &&
          (_dniFrontPath != null ||
              _criminalPath != null ||
              _dniScannedText.isNotEmpty ||
              _criminalScannedText.isNotEmpty ||
              _profile!.verificationStatus != 'approved')) {
        await FirebaseFirestore.instance
            .collection('caregivers')
            .doc(_profile!.id)
            .collection('private')
            .doc('verification')
            .set({
          'dniUrl': dniUrl,
          'criminalRecordUrl': criminalUrl,
          if (_dniScannedText.isNotEmpty) 'dniScannedText': _dniScannedText,
          if (_criminalScannedText.isNotEmpty)
            'criminalScannedText': _criminalScannedText,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      final authNotifier = context.read<AuthNotifier>();
      await authNotifier.reloadRole();
      if (!mounted) return;

      CustomSnackBar.show(
        context,
        message: useFirebaseBackend
            ? 'Perfil actualizado correctamente'
            : 'Perfil simulado actualizado correctamente',
        type: SnackBarType.success,
      );
      setState(() => _isEditing = false);
      await _loadProfile();
    } catch (e) {
      debugPrint('Error saving caregiver profile: $e');
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al guardar el perfil: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<String> _uploadAvatar(String localPath) async {
    final bytes = await XFile(localPath).readAsBytes();
    final ref = FirebaseStorage.instance
        .ref()
        .child('caregiver_avatars')
        .child('${_profile!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<String?> _uploadFile(String path, String folder) async {
    if (path.startsWith('http')) return path;

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('El archivo local seleccionado no existe.');
    }

    final userId = _profile!.id;
    final ext =
        p.extension(path).isNotEmpty ? p.extension(path).toLowerCase() : '.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child(folder)
        .child('${userId}_${DateTime.now().millisecondsSinceEpoch}$ext');

    String contentType = 'application/octet-stream';
    if (ext == '.pdf') {
      contentType = 'application/pdf';
    } else if (ext == '.png') {
      contentType = 'image/png';
    } else if (ext == '.jpg' || ext == '.jpeg') {
      contentType = 'image/jpeg';
    }

    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return await ref.getDownloadURL();
  }

  Future<void> _useCurrentGpsLocation() async {
    if (_isResolvingGps) return;
    setState(() => _isResolvingGps = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Activa la ubicación (GPS) del dispositivo.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado.');
      }

      final pos = await Geolocator.getCurrentPosition();
      final readable =
          await NominatimService.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;

      setState(() {
        _homeLat = pos.latitude;
        _homeLon = pos.longitude;
        if (readable != null && readable.trim().isNotEmpty) {
          _homeAddressCtrl.text = readable.trim();
          _initialAddressSnapshot = readable.trim();
        }
      });
      CustomSnackBar.show(
        context,
        message: 'Ubicación GPS guardada correctamente.',
        type: SnackBarType.success,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo obtener la ubicación: $e',
          type: SnackBarType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isResolvingGps = false);
    }
  }

  Future<void> _pickAvatarImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
                title: const Text('Hacer una foto ahora'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                title: const Text('Elegir de la galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (image != null && mounted) {
        final savedPath = await _persistFile(image.path);
        if (!mounted) return;
        setState(() {
          _newImageUrl = savedPath;
          _isEditing = true;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al seleccionar la foto: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<String> _persistFile(String originalPath) async {
    final file = File(originalPath);
    if (!await file.exists()) return originalPath;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(originalPath);
    final newPath = p.join(dir.path, 'senicare_tmp_$fileName');

    final newFile = await file.copy(newPath);
    return newFile.path;
  }

  Future<void> _readDNI(String path) async {
    if (mounted) setState(() => _isSaving = true);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      final buf = StringBuffer();
      for (final block in recognizedText.blocks) {
        if (block.text.contains(RegExp(r'[0-9]{8}[A-Za-z]'))) {
          buf.writeln('DNI/NIE: ${block.text}');
        } else if (block.text.length > 5) {
          buf.writeln(block.text);
        }
      }
      if (mounted) setState(() => _dniScannedText = buf.toString());
    } catch (e) {
      debugPrint('DNI OCR error: $e');
    } finally {
      await textRecognizer.close();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _scanDniLive() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveDniScannerScreen()),
    );
    if (result != null && result is Map && result['path'] != null) {
      final savedPath = await _persistFile(result['path'].toString());
      if (!mounted) return;
      setState(() {
        _dniFrontPath = savedPath;
        _dniScannedText = (result['text'] ?? '').toString();
      });
    }
  }

  Future<void> _pickDniDocument() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.document_scanner_rounded,
                color: AppTheme.primary,
              ),
              title: const Text('Escanear DNI / NIE en vivo (Cámara)'),
              onTap: () {
                Navigator.pop(ctx);
                _scanDniLive();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppTheme.primary,
              ),
              title: const Text('Elegir foto de galería'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(
                  source: ImageSource.gallery,
                  (path) async {
                    setState(() => _dniFrontPath = path);
                    await _readDNI(path);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(
    Future<void> Function(String) onPicked, {
    required ImageSource source,
  }) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 75);
      if (image != null) {
        final savedPath = await _persistFile(image.path);
        if (!mounted) return;
        await onPicked(savedPath);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al seleccionar imagen: $e',
          type: SnackBarType.warning,
        );
      }
    }
  }

  Future<void> _pickCriminalRecord() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
              title: const Text('Hacer foto al certificado'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(
                  source: ImageSource.camera,
                  (path) async {
                    setState(() {
                      _criminalPath = path;
                      _criminalIsPdf = false;
                      _isSaving = true;
                    });
                    await _extractTextFromImage(path);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
              title: const Text('Elegir foto de galería'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(
                  source: ImageSource.gallery,
                  (path) async {
                    setState(() {
                      _criminalPath = path;
                      _criminalIsPdf = false;
                      _isSaving = true;
                    });
                    await _extractTextFromImage(path);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary),
              title: const Text('Subir archivo PDF oficial'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                  );
                  if (result != null && result.files.single.path != null) {
                    final savedPath =
                        await _persistFile(result.files.single.path!);
                    if (!mounted) return;
                    setState(() {
                      _criminalPath = savedPath;
                      _criminalIsPdf = true;
                      _isSaving = true;
                    });
                    await _extractTextFromPdf(savedPath);
                  }
                } catch (e) {
                  debugPrint('PDF picker error: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractTextFromPdf(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final String text = PdfTextExtractor(document).extractText();
      document.dispose();
      if (mounted) setState(() => _criminalScannedText = text);
    } catch (e) {
      debugPrint('PDF extraction error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _extractTextFromImage(String path) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      if (mounted) setState(() => _criminalScannedText = recognizedText.text);
    } catch (e) {
      debugPrint('Image extraction error: $e');
    } finally {
      await textRecognizer.close();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _validateIdentity() {
    if (_dniScannedText.isEmpty || _criminalScannedText.isEmpty) {
      return 'pending';
    }

    final nameRaw = _nameCtrl.text.trim().toLowerCase();
    final normalizedName = nameRaw
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    final nameParts =
        normalizedName.split(' ').where((part) => part.length > 2).toList();

    final dniTextNorm = _dniScannedText.toLowerCase();
    final crimTextNorm = _criminalScannedText.toLowerCase();

    final dniRegExp = RegExp(r'\b[0-9]{8}[a-z]\b|\b[xyz][0-9]{7}[a-z]\b');
    final dniMatch = dniRegExp.firstMatch(dniTextNorm);
    if (dniMatch == null) return 'pending';

    final extractedDni = dniMatch.group(0)!;
    if (!crimTextNorm.contains(extractedDni)) return 'pending';

    int matchDniCount = 0;
    int matchCrimCount = 0;
    for (final part in nameParts) {
      if (dniTextNorm.contains(part)) matchDniCount++;
      if (crimTextNorm.contains(part)) matchCrimCount++;
    }

    if (matchDniCount >= 1 && matchCrimCount >= 1) {
      return 'manual_review';
    }
    return 'pending';
  }

  Future<void> _handleStripeConnect() async {
    if (_profile == null) return;
    try {
      if (_profile!.stripeAccountId != null &&
          _profile!.stripeAccountId!.isNotEmpty) {
        CustomSnackBar.show(
          context,
          message: 'Abriendo tu panel bancario en Stripe...',
          type: SnackBarType.info,
        );
        await StripeService.openBankAccountManagement(
          _profile!.stripeAccountId!,
        );
        return;
      }

      CustomSnackBar.show(
        context,
        message: 'Creando tu cuenta segura de cobros...',
        type: SnackBarType.info,
      );
      final accountId = await StripeService.createConnectAccount();
      if (!mounted) return;
      if (accountId == null || accountId.isEmpty) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo conectar con Stripe. Inténtalo de nuevo.',
          type: SnackBarType.error,
        );
        return;
      }

      await DependencyInjection.caregivers.updateProfile(_profile!.id, {
        'stripeAccountId': accountId,
      });
      await _loadProfile();
      await StripeService.launchOnboarding(accountId);
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al conectar Stripe: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _handleSyncKyc() async {
    if (_profile == null || _isSyncingKyc) return;
    setState(() => _isSyncingKyc = true);
    try {
      final isVerified = await StripeService.syncStripeKycStatus();
      await _loadProfile();
      if (!mounted) return;
      await context.read<AuthNotifier>().reloadRole();
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: isVerified
            ? '¡Cuenta bancaria verificada y lista para recibir pagos!'
            : 'Stripe todavía necesita algún dato bancario. Pulsa "Gestionar banco" para completarlo.',
        type: isVerified ? SnackBarType.success : SnackBarType.warning,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No pudimos comprobar el estado bancario ahora: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingKyc = false);
    }
  }

  void _showDocumentsGuideModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_user,
                    color: AppTheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Guía rápida: Sube tus documentos en 2 minutos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '1. DNI o NIE en vigor:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Pulsa en "Escanear DNI / NIE" y enfoca la parte delantera con buena luz.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '2. Certificado de Antecedentes Penales / Delitos Sexuales (Gratis):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Descárgalo al instante en sede.mjusticia.gob.es con Cl@ve o Certificado Digital.\n'
                '• Sube el PDF o hazle una foto nítida.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '3. Cuenta Bancaria (Stripe Connect):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Añade tu IBAN español para recibir automáticamente el dinero de cada servicio finalizado.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Seguro que quieres salir de tu cuenta de cuidador?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DependencyInjection.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSenior = false;
    try {
      isSenior = context.watch<ConfigNotifier>().seniorMode;
    } catch (_) {}
    final fontMult = isSenior ? 1.25 : 1.0;
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    if (_isLoading) {
      return Scaffold(
        appBar: canPop ? AppBar(title: const Text('Mi Perfil de Cuidador')) : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _profile == null) {
      return Scaffold(
        appBar: canPop ? AppBar(title: const Text('Mi Perfil de Cuidador')) : null,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_off_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'No pudimos cargar tu perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16 * fontMult,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _loadProfile,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final missingItems = _computeMissingItems(profile);
    final isApproved =
        profile.verified || profile.verificationStatus == 'approved';
    final isRejected = profile.verificationStatus == 'rejected';
    final tutorialTargets = TutorialScope.maybeOf(context);
    final displayedSpecialties = {
      ..._allSpecialties,
      ..._selectedSpecialties,
    }.toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundNeutral,
      appBar: canPop
          ? AppBar(
              title: Text(
                _isEditing ? 'Editar Mi Perfil' : 'Mi Perfil Profesional',
              ),
            )
          : null,
      bottomNavigationBar: _isEditing
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, isSenior ? 52 : 46),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _syncDraftFromProfile(profile);
                                  _isEditing = false;
                                });
                              },
                        child: Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 15 * fontMult),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: Size(0, isSenior ? 52 : 46),
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSaving ? 'Guardando...' : 'Guardar cambios',
                          style: TextStyle(
                            fontSize: 15 * fontMult,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildHeaderCard(profile, fontMult, isSenior),
            const SizedBox(height: 14),
            if (!_isEditing) ...[
              Column(
                key: tutorialTargets?.profileStatusKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(
                    profile: profile,
                    missingItems: missingItems,
                    isApproved: isApproved,
                    isRejected: isRejected,
                    fontMult: fontMult,
                  ),
                  const SizedBox(height: 16),
                  _buildQuickActionsRow(profile, fontMult, isSenior),
                ],
              ),
              const SizedBox(height: 16),
              _buildReadOnlySections(
                profile,
                fontMult,
                isSenior,
                docsKey: tutorialTargets?.profileDocsKey,
              ),
            ] else ...[
              _buildStatusCard(
                profile: profile,
                missingItems: missingItems,
                isApproved: isApproved,
                isRejected: isRejected,
                fontMult: fontMult,
              ),
              const SizedBox(height: 16),
              _buildEditingSections(
                profile,
                displayedSpecialties,
                isApproved,
                fontMult,
                isSenior,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    CaregiverProfile profile,
    double fontMult,
    bool isSenior,
  ) {
    final minRate = FirestoreStatsRepository.calculateCommissionRate(0);
    final maxRate = FirestoreStatsRepository.calculateCommissionRate(81);
    final minNet = profile.pricePerHour * (1.0 - minRate);
    final maxNet = profile.pricePerHour * (1.0 - maxRate);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.modernCardDecoration(radius: 22),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickAvatarImage,
                child: Stack(
                  children: [
                    _buildSafeAvatar(profile, radius: isSenior ? 42 : 38),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name == 'Sin nombre' || profile.name.trim().isEmpty
                          ? 'Tu nombre'
                          : profile.name,
                      style: TextStyle(
                        fontSize: 20 * fontMult,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.title.trim().isNotEmpty
                          ? profile.title
                          : 'Cuidador/a SeniCare',
                      style: TextStyle(
                        fontSize: 13.5 * fontMult,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${profile.pricePerHour.toStringAsFixed(0)} €/h',
                            style: TextStyle(
                              fontSize: 13.5 * fontMult,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        if (profile.reviewsCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                                size: 18,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${profile.rating.toStringAsFixed(1)} (${profile.reviewsCount})',
                                style: TextStyle(
                                  fontSize: 13 * fontMult,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.darkSlate,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.pricePerHour >= 6) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recibes neto: ${minNet.toStringAsFixed(2)} € – ${maxNet.toStringAsFixed(2)} €/h según horas con cada familia.',
                style: TextStyle(
                  fontSize: 12 * fontMult,
                  color: AppTheme.slateMuted,
                ),
              ),
            ),
          ],
          if (!_isEditing) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size(0, isSenior ? 50 : 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(
                      'Editar perfil',
                      style: TextStyle(
                        fontSize: 14.5 * fontMult,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.darkSlate,
                      minimumSize: Size(0, isSenior ? 50 : 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CaregiverDetailScreen(
                            caregiver: profile,
                            isPreview: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(
                      'Vista previa',
                      style: TextStyle(
                        fontSize: 14.5 * fontMult,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSafeAvatar(CaregiverProfile profile, {required double radius}) {
    final currentImg = _newImageUrl ?? profile.imageUrl;
    if (currentImg.isNotEmpty && !currentImg.startsWith('http') && !kIsWeb) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primarySurface,
        backgroundImage: FileImage(File(currentImg)),
      );
    }
    if (currentImg.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primarySurface,
        backgroundImage: CachedNetworkImageProvider(currentImg),
      );
    }

    final initial = profile.name.trim().isNotEmpty && profile.name != 'Sin nombre'
        ? profile.name.trim()[0].toUpperCase()
        : 'C';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primarySurface,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required CaregiverProfile profile,
    required List<String> missingItems,
    required bool isApproved,
    required bool isRejected,
    required double fontMult,
  }) {
    final int totalSteps = 8;
    final int completedSteps =
        (totalSteps - missingItems.length).clamp(0, totalSteps);
    final double progress = completedSteps / totalSteps;

    late Color bgColor;
    late Color borderColor;
    late Color accentColor;
    late IconData icon;
    late String title;
    late String subtitle;

    if (isApproved && missingItems.isEmpty) {
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      accentColor = const Color(0xFF047857);
      icon = Icons.verified_rounded;
      title = 'Perfil Verificado y Visible ✓';
      subtitle = 'Las familias ya pueden encontrarte y enviarte reservas.';
    } else if (isRejected) {
      bgColor = Colors.red.shade50;
      borderColor = Colors.red.shade200;
      accentColor = Colors.red.shade900;
      icon = Icons.error_outline_rounded;
      title = 'Documentación rechazada';
      subtitle =
          'Vuelve a subir tu DNI o certificado de penales con buena iluminación para aprobar tu perfil.';
    } else if (missingItems.isNotEmpty) {
      bgColor = const Color(0xFFFFF7ED);
      borderColor = Colors.orange.shade200;
      accentColor = Colors.orange.shade900;
      icon = Icons.checklist_rounded;
      title = 'Faltan ${missingItems.length} datos para activarte';
      subtitle = 'Pendiente: ${missingItems.join(' • ')}';
    } else {
      bgColor = const Color(0xFFEFF6FF);
      borderColor = Colors.blue.shade200;
      accentColor = Colors.blue.shade900;
      icon = Icons.hourglass_top_rounded;
      title = 'Documentación en revisión (<24h)';
      subtitle =
          'Has enviado todo lo necesario. Te notificaremos en cuanto el equipo lo apruebe.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13.5 * fontMult,
              color: accentColor,
              height: 1.35,
            ),
          ),
          if (missingItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$completedSteps de $totalSteps pasos completados',
              style: TextStyle(
                fontSize: 12 * fontMult,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
          if ((isRejected || missingItems.isNotEmpty) && !_isEditing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor),
                  backgroundColor: Colors.white.withValues(alpha: 0.7),
                ),
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(
                  isRejected ? 'Corregir documentos' : 'Completar ahora',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow(
    CaregiverProfile profile,
    double fontMult,
    bool isSenior,
  ) {
    return Row(
      children: [
        Expanded(
          child: _QuickTileButton(
            icon: Icons.calendar_month_rounded,
            color: AppTheme.primary,
            title: 'Mis Horarios',
            subtitle: 'Disponibilidad',
            fontMult: fontMult,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CaregiverCalendarScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTileButton(
            icon: Icons.account_balance_rounded,
            color: profile.stripeAccountId != null
                ? const Color(0xFF059669)
                : const Color(0xFF6366F1),
            title: profile.stripeAccountId != null
                ? 'Mi Banco'
                : 'Conectar Banco',
            subtitle: profile.isKycVerified
                ? 'Pagos activos ✓'
                : 'Revisar cobros',
            fontMult: fontMult,
            onTap: _handleStripeConnect,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlySections(
    CaregiverProfile profile,
    double fontMult,
    bool isSenior, {
    Key? docsKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Sobre mí y Especialidades',
          icon: Icons.person_pin_rounded,
          fontMult: fontMult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.bio.trim().isEmpty ||
                        profile.bio.startsWith('Nuevo cuidador registrado')
                    ? 'Aún no has escrito tu presentación. Pulsa "Editar perfil" para contar tu experiencia a las familias.'
                    : profile.bio,
                style: TextStyle(
                  fontSize: 15 * fontMult,
                  color: AppTheme.darkSlate,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              if (profile.specialties.isEmpty)
                Text(
                  'Sin especialidades seleccionadas.',
                  style: TextStyle(
                    fontSize: 13.5 * fontMult,
                    color: AppTheme.slateMuted,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.specialties
                      .map(
                        (spec) => Chip(
                          label: Text(
                            spec,
                            style: TextStyle(
                              fontSize: 13 * fontMult,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          backgroundColor: AppTheme.primarySurface,
                          side: BorderSide(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Zona de Trabajo',
          icon: Icons.location_on_rounded,
          fontMult: fontMult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: 'Dirección base',
                value: profile.homeAddress.trim().isEmpty
                    ? 'No especificada'
                    : profile.homeAddress,
                fontMult: fontMult,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: 'Distancia máxima',
                value: '${profile.maxDistanceRadius.toStringAsFixed(0)} km',
                fontMult: fontMult,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          key: docsKey,
          title: 'Documentos y Cuenta Bancaria',
          icon: Icons.verified_user_rounded,
          fontMult: fontMult,
          trailing: TextButton.icon(
            onPressed: _showDocumentsGuideModal,
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: const Text('Guía fácil'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusItemRow(
                label: 'Documento de Identidad (DNI / NIE)',
                done: profile.hasDni,
                doneLabel: 'Subido',
                pendingLabel: 'Pendiente',
                fontMult: fontMult,
              ),
              const SizedBox(height: 10),
              _StatusItemRow(
                label: 'Certificado de Antecedentes Penales',
                done: profile.hasCriminalRecord,
                doneLabel: 'Subido',
                pendingLabel: 'Pendiente',
                fontMult: fontMult,
              ),
              const SizedBox(height: 10),
              _StatusItemRow(
                label: 'Cuenta Bancaria (Stripe)',
                done: profile.stripeAccountId != null &&
                    profile.stripeAccountId!.isNotEmpty,
                doneLabel: profile.isKycVerified
                    ? 'Verificada (KYC ✓)'
                    : 'Conectada (KYC pendiente)',
                pendingLabel: 'Sin conectar',
                fontMult: fontMult,
              ),
              if (profile.stripeAccountId != null &&
                  profile.stripeAccountId!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _handleStripeConnect,
                        icon: const Icon(Icons.account_balance_outlined, size: 18),
                        label: const Text('Cambiar IBAN'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSyncingKyc ? null : _handleSyncKyc,
                        icon: _isSyncingKyc
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Comprobar KYC'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _handleStripeConnect,
                    icon: const Icon(Icons.account_balance_rounded),
                    label: const Text('Conectar cuenta bancaria'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Accesibilidad y Cuenta',
          icon: Icons.tune_rounded,
          fontMult: fontMult,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.text_increase_rounded,
                  color: AppTheme.primary,
                ),
                title: Text(
                  'Ajustes, Letra Grande y Privacidad',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15 * fontMult,
                  ),
                ),
                subtitle: Text(
                  'Activa el Modo Senior (+30% letra) o consulta tus coberturas.',
                  style: TextStyle(fontSize: 12.5 * fontMult),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  'Cerrar sesión',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 15 * fontMult,
                  ),
                ),
                onTap: _confirmSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditingSections(
    CaregiverProfile profile,
    List<String> displayedSpecialties,
    bool isApproved,
    double fontMult,
    bool isSenior,
  ) {
    final parsed = _parsePriceInput(_priceCtrl.text);
    final minRate = FirestoreStatsRepository.calculateCommissionRate(0);
    final previewNet = parsed != null && parsed >= 6
        ? (parsed * (1.0 - minRate)).toStringAsFixed(2)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Tus Datos Básicos',
          icon: Icons.edit_rounded,
          fontMult: fontMult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  border: OutlineInputBorder(),
                ),
                style: TextStyle(fontSize: 15.5 * fontMult),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titulación o perfil profesional',
                  hintText: 'Ej. Auxiliar de Enfermería Geriátrica',
                  border: OutlineInputBorder(),
                ),
                style: TextStyle(fontSize: 15 * fontMult),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _suggestedTitles
                    .map(
                      (t) => ActionChip(
                        label: Text(
                          t,
                          style: TextStyle(fontSize: 12 * fontMult),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _titleCtrl.text = t);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _bioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Acerca de mí (experiencia, formación, trato)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                style: TextStyle(fontSize: 14.5 * fontMult),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tarifa por hora (€)',
                  helperText: previewNet != null
                      ? 'Mínimo 6 €/h. Recibes desde $previewNet €/h neto.'
                      : 'Tarifa mínima: 6 €/hora.',
                  border: const OutlineInputBorder(),
                ),
                style: TextStyle(fontSize: 15.5 * fontMult),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.mic_rounded, color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Presentación en voz (opcional)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5 * fontMult,
                              color: AppTheme.darkSlate,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profile?.voiceIntroUrl.trim().isNotEmpty == true
                          ? 'Audio de presentación subido y visible en tu ficha pública.'
                          : 'Sube un breve audio (MP3, M4A o WAV) para presentarte a las familias.',
                      style: TextStyle(fontSize: 12 * fontMult, color: AppTheme.slateMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isUploadingVoice ? null : _uploadVoiceIntro,
                          icon: _isUploadingVoice
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.audio_file_rounded, size: 18),
                          label: Text(
                            _profile?.voiceIntroUrl.trim().isNotEmpty == true
                                ? 'Cambiar audio'
                                : 'Subir audio',
                          ),
                        ),
                        if (_profile?.voiceIntroUrl.trim().isNotEmpty == true)
                          TextButton.icon(
                            onPressed: _isUploadingVoice ? null : _removeVoiceIntro,
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            label: const Text(
                              'Eliminar',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Especialidades',
          icon: Icons.medical_services_outlined,
          fontMult: fontMult,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displayedSpecialties.map((spec) {
              final isSelected = _selectedSpecialties.contains(spec);
              return FilterChip(
                label: Text(spec, style: TextStyle(fontSize: 13.5 * fontMult)),
                selected: isSelected,
                onSelected: (selected) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (selected) {
                      if (!_selectedSpecialties.contains(spec)) {
                        _selectedSpecialties.add(spec);
                      }
                    } else {
                      _selectedSpecialties.remove(spec);
                    }
                  });
                },
                selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                checkmarkColor: AppTheme.primary,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Dirección y Radio de Desplazamiento',
          icon: Icons.map_outlined,
          fontMult: fontMult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AddressFormWidget(
                initialAddress: _homeAddressCtrl.text,
                onAddressChanged: (addr) {
                  _homeAddressCtrl.text = addr;
                  if (addr != _initialAddressSnapshot) {
                    _homeLat = null;
                    _homeLon = null;
                  }
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isResolvingGps ? null : _useCurrentGpsLocation,
                icon: _isResolvingGps
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  _homeLat != null
                      ? 'Actualizar con mi ubicación GPS actual ✓'
                      : 'Usar mi ubicación GPS actual',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Me desplazo hasta: ${_maxDistanceRadius.toStringAsFixed(0)} km',
                style: TextStyle(
                  fontSize: 15 * fontMult,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: _maxDistanceRadius,
                min: 1.0,
                max: 50.0,
                divisions: 49,
                label: '${_maxDistanceRadius.toStringAsFixed(0)} km',
                activeColor: AppTheme.primary,
                onChanged: (val) => setState(() => _maxDistanceRadius = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Documentación y Pagos',
          icon: Icons.verified_user_rounded,
          fontMult: fontMult,
          trailing: TextButton.icon(
            onPressed: _showDocumentsGuideModal,
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: const Text('Guía fácil'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isApproved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Tus documentos de identidad ya han sido aprobados por SeniCare y están protegidos.',
                    style: TextStyle(
                      fontSize: 13 * fontMult,
                      color: const Color(0xFF047857),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: isApproved ? null : _pickDniDocument,
                icon: const Icon(Icons.document_scanner_rounded),
                label: Text(
                  isApproved
                      ? 'DNI / NIE Verificado ✓'
                      : (_dniFrontUrl?.isNotEmpty == true ||
                              _dniFrontPath != null
                          ? 'Cambiar DNI / NIE'
                          : 'Escanear o subir DNI / NIE'),
                ),
              ),
              if (_dniFrontPath != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (!kIsWeb) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_dniFrontPath!),
                          height: 54,
                          width: 82,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        _dniScannedText.isNotEmpty
                            ? 'Documento escaneado y leído correctamente ✓'
                            : 'Imagen seleccionada ✓',
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_dniFrontUrl != null && _dniFrontUrl!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'DNI / NIE guardado ✓',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: isApproved ? null : _pickCriminalRecord,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: Text(
                  isApproved
                      ? 'Certificado de Penales Verificado ✓'
                      : (_criminalUrl?.isNotEmpty == true ||
                              _criminalPath != null
                          ? 'Cambiar Certificado de Penales'
                          : 'Subir Certificado de Penales'),
                ),
              ),
              if (_criminalPath != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Archivo listo para guardar (${_criminalIsPdf ? "PDF" : "Foto"}) ✓',
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (_criminalUrl != null && _criminalUrl!.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'Certificado de Penales guardado ✓',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.stripeAccountId != null
                      ? const Color(0xFF059669)
                      : Colors.deepPurple,
                  foregroundColor: Colors.white,
                  minimumSize: Size(0, isSenior ? 50 : 44),
                ),
                onPressed: _handleStripeConnect,
                icon: const Icon(Icons.account_balance_rounded),
                label: Text(
                  profile.stripeAccountId != null
                      ? 'Cambiar IBAN / Panel Bancario'
                      : 'Conectar cuenta bancaria (Stripe)',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickTileButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double fontMult;
  final VoidCallback onTap;

  const _QuickTileButton({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.fontMult,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5 * fontMult,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12 * fontMult,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double fontMult;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.fontMult,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.modernCardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final double fontMult;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.fontMult,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5 * fontMult,
            fontWeight: FontWeight.w700,
            color: AppTheme.slateMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15 * fontMult,
            color: AppTheme.darkSlate,
          ),
        ),
      ],
    );
  }
}

class _StatusItemRow extends StatelessWidget {
  final String label;
  final bool done;
  final String doneLabel;
  final String pendingLabel;
  final double fontMult;

  const _StatusItemRow({
    required this.label,
    required this.done,
    required this.doneLabel,
    required this.pendingLabel,
    required this.fontMult,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF059669) : Colors.orange.shade700,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5 * fontMult,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkSlate,
                ),
              ),
              Text(
                done ? doneLabel : pendingLabel,
                style: TextStyle(
                  fontSize: 12.5 * fontMult,
                  color: done ? const Color(0xFF059669) : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
