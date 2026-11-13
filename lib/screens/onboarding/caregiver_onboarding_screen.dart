import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/address_form_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'live_dni_scanner_screen.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CaregiverOnboardingScreen extends StatefulWidget {
  const CaregiverOnboardingScreen({super.key});

  @override
  State<CaregiverOnboardingScreen> createState() => _CaregiverOnboardingScreenState();
}

class _CaregiverOnboardingScreenState extends State<CaregiverOnboardingScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isSaving = false; // Auto-save indicator

  // Step 1: Personal
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _profileImagePath;
  String? _profileImageUrl; // URL after upload

  // Step 2: Ops
  final _priceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double _radius = 10;
  double? _homeLat;
  double? _homeLon;
  List<String> _specialties = [];

  // Step 3: Docs
  String? _dniFrontPath;
  String? _dniUrl; // URL after upload
  String? _criminalPath;
  String? _criminalUrl; // URL after upload
  String _dniScannedText = '';
  String _criminalScannedText = '';
  bool _criminalIsPdf = false;

  // Step 4: Stripe
  String? _stripeAccountId;

  final _picker = ImagePicker();

  static const List<String> _allSpecialties = [
    'Movilidad', 'Cocina Médica', 'Compañía', 'Soporte Digital',
    'Demencia', 'Post-operatorio', 'Alzheimer', 'Fisioterapia',
    'Administración', 'Emergencias',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingData();
    // Auto-save on text changes
    _nameCtrl.addListener(_autoSaveDraft);
    _bioCtrl.addListener(_autoSaveDraft);
    _priceCtrl.addListener(_autoSaveDraft);
    _addressCtrl.addListener(_autoSaveDraft);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_autoSaveDraft);
    _bioCtrl.removeListener(_autoSaveDraft);
    _priceCtrl.removeListener(_autoSaveDraft);
    _addressCtrl.removeListener(_autoSaveDraft);
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _priceCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Load any previously saved draft from Firestore
  Future<void> _loadExistingData() async {
    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      if (userId == null) return;

      final cgRef = FirebaseFirestore.instance.collection('caregivers').doc(userId);
      final doc = await cgRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      Map<String, dynamic> privateData = {};
      try {
        final privDoc = await cgRef.collection('private').doc('verification').get();
        if (privDoc.exists && privDoc.data() != null) {
          privateData = privDoc.data()!;
        }
      } catch (_) {}

      final loadedDni = (privateData['dniUrl'] ?? data['dniUrl'])?.toString() ?? '';
      final loadedCriminal = (privateData['criminalRecordUrl'] ?? data['criminalRecordUrl'])?.toString() ?? '';
      final loadedDniScan = (privateData['dniScannedText'] ?? data['dniScannedText'])?.toString() ?? '';
      final loadedCrimScan = (privateData['criminalScannedText'] ?? data['criminalScannedText'])?.toString() ?? '';

      if (mounted) {
        setState(() {
          if (data['name'] != null) _nameCtrl.text = data['name'];
          if (data['bio'] != null) _bioCtrl.text = data['bio'];
          if (data['pricePerHour'] != null) _priceCtrl.text = data['pricePerHour'].toString();
          if (data['homeAddress'] != null) _addressCtrl.text = data['homeAddress'];
          if (data['maxDistanceRadius'] != null) _radius = (data['maxDistanceRadius'] as num).toDouble();
          if (data['latitude'] != null) _homeLat = (data['latitude'] as num).toDouble();
          if (data['longitude'] != null) _homeLon = (data['longitude'] as num).toDouble();
          if (data['imageUrl'] != null && data['imageUrl'] != '') {
            _profileImageUrl = data['imageUrl'];
            _profileImagePath = data['imageUrl']; // show from URL
          }
          if (loadedDni.isNotEmpty) {
            _dniUrl = loadedDni;
            _dniFrontPath = loadedDni;
          }
          if (loadedCriminal.isNotEmpty) {
            _criminalUrl = loadedCriminal;
            _criminalPath = loadedCriminal;
          }
          if (loadedDniScan.isNotEmpty) _dniScannedText = loadedDniScan;
          if (loadedCrimScan.isNotEmpty) _criminalScannedText = loadedCrimScan;
          if (data['stripeAccountId'] != null) _stripeAccountId = data['stripeAccountId'];
          if (data['specialties'] != null) _specialties = List<String>.from(data['specialties']);
          // Restore step progress
          if (data['onboardingStep'] != null) _currentStep = (data['onboardingStep'] as num).toInt().clamp(0, 3);
        });
      }
    } catch (e) {
      debugPrint('Error loading draft: $e');
    }
  }

  bool _pendingSave = false;

  /// Auto-saves current state to Firestore as a draft (debounced & queued via _pendingSave)
  Future<void> _autoSaveDraft() async {
    if (_isSaving) {
      _pendingSave = true;
      return;
    }
    _isSaving = true;
    try {
      do {
        _pendingSave = false;
        await Future.delayed(const Duration(milliseconds: 800)); // debounce
        if (mounted) {
          await _saveDraft();
        }
      } while (_pendingSave && mounted);
    } finally {
      _isSaving = false;
    }
  }

  /// Saves current step data to Firestore immediately
  Future<void> _saveDraft({bool showFeedback = false}) async {
    try {
      if (!mounted) return;
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      if (userId == null) return;

      final parsedPrice = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

      final data = <String, dynamic>{
        'onboardingStep': _currentStep,
        'onboardingComplete': false,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Step 1 fields
      if (_nameCtrl.text.isNotEmpty) data['name'] = _nameCtrl.text.trim();
      if (_bioCtrl.text.isNotEmpty) data['bio'] = _bioCtrl.text.trim();
      if (_profileImageUrl != null) data['imageUrl'] = _profileImageUrl;

      // Step 2 fields
      if (parsedPrice > 0) data['pricePerHour'] = parsedPrice < 6 ? 6.0 : parsedPrice;
      if (_addressCtrl.text.isNotEmpty) data['homeAddress'] = _addressCtrl.text.trim();
      data['maxDistanceRadius'] = _radius;
      if (_homeLat != null) data['latitude'] = _homeLat;
      if (_homeLon != null) data['longitude'] = _homeLon;
      if (_specialties.isNotEmpty) data['specialties'] = _specialties;

      // Step 3 fields (flags públicos + documentos privados en subcolección protegida)
      if (_dniUrl != null) data['hasDniSubmitted'] = _dniUrl!.isNotEmpty;
      if (_criminalUrl != null) data['hasCriminalSubmitted'] = _criminalUrl!.isNotEmpty;

      final cgRef = FirebaseFirestore.instance.collection('caregivers').doc(userId);
      await cgRef.set(data, SetOptions(merge: true));

      final privateData = <String, dynamic>{};
      if (_dniUrl != null) privateData['dniUrl'] = _dniUrl;
      if (_criminalUrl != null) privateData['criminalRecordUrl'] = _criminalUrl;
      if (_dniScannedText.isNotEmpty) privateData['dniScannedText'] = _dniScannedText;
      if (_criminalScannedText.isNotEmpty) privateData['criminalScannedText'] = _criminalScannedText;
      if (privateData.isNotEmpty) {
        privateData['lastUpdated'] = FieldValue.serverTimestamp();
        await cgRef.collection('private').doc('verification').set(privateData, SetOptions(merge: true));
      }

      if (showFeedback && mounted) {
        CustomSnackBar.show(
          context,
          message: 'Borrador guardado automáticamente',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      debugPrint('Auto-save error: $e');
    }
  }

  bool get _supportsMobileOcr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String> _persistFile(String originalPath) async {
    if (kIsWeb || originalPath.isEmpty || originalPath.startsWith('http')) {
      return originalPath;
    }
    final file = File(originalPath);
    if (!await file.exists()) return originalPath;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(originalPath);
    final newPath = p.join(dir.path, 'senicare_tmp_$fileName');

    final newFile = await file.copy(newPath);
    return newFile.path;
  }

  /// Uploads a file (mobile path or web/desktop bytes) to Firebase Storage.
  Future<String?> _uploadFileToStorage(
    String path,
    String folder, {
    Uint8List? bytes,
    String? originalName,
  }) async {
    try {
      if (path.startsWith('http')) return path;

      // Capture auth synchronously before any await
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId ?? 'unknown';

      Uint8List? uploadBytes = bytes;
      if (uploadBytes == null) {
        if (path.isEmpty) return null;
        if (!kIsWeb) {
          final file = File(path);
          if (!await file.exists()) return null;
          uploadBytes = await file.readAsBytes();
        } else {
          uploadBytes = await XFile(path).readAsBytes();
        }
      }

      final nameHint = (originalName != null && originalName.isNotEmpty)
          ? originalName
          : path;
      final ext =
          p.extension(nameHint).isNotEmpty ? p.extension(nameHint).toLowerCase() : '.jpg';
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}$ext';

      SettableMetadata? metadata;
      if (ext == '.pdf') {
        metadata = SettableMetadata(contentType: 'application/pdf');
      } else if (ext == '.png') {
        metadata = SettableMetadata(contentType: 'image/png');
      } else if (ext == '.jpg' || ext == '.jpeg') {
        metadata = SettableMetadata(contentType: 'image/jpeg');
      }

      final ref = FirebaseStorage.instance.ref().child(folder).child(fileName);
      await ref.putData(uploadBytes, metadata);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        CustomSnackBar.show(context, message: 'Error al subir archivo: $e', type: SnackBarType.error);
      }
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final savedPath = await _persistFile(image.path);
      if (!mounted) return;
      setState(() {
        _profileImagePath = savedPath;
        _isLoading = true;
      });

      // Upload immediately
      final url = await _uploadFileToStorage(
        savedPath,
        'caregiver_avatars',
        bytes: bytes,
        originalName: image.name,
      );
      if (url != null) {
        setState(() {
          _profileImageUrl = url;
          if (kIsWeb) _profileImagePath = url;
        });
        await _saveDraft(showFeedback: true);
      }
    } catch (e) {
      if (mounted) CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.info);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanDniLive() async {
    if (kIsWeb) {
      await _pickDniFile();
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveDniScannerScreen()),
    );
    if (result != null && result is Map) {
      setState(() => _isLoading = true);
      try {
        final savedPath = await _persistFile(result['path'].toString());
        setState(() {
          _dniFrontPath = savedPath;
          _dniScannedText = (result['text'] ?? '').toString();
        });

        // Upload immediately
        final url = await _uploadFileToStorage(savedPath, 'caregiver_docs');
        if (url != null) {
          setState(() => _dniUrl = url);
          await _saveDraft(showFeedback: true);
        }
      } catch (e) {
        debugPrint('DNI Scan error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDniFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes;
      final rawPath = kIsWeb ? '' : (picked.path ?? '');
      final savedPath = rawPath.isNotEmpty ? await _persistFile(rawPath) : picked.name;
      final isPdf = p.extension(picked.name).toLowerCase() == '.pdf';

      String extracted = '';
      if (isPdf) {
        extracted = await _extractTextFromPdfBytes(
          bytes ?? (rawPath.isNotEmpty ? await File(rawPath).readAsBytes() : Uint8List(0)),
        );
      } else if (_supportsMobileOcr && savedPath.isNotEmpty) {
        extracted = await _extractTextFromImagePath(savedPath);
      }

      if (!mounted) return;
      setState(() {
        _dniFrontPath = savedPath;
        _dniScannedText = extracted;
      });

      final url = await _uploadFileToStorage(
        savedPath,
        'caregiver_docs',
        bytes: bytes,
        originalName: picked.name,
      );
      if (url != null && mounted) {
        setState(() {
          _dniUrl = url;
          if (kIsWeb || isPdf) _dniFrontPath = url;
        });
        await _saveDraft(showFeedback: true);
      }
    } catch (e) {
      debugPrint('DNI file pick error: $e');
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo cargar el documento de identidad.',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCriminalRecord() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Hacer foto'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (mounted) setState(() => _isLoading = true);
                  try {
                    final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                    if (image == null) return;
                    final bytes = await image.readAsBytes();
                    final savedPath = await _persistFile(image.path);
                    setState(() {
                      _criminalPath = savedPath;
                      _criminalIsPdf = false;
                    });
                    await _extractTextFromImage(savedPath);
                    final url = await _uploadFileToStorage(
                      savedPath,
                      'caregiver_docs',
                      bytes: bytes,
                      originalName: image.name,
                    );
                    if (url != null) {
                      setState(() => _criminalUrl = url);
                      await _saveDraft(showFeedback: true);
                    }
                  } catch (e) {
                    debugPrint('Criminal photo error: $e');
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Subir Archivo PDF'),
              onTap: () async {
                Navigator.pop(ctx);
                if (mounted) setState(() => _isLoading = true);
                try {
                  final result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final picked = result.files.single;
                    final rawPath = kIsWeb ? '' : (picked.path ?? '');
                    final savedPath = rawPath.isNotEmpty ? await _persistFile(rawPath) : picked.name;
                    setState(() {
                      _criminalPath = savedPath;
                      _criminalIsPdf = true;
                    });
                    final bytes = picked.bytes ??
                        (rawPath.isNotEmpty ? await File(rawPath).readAsBytes() : null);
                    if (bytes != null) {
                      final text = await _extractTextFromPdfBytes(bytes);
                      if (mounted) setState(() => _criminalScannedText = text);
                    } else if (savedPath.isNotEmpty) {
                      await _extractTextFromPdf(savedPath);
                    }
                    final url = await _uploadFileToStorage(
                      savedPath,
                      'caregiver_docs',
                      bytes: bytes,
                      originalName: picked.name,
                    );
                    if (url != null) {
                      setState(() {
                        _criminalUrl = url;
                        if (kIsWeb) _criminalPath = url;
                      });
                      await _saveDraft(showFeedback: true);
                    }
                  }
                } catch (e) {
                  debugPrint('PDF pick error: $e');
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Subir Imagen'),
              onTap: () async {
                Navigator.pop(ctx);
                if (mounted) setState(() => _isLoading = true);
                try {
                  final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                  if (image == null) return;
                  final bytes = await image.readAsBytes();
                  final savedPath = await _persistFile(image.path);
                  setState(() {
                    _criminalPath = savedPath;
                    _criminalIsPdf = false;
                  });
                  await _extractTextFromImage(savedPath);
                  final url = await _uploadFileToStorage(
                    savedPath,
                    'caregiver_docs',
                    bytes: bytes,
                    originalName: image.name,
                  );
                  if (url != null) {
                    setState(() {
                      _criminalUrl = url;
                      if (kIsWeb) _criminalPath = url;
                    });
                    await _saveDraft(showFeedback: true);
                  }
                } catch (e) {
                  debugPrint('Criminal image error: $e');
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _extractTextFromPdfBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return '';
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();
      return text;
    } catch (e) {
      debugPrint('PDF bytes extraction error: $e');
      return '';
    }
  }

  Future<void> _extractTextFromPdf(String path) async {
    try {
      if (kIsWeb) return;
      final file = File(path);
      final bytes = await file.readAsBytes();
      final text = await _extractTextFromPdfBytes(bytes);
      if (mounted) setState(() => _criminalScannedText = text);
    } catch (e) {
      debugPrint('PDF extraction error: $e');
    }
  }

  Future<String> _extractTextFromImagePath(String path) async {
    if (!_supportsMobileOcr) return '';
    try {
      final inputImage = InputImage.fromFilePath(path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      return recognizedText.text;
    } catch (e) {
      debugPrint('Image extraction error: $e');
      return '';
    }
  }

  Future<void> _extractTextFromImage(String path) async {
    final text = await _extractTextFromImagePath(path);
    if (mounted && text.isNotEmpty) {
      setState(() => _criminalScannedText = text);
    }
  }

  String _validateIdentity() {
    if (_dniScannedText.isEmpty || _criminalScannedText.isEmpty) return 'pending';

    final nameRaw = _nameCtrl.text.trim().toLowerCase();
    final normalizedName = nameRaw
        .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i')
        .replaceAll('ó', 'o').replaceAll('ú', 'u');
    final nameParts = normalizedName.split(' ').where((p) => p.length > 2).toList();

    final dniTextNorm = _dniScannedText.toLowerCase();
    final crimTextNorm = _criminalScannedText.toLowerCase();

    final RegExp dniRegExp = RegExp(r'\b[0-9]{8}[a-z]\b|\b[xyz][0-9]{7}[a-z]\b');
    final dniMatch = dniRegExp.firstMatch(dniTextNorm);

    if (dniMatch == null) return 'pending';
    final extractedDni = dniMatch.group(0)!;

    bool dniInCriminal = crimTextNorm.contains(extractedDni);
    if (!dniInCriminal) return 'pending';

    int matchDniCount = 0;
    int matchCrimCount = 0;

    for (var part in nameParts) {
      if (dniTextNorm.contains(part)) matchDniCount++;
      if (crimTextNorm.contains(part)) matchCrimCount++;
    }

    if (matchDniCount >= 1 && matchCrimCount >= 1) return 'manual_review';
    return 'pending';
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId!;

      if (_homeLat == null || _homeLon == null) {
        final coords = await NominatimService.geocodeAddress(_addressCtrl.text.trim());
        if (coords != null) {
          _homeLat = coords.latitude;
          _homeLon = coords.longitude;
        }
      }

      final parsedPrice = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 8.0;
      final validationStatus = _validateIdentity();

      final data = {
        'name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'pricePerHour': parsedPrice < 6 ? 6.0 : parsedPrice,
        'homeAddress': _addressCtrl.text.trim(),
        'maxDistanceRadius': _radius,
        'imageUrl': _profileImageUrl ?? '',
        'hasDniSubmitted': (_dniUrl ?? '').isNotEmpty,
        'hasCriminalSubmitted': (_criminalUrl ?? '').isNotEmpty,
        'verificationStatus': validationStatus,
        'onboardingComplete': true,
        'onboardingStep': 3,
        'specialties': _specialties,
        if (_homeLat != null) 'latitude': _homeLat,
        if (_homeLon != null) 'longitude': _homeLon,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      final cgRef = FirebaseFirestore.instance.collection('caregivers').doc(userId);
      await cgRef.set(data, SetOptions(merge: true));
      await cgRef.collection('private').doc('verification').set({
        'dniUrl': _dniUrl ?? '',
        'criminalRecordUrl': _criminalUrl ?? '',
        'dniScannedText': _dniScannedText,
        'criminalScannedText': _criminalScannedText,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        if (validationStatus == 'manual_review') {
          CustomSnackBar.show(context, message: 'Documentación prevalidada. Pendiente de aprobación final del equipo SeniCare.', type: SnackBarType.success);
        } else {
          CustomSnackBar.show(context, message: 'Registro completado. Identidad pendiente de validación manual.', type: SnackBarType.info);
        }
        auth.onboardingComplete = true;
        // Reload auth state to re-route the user to caregiver dashboard
        await auth.reloadRole();
      }
    } catch (e) {
      if (mounted) CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.info);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _launchStripe() async {
    setState(() => _isLoading = true);
    try {
      final accountId = await StripeService.createConnectAccount();
      if (accountId != null) {
        setState(() => _stripeAccountId = accountId);
        // Save Stripe account ID immediately
        await _saveDraft(showFeedback: true);
        await StripeService.launchOnboarding(accountId);
        if (mounted) {
          CustomSnackBar.show(context, message: 'Sigue los pasos en el navegador para conectar Stripe.', type: SnackBarType.success);
        }
      } else {
        if (mounted) {
          CustomSnackBar.show(context, message: 'No se pudo crear la cuenta de Stripe.', type: SnackBarType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context, message: 'Error Stripe: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSaveIndicator() {
    return _isSaving
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                SizedBox(width: 6),
                Text('Guardando...', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )
        : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Cuidador'),
        actions: [
          TextButton.icon(
            onPressed: () => _saveDraft(showFeedback: true),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar'),
          ),
          TextButton(
            onPressed: () async {
              await _saveDraft();
              if (!context.mounted) return;
              CustomSnackBar.show(
                context,
                message: 'Borrador guardado. Podrás continuar tu registro la próxima vez que entres.',
                type: SnackBarType.info,
              );
              await DependencyInjection.auth.signOut();
            },
            child: const Text('Guardar y salir'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stepper(
              type: StepperType.vertical,
              currentStep: _currentStep,
              onStepContinue: () async {
                if (_currentStep < 3) {
                  // Save progress before advancing
                  await _saveDraft(showFeedback: true);
                  setState(() => _currentStep += 1);
                } else {
                  _submit();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep -= 1);
                }
              },
              steps: [
                // ── STEP 1: Datos personales ──────────────────────────────────
                Step(
                  title: const Text('Datos Personales'),
                  isActive: _currentStep >= 0,
                  state: _nameCtrl.text.isNotEmpty ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSaveIndicator(),
                      Center(
                        child: GestureDetector(
                          onTap: _pickProfileImage,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: _profileImagePath != null
                                    ? (_profileImagePath!.startsWith('http')
                                        ? CachedNetworkImageProvider(_profileImagePath!) as ImageProvider
                                        : (!kIsWeb ? FileImage(File(_profileImagePath!)) as ImageProvider : null))
                                    : null,
                                child: _profileImagePath == null ||
                                        (kIsWeb && !_profileImagePath!.startsWith('http'))
                                    ? const Icon(Icons.camera_alt, size: 40)
                                    : null,
                              ),
                              if (_profileImagePath != null)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: _profileImageUrl != null ? Colors.green : Colors.orange,
                                    child: Icon(
                                      _profileImageUrl != null ? Icons.cloud_done : Icons.cloud_upload,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          _profileImageUrl != null ? 'Foto guardada ✓' : 'Toca para añadir foto de perfil',
                          style: TextStyle(
                            fontSize: 12,
                            color: _profileImageUrl != null ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Biografía Corta',
                          hintText: 'Cuéntanos sobre tu experiencia como cuidador...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── STEP 2: Operaciones ───────────────────────────────────────
                Step(
                  title: const Text('Operaciones'),
                  isActive: _currentStep >= 1,
                  state: _priceCtrl.text.isNotEmpty && _addressCtrl.text.isNotEmpty
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSaveIndicator(),
                      TextFormField(
                        controller: _priceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tarifa Hora (€) *',
                          helperText: 'Mínimo 6€/h',
                          prefixText: '€ ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AddressFormWidget(
                        initialAddress: _addressCtrl.text,
                        onAddressChanged: (addr) {
                          _addressCtrl.text = addr;
                          _homeLat = null;
                          _homeLon = null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Radio máximo de desplazamiento:'),
                          Text('${_radius.round()} km', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: _radius,
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: '${_radius.round()} km',
                        onChanged: (val) => setState(() => _radius = val),
                        onChangeEnd: (_) => _saveDraft(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Especialidades:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allSpecialties.map((spec) {
                          final selected = _specialties.contains(spec);
                          return FilterChip(
                            label: Text(spec),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _specialties.add(spec);
                                } else {
                                  _specialties.remove(spec);
                                }
                              });
                              _saveDraft();
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                // ── STEP 3: Documentación ─────────────────────────────────────
                Step(
                  title: const Text('Documentación de Identidad'),
                  isActive: _currentStep >= 2,
                  state: (_dniUrl != null && _criminalUrl != null) ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: AppTheme.softTealGradient,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '¡Fácil, rápido y 100% gratuito!',
                                    style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkSlate, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'No te preocupes si no sabes cómo sacar el Certificado de Penales: se descarga gratis en 2 minutos desde el móvil. Tu progreso queda guardado automáticamente.',
                              style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, height: 1.4),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
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
                                              const Icon(Icons.verified_user, color: AppTheme.primary, size: 26),
                                              const SizedBox(width: 10),
                                              const Expanded(
                                                child: Text(
                                                  'Cómo conseguir y subir tus documentos en 2 minutos',
                                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Text('1. DNI o NIE (Parte delantera):', style: TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          const Text('• Pulsa "Escanear DNI/NIE (Cámara)" y haz una foto clara a tu documento.'),
                                          const SizedBox(height: 12),
                                          const Text('2. Certificado de Penales / Delitos Sexuales (Gratis):', style: TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          const Text(
                                            '• Entra en sede.mjusticia.gob.es desde tu navegador.\n'
                                            '• Identifícate con Cl@ve PIN o Certificado Digital.\n'
                                            '• Descarga el PDF oficial gratuito al instante y súbelo pulsando en "Subir Certificado de Penales".',
                                          ),
                                          const SizedBox(height: 16),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Entendido, volver al registro'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.menu_book_rounded, size: 18),
                              label: const Text('Ver guía paso a paso (2 min)'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // DNI Section
                      const Text('1. Documento de Identidad (DNI/NIE)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!kIsWeb)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade100,
                                foregroundColor: Colors.blue.shade900,
                              ),
                              onPressed: _scanDniLive,
                              icon: const Icon(Icons.document_scanner),
                              label: const Text('Escanear DNI/NIE (Cámara)'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _pickDniFile,
                            icon: const Icon(Icons.upload_file),
                            label: Text(kIsWeb ? 'Subir DNI/NIE (Imagen o PDF)' : 'Subir archivo o galería'),
                          ),
                        ],
                      ),
                      if (_dniFrontPath != null) ...[
                        const SizedBox(height: 8),
                        if (_dniFrontPath!.toLowerCase().contains('.pdf'))
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                            title: Text('Documento PDF seleccionado'),
                          )
                        else if (_dniFrontPath!.startsWith('http'))
                          CachedNetworkImage(imageUrl: _dniFrontPath!, height: 100)
                        else if (!kIsWeb)
                          Image.file(File(_dniFrontPath!), height: 100),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              _dniUrl != null ? Icons.cloud_done : Icons.cloud_upload,
                              size: 14,
                              color: _dniUrl != null ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _dniUrl != null ? 'DNI guardado en la nube ✓' : 'Subiendo...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _dniUrl != null ? Colors.green : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_dniScannedText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              _dniScannedText.length > 60
                                  ? '${_dniScannedText.substring(0, 60)}...'
                                  : _dniScannedText,
                              style: const TextStyle(fontSize: 11, color: Colors.green),
                            ),
                          ),
                      ],

                      const Divider(height: 32),

                      // Criminal Record Section
                      const Text('2. Certificado de Antecedentes Penales', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _pickCriminalRecord,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Subir Certificado de Penales (PDF o Foto)'),
                      ),
                      if (_criminalPath != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _criminalUrl != null ? Icons.cloud_done : Icons.cloud_upload,
                              size: 14,
                              color: _criminalUrl != null ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _criminalUrl != null
                                    ? 'Certificado guardado en la nube ✓ (${_criminalIsPdf ? "PDF" : "Imagen"})'
                                    : 'Subiendo...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _criminalUrl != null ? Colors.green : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_dniUrl != null && _criminalUrl != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user, color: Colors.green, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Todos los documentos subidos. La verificación de identidad se procesará automáticamente.',
                                  style: TextStyle(fontSize: 12, color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── STEP 4: Stripe ────────────────────────────────────────────
                Step(
                  title: const Text('Cuenta Bancaria (Stripe)'),
                  isActive: _currentStep >= 3,
                  state: _stripeAccountId != null ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Para recibir el ingreso directo de cada guardia en tu banco (IBAN), vincula tu cuenta con Stripe Connect. Podrás cambiar de cuenta bancaria cuando quieras.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _stripeAccountId != null ? Colors.green : Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _stripeAccountId != null
                              ? () => StripeService.openBankAccountManagement(_stripeAccountId!)
                              : _launchStripe,
                          child: Text(_stripeAccountId != null
                              ? '✓ Stripe Conectado (Toca para cambiar IBAN)'
                              : 'Conectar Cuenta Bancaria con Stripe'),
                        ),
                      ),
                      if (_stripeAccountId != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Tu cuenta bancaria está conectada correctamente. Pulsa "Continuar" para finalizar el registro.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

