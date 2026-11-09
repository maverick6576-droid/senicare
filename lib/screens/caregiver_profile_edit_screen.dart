import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/address_form_widget.dart';
import 'package:senicare/screens/screens.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'onboarding/live_dni_scanner_screen.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CaregiverProfileEditScreen extends StatefulWidget {
  const CaregiverProfileEditScreen({super.key});

  @override
  State<CaregiverProfileEditScreen> createState() => _CaregiverProfileEditScreenState();
}

class _CaregiverProfileEditScreenState extends State<CaregiverProfileEditScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isEditing = false;
  bool _isSaving = false;
  CaregiverProfile? _profile;
  
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  // Document verification variables
  String? _dniFrontPath;
  String? _criminalPath;
  String _dniScannedText = '';
  String _criminalScannedText = '';
  bool _criminalIsPdf = false;
  String? _dniFrontUrl;
  String? _criminalUrl;
  final _homeAddressCtrl = TextEditingController();
  double? _homeLat;
  double? _homeLon;
  double _maxDistanceRadius = 10.0;
  List<String> _selectedSpecialties = [];
  String? _newImageUrl;
  
  final List<String> _allSpecialties = [
    'Movilidad', 'Cocina Médica', 'Compañía', 'Soporte Digital', 'Demencia', 'Post-operatorio'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final auth = context.read<AuthNotifier>();
    try {
      final myProfile = await DependencyInjection.caregivers.getCaregiver(auth.currentUserId!);
      if (myProfile != null) {
        setState(() {
          _profile = myProfile;
          _nameCtrl.text = myProfile.name;
          _bioCtrl.text = myProfile.bio;
          _priceCtrl.text = myProfile.pricePerHour.toString();
          _homeAddressCtrl.text = myProfile.homeAddress;
          _homeLat = myProfile.latitude;
          _homeLon = myProfile.longitude;
          _maxDistanceRadius = myProfile.maxDistanceRadius;
          _selectedSpecialties = List.from(myProfile.specialties);
          _newImageUrl = myProfile.imageUrl;
          _dniFrontUrl = myProfile.dniUrl;
          _criminalUrl = myProfile.criminalRecordUrl;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (_profile == null) return;
    
    final parsedPrice = double.tryParse(_priceCtrl.text) ?? _profile!.pricePerHour;
    if (parsedPrice < 6) {
      CustomSnackBar.show(context, message: 'Por política de SeniCare, la tarifa mínima es de 6€/hora.', type: SnackBarType.error);
      return;
    }
    if (_homeLat == null || _homeLon == null) {
      final coords = await NominatimService.geocodeAddress(_homeAddressCtrl.text.trim());
      if (coords != null) {
        _homeLat = coords.latitude;
        _homeLon = coords.longitude;
      } else {
        CustomSnackBar.show(context, message: 'Por favor, selecciona una dirección válida de la lista.', type: SnackBarType.error);
        return;
      }
    }

    setState(() => _isSaving = true);

    String dniUrl = _dniFrontUrl ?? '';
    String criminalUrl = _criminalUrl ?? '';

    try {
      if (_newImageUrl != null && !_newImageUrl!.startsWith('http') && _newImageUrl!.isNotEmpty) {
        final ref = FirebaseStorage.instance.ref().child('caregiver_avatars').child('${_profile!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(File(_newImageUrl!));
        _newImageUrl = await ref.getDownloadURL();
      }
      
      if (_dniFrontPath != null) {
        dniUrl = await _uploadFile(_dniFrontPath!, 'caregiver_docs') ?? '';
      }
      if (_criminalPath != null) {
        criminalUrl = await _uploadFile(_criminalPath!, 'caregiver_docs') ?? '';
      }
    } catch (e) {
      debugPrint('Error uploading files: $e');
      if (context.mounted) {
        CustomSnackBar.show(context, message: 'Error al subir los archivos: $e', type: SnackBarType.error);
        setState(() => _isSaving = false);
      }
      return;
    }

    // Calcular el estado de verificación
    String newStatus = _profile!.verificationStatus;
    if (_dniFrontPath != null || _criminalPath != null) {
      newStatus = _validateIdentity();
    }

    final hasName = _nameCtrl.text.trim().isNotEmpty && _nameCtrl.text.trim() != 'Sin nombre';
    final hasBio = _bioCtrl.text.trim().isNotEmpty && !_bioCtrl.text.trim().startsWith('Nuevo cuidador');
    final hasAddress = _homeAddressCtrl.text.trim().isNotEmpty;
    final hasImage = (_newImageUrl != null && _newImageUrl!.isNotEmpty) || _profile!.imageUrl.isNotEmpty;
    final hasDni = dniUrl.isNotEmpty;
    final hasCriminal = criminalUrl.isNotEmpty;
    final hasStripe = _profile!.stripeAccountId != null && _profile!.stripeAccountId!.isNotEmpty;

    final onboardingComplete = hasName && hasBio && hasAddress && hasImage && hasDni && hasCriminal && hasStripe;

    final updatedData = {
      'name': _nameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'pricePerHour': parsedPrice,
      'homeAddress': _homeAddressCtrl.text.trim(),
      'latitude': _homeLat,
      'longitude': _homeLon,
      'maxDistanceRadius': _maxDistanceRadius,
      'specialties': _selectedSpecialties,
      if (_newImageUrl != null) 'imageUrl': _newImageUrl,
      'dniUrl': dniUrl,
      'criminalRecordUrl': criminalUrl,
      'verificationStatus': newStatus,
      'onboardingComplete': onboardingComplete,
    };

    await DependencyInjection.caregivers.updateProfile(_profile!.id, updatedData);
    
    // Forzar recarga del estado de autenticación
    final authNotifier = context.read<AuthNotifier>();
    await authNotifier.reloadRole();
    
    if (mounted) {
      CustomSnackBar.show(context, message: useFirebaseBackend ? 'Perfil actualizado correctamente' : 'Perfil simulado actualizado correctamente', type: SnackBarType.success);
      setState(() {
        _isEditing = false;
        _dniFrontPath = null;
        _criminalPath = null;
      });
      _loadProfile();
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
                  const Icon(Icons.verified_user, color: AppTheme.primary, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Guía rápida: Sube tus documentos en 2 minutos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                '• Pulsa en "Escanear DNI/NIE (Cámara)" y enfoca la parte delantera de tu documento con buena luz.\n'
                '• Nuestro lector inteligente detectará automáticamente tu número de documento.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '2. Certificado de Antecedentes Penales / Delitos Sexuales (100% Gratis):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Entra en la Sede Electrónica del Ministerio de Justicia (sede.mjusticia.gob.es).\n'
                '• Accede con Cl@ve PIN, Cl@ve Permanente o Certificado Digital.\n'
                '• Descarga el PDF oficial al instante (es gratuito para trabajar con personas vulnerables y mayores).\n'
                '• Pulsa en "Subir Certificado de Penales" en esta pantalla y selecciona el PDF descargado o una foto nítida.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '3. Cuenta Bancaria (Stripe Connect):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Conecta tu IBAN español en Stripe para recibir el pago de tus guardias automáticamente tras finalizar cada servicio. Puedes cambiar tu IBAN cuando quieras desde este perfil.',
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

  Future<String> _persistFile(String originalPath) async {
    final file = File(originalPath);
    if (!await file.exists()) return originalPath;
    
    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(originalPath);
    final newPath = p.join(dir.path, 'senicare_tmp_$fileName');
    
    final newFile = await file.copy(newPath);
    return newFile.path;
  }

  Future<void> _pickImage(Function(String) onPicked, {bool readText = false}) async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image != null) {
        final savedPath = await _persistFile(image.path);
        onPicked(savedPath);
        if (readText) {
          _readDNI(savedPath);
        }
      }
    } catch (e) {
      if (mounted) CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.info);
    }
  }

  Future<void> _readDNI(String path) async {
    setState(() => _isSaving = true);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      setState(() {
        _dniScannedText = 'Datos detectados (OCR):\n';
        for (TextBlock block in recognizedText.blocks) {
          if (block.text.contains(RegExp(r'[0-9]{8}[A-Z]'))) {
             _dniScannedText += 'DNI/NIE: ${block.text}\n';
          } else if (block.text.length > 5) {
             _dniScannedText += '${block.text}\n';
          }
        }
      });
      textRecognizer.close();
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _scanDniLive() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveDniScannerScreen()),
    );
    if (result != null && result is Map) {
      final savedPath = await _persistFile(result['path']);
      setState(() {
        _dniFrontPath = savedPath;
        _dniScannedText = result['text'] ?? '';
      });
    }
  }

  Future<void> _pickCriminalRecord() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Hacer foto'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage((path) async {
                  setState(() {
                    _criminalPath = path;
                    _criminalIsPdf = false;
                    _isSaving = true;
                  });
                  await _extractTextFromImage(path);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Subir Archivo PDF'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  FilePickerResult? result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                  );
                  if (result != null && result.files.single.path != null) {
                    final savedPath = await _persistFile(result.files.single.path!);
                    setState(() {
                      _criminalPath = savedPath;
                      _criminalIsPdf = true;
                      _isSaving = true;
                    });
                    await _extractTextFromPdf(savedPath);
                  }
                } catch (e) {
                  print(e);
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
      final file = File(path);
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();
      setState(() => _criminalScannedText = text);
    } catch (e) {
      print('PDF extraction error: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _extractTextFromImage(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      setState(() => _criminalScannedText = recognizedText.text);
      textRecognizer.close();
    } catch (e) {
      print('Image extraction error: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<String?> _uploadFile(String path, String folder) async {
    if (path.startsWith('http')) return path;
    
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('El archivo local seleccionado no existe.');
    }
    
    final userId = _profile!.id;
    final ext = p.extension(path).isNotEmpty ? p.extension(path).toLowerCase() : '.jpg';
    final ref = FirebaseStorage.instance.ref().child(folder).child('${userId}_${DateTime.now().millisecondsSinceEpoch}$ext');
    
    SettableMetadata? metadata;
    if (ext == '.pdf') {
      metadata = SettableMetadata(contentType: 'application/pdf');
    } else if (ext == '.png') {
      metadata = SettableMetadata(contentType: 'image/png');
    } else if (ext == '.jpg' || ext == '.jpeg') {
      metadata = SettableMetadata(contentType: 'image/jpeg');
    }

    await ref.putFile(file, metadata);
    return await ref.getDownloadURL();
  }

  String _validateIdentity() {
    if (_dniScannedText.isEmpty || _criminalScannedText.isEmpty) {
      return 'pending';
    }

    final nameRaw = _nameCtrl.text.trim().toLowerCase();
    final normalizedName = nameRaw.replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u');
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

    if (matchDniCount >= 1 && matchCrimCount >= 1) {
      return 'approved';
    }

    return 'pending';
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) return const Center(child: CircularProgressIndicator());
    
    final config = context.watch<ConfigNotifier>();
    final isSenior = config.seniorMode;
    final fontMult = isSenior ? 1.3 : 1.0;

    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('Mi Perfil de Cuidador'),
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: _isSaving
            ? null
            : () {
                if (_isEditing) {
                  _saveProfile();
                } else {
                  setState(() => _isEditing = true);
                }
              },
        icon: _isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Icon(_isEditing ? Icons.save : Icons.edit, color: Colors.white),
        label: Text(_isSaving ? 'Guardando...' : (_isEditing ? 'Guardar' : 'Editar Perfil')),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
                height: 170,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Container(height: 120, width: double.infinity, color: AppTheme.primary),
                    Positioned(
                      top: 70,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 46,
                              backgroundImage: _newImageUrl != null && !_newImageUrl!.startsWith('http')
                                  ? FileImage(File(_newImageUrl!)) as ImageProvider
                                  : CachedNetworkImageProvider(_newImageUrl ?? _profile!.imageUrl),
                            ),
                          ),
                          if (_isEditing)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: InkWell(
                                onTap: () async {
                                  try {
                                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                                    if (image != null) {
                                      setState(() {
                                        _newImageUrl = image.path;
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      CustomSnackBar.show(context, message: 'Error al acceder a la galería: $e', type: SnackBarType.error);
                                    }
                                  }
                                },
                                child: const CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.white,
                                  child: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppTheme.primary,
                                    child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
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
              const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _profile!.verified ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _profile!.verified ? Colors.blue.shade200 : Colors.orange.shade200)
              ),
              child: Row(
                children: [
                  Icon(
                    _profile!.verified ? Icons.verified : Icons.pending_actions,
                    color: _profile!.verified ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _profile!.verified 
                        ? "Perfil Verificado por SeniCare" 
                        : "Tu documentación está siendo auditada por nuestro equipo. Tu perfil será visible para los clientes en cuanto se verifique.",
                      style: TextStyle(
                        fontSize: 14 * fontMult,
                        color: _profile!.verified ? Colors.blue.shade800 : Colors.orange.shade900,
                        fontWeight: FontWeight.w500
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isEditing) ...[
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre completo', border: OutlineInputBorder()),
                      style: TextStyle(fontSize: 16 * fontMult),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bioCtrl,
                      decoration: const InputDecoration(labelText: 'Acerca de mí', border: OutlineInputBorder()),
                      maxLines: 4,
                      style: TextStyle(fontSize: 14 * fontMult),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tarifa por hora (€)', border: OutlineInputBorder()),
                      style: TextStyle(fontSize: 16 * fontMult),
                    ),
                    const SizedBox(height: 16),
                    AddressFormWidget(
                        initialAddress: _homeAddressCtrl.text,
                        onAddressChanged: (addr) {
                          _homeAddressCtrl.text = addr;
                          _homeLat = null;
                          _homeLon = null;
                        },
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Me desplazo hasta: ${_maxDistanceRadius.toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 16 * fontMult, fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: _maxDistanceRadius,
                      min: 1.0,
                      max: 50.0,
                      divisions: 49,
                      label: '${_maxDistanceRadius.toStringAsFixed(1)} km',
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() => _maxDistanceRadius = val);
                      },
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Documentación de Identidad', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: _showDocumentsGuideModal,
                          icon: const Icon(Icons.help_outline, size: 18),
                          label: const Text('Guía fácil'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue.shade900),
                      onPressed: (_profile!.verified || _profile!.verificationStatus == 'approved') ? null : _scanDniLive,
                      icon: const Icon(Icons.document_scanner),
                      label: const Text('Escanear DNI/NIE (Cámara)'),
                    ),
                    if (_dniFrontPath != null) ...[
                      const SizedBox(height: 8),
                      Image.file(File(_dniFrontPath!), height: 80),
                      if (_dniScannedText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(_dniScannedText, style: const TextStyle(fontSize: 12, color: Colors.green)),
                        )
                    ] else if (_dniFrontUrl != null && _dniFrontUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('DNI/NIE ya subido ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      )
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue.shade900),
                      onPressed: (_profile!.verified || _profile!.verificationStatus == 'approved') ? null : _pickCriminalRecord,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Subir Certificado de Penales'),
                    ),
                    if (_criminalPath != null) ...[
                      const SizedBox(height: 8),
                      Text('Penales seleccionado: ${_criminalIsPdf ? "PDF" : "Imagen"}', style: const TextStyle(color: Colors.green)),
                    ] else if (_criminalUrl != null && _criminalUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Certificado de Penales ya subido ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      )
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text('Cuenta de Cobros (Stripe)', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _profile!.stripeAccountId != null ? Colors.green.shade600 : Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          if (_profile!.stripeAccountId != null) {
                            CustomSnackBar.show(context, message: 'Abriendo panel bancario de Stripe...', type: SnackBarType.info);
                            await StripeService.openBankAccountManagement(_profile!.stripeAccountId!);
                            return;
                          }
                          CustomSnackBar.show(context, message: 'Creando cuenta conectada de Stripe...', type: SnackBarType.info);
                          final accountId = await StripeService.createConnectAccount();
                          if (accountId != null) {
                            await StripeService.launchOnboarding(accountId);
                            setState(() {
                              _profile = CaregiverProfile(
                                id: _profile!.id,
                                name: _profile!.name,
                                title: _profile!.title,
                                bio: _profile!.bio,
                                pricePerHour: _profile!.pricePerHour,
                                rating: _profile!.rating,
                                reviewsCount: _profile!.reviewsCount,
                                distance: _profile!.distance,
                                imageUrl: _profile!.imageUrl,
                                specialties: _profile!.specialties,
                                verified: _profile!.verified,
                                availableSlots: _profile!.availableSlots,
                                maxDistanceRadius: _profile!.maxDistanceRadius,
                                homeAddress: _profile!.homeAddress,
                                verificationStatus: _profile!.verificationStatus,
                                stripeAccountId: accountId,
                                onboardingComplete: _profile!.onboardingComplete,
                                isKycVerified: _profile!.isKycVerified,
                              );
                            });
                          }
                        } catch (e) {
                          CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.info);
                        }
                      },
                      child: Text(_profile!.stripeAccountId != null ? 'Cambiar cuenta bancaria (IBAN) / Panel Stripe' : 'Conectar con Stripe Connect'),
                    ),
                  ] else ...[
                    Text(_profile!.name, style: TextStyle(fontSize: 24 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_profile!.pricePerHour}€ / hora', style: TextStyle(fontSize: 18 * fontMult, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Text('Acerca de mí', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_profile!.bio, style: TextStyle(fontSize: 16 * fontMult, color: Colors.grey.shade700)),
                    const SizedBox(height: 16),
                    Text('Dirección de residencia', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_profile!.homeAddress.isEmpty ? 'No especificada' : _profile!.homeAddress, style: TextStyle(fontSize: 16 * fontMult, color: Colors.grey.shade700)),
                    const SizedBox(height: 16),
                    Text('Me desplazo hasta', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_profile!.maxDistanceRadius.toStringAsFixed(1)} km', style: TextStyle(fontSize: 16 * fontMult, color: Colors.grey.shade700)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Documentos', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: _showDocumentsGuideModal,
                          icon: const Icon(Icons.help_outline, size: 18),
                          label: const Text('¿Cómo conseguirlos?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _profile!.dniUrl.isNotEmpty ? Icons.check_circle : Icons.cancel,
                          color: _profile!.dniUrl.isNotEmpty ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Documento de Identidad (DNI/NIE)', style: TextStyle(fontSize: 16 * fontMult)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _profile!.criminalRecordUrl.isNotEmpty ? Icons.check_circle : Icons.cancel,
                          color: _profile!.criminalRecordUrl.isNotEmpty ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Certificado de Antecedentes Penales', style: TextStyle(fontSize: 16 * fontMult)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Cuenta de Cobros', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _profile!.stripeAccountId != null ? Icons.check_circle : Icons.cancel,
                          color: _profile!.stripeAccountId != null ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_profile!.stripeAccountId != null ? 'Stripe Conectado ✓' : 'Stripe No Conectado', style: TextStyle(fontSize: 16 * fontMult)),
                        ),
                      ],
                    ),
                    if (_profile!.stripeAccountId != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            CustomSnackBar.show(context, message: 'Abriendo panel bancario de Stripe...', type: SnackBarType.info);
                            await StripeService.openBankAccountManagement(_profile!.stripeAccountId!);
                          } catch (e) {
                            CustomSnackBar.show(context, message: 'Error abriendo Stripe: $e', type: SnackBarType.error);
                          }
                        },
                        icon: const Icon(Icons.account_balance_outlined, size: 18),
                        label: const Text('Cambiar cuenta bancaria (IBAN) / Panel Stripe'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Text('Especialidades', style: TextStyle(fontSize: 18 * fontMult, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allSpecialties.map((spec) {
                      final isSelected = _selectedSpecialties.contains(spec);
                      return FilterChip(
                        label: Text(spec, style: TextStyle(fontSize: 14 * fontMult)),
                        selected: isSelected,
                        onSelected: _isEditing ? (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedSpecialties.add(spec);
                            } else {
                              _selectedSpecialties.remove(spec);
                            }
                          });
                        } : null,
                        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                        checkmarkColor: AppTheme.primary,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Gestionar Mi Calendario'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CaregiverCalendarScreen()));
                      },
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}



