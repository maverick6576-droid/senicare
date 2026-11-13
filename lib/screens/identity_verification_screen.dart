import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  bool _isLoading = false;
  String _dniStatus = '';
  String _criminalRecordStatus = '';

  Future<String?> _uploadDocToStorage({
    required String caregiverId,
    required PlatformFile pickedFile,
    required String prefix,
  }) async {
    if (!useFirebaseBackend) return 'mock://uploaded/$prefix';
    final ext = (pickedFile.extension ?? 'jpg').toLowerCase();
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final fileName = '${caregiverId}_${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref().child('caregiver_docs').child(fileName);
    final meta = SettableMetadata(contentType: contentType);

    if (pickedFile.bytes != null) {
      await ref.putData(pickedFile.bytes!, meta);
    } else if (!kIsWeb && pickedFile.path != null) {
      await ref.putFile(File(pickedFile.path!), meta);
    } else {
      return null;
    }
    return ref.getDownloadURL();
  }

  Future<void> _verifyDocument(bool isDni) async {
    final auth = Provider.of<AuthNotifier>(context, listen: false);
    final user = auth.currentCaregiver;
    if (user == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.path == null && picked.bytes == null) return;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      if (isDni) {
        _dniStatus = 'Analizando y subiendo documento de identidad...';
      } else {
        _criminalRecordStatus = 'Analizando y subiendo certificado...';
      }
    });

    try {
      final validation = picked.path != null
          ? (isDni
              ? await MLKitService.validateDNI(picked.path!, user.name)
              : await MLKitService.validateCriminalRecord(picked.path!, user.name))
          : ValidationResult(
              isApproved: false,
              isManualReview: true,
              message: 'Documento subido desde web para revisión manual.',
            );

      String? uploadedUrl;
      if (validation.isApproved || validation.isManualReview) {
        uploadedUrl = await _uploadDocToStorage(
          caregiverId: user.id,
          pickedFile: picked,
          prefix: isDni ? 'dni' : 'penales',
        );
        await _persistVerificationSubmission(
          user,
          newStatus: 'manual_review',
          dniUrl: isDni ? uploadedUrl : null,
          criminalRecordUrl: isDni ? null : uploadedUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        if (isDni) {
          _dniStatus = validation.message;
        } else {
          _criminalRecordStatus = validation.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: 'No se pudo subir el documento: $e',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _persistVerificationSubmission(
    CaregiverProfile profile, {
    required String newStatus,
    String? dniUrl,
    String? criminalRecordUrl,
  }) async {
    final caregiverState = Provider.of<CaregiverNotifier>(context, listen: false);
    final nextDni = (dniUrl != null && dniUrl.isNotEmpty) ? dniUrl : profile.dniUrl;
    final nextCriminal = (criminalRecordUrl != null && criminalRecordUrl.isNotEmpty)
        ? criminalRecordUrl
        : profile.criminalRecordUrl;

    if (useFirebaseBackend) {
      final cgRef = FirebaseFirestore.instance.collection('caregivers').doc(profile.id);
      await cgRef.set({
        'verificationStatus': newStatus,
        'hasDniSubmitted': nextDni.isNotEmpty,
        'hasCriminalSubmitted': nextCriminal.isNotEmpty,
      }, SetOptions(merge: true));

      final privateData = <String, dynamic>{
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (dniUrl != null && dniUrl.isNotEmpty) privateData['dniUrl'] = dniUrl;
      if (criminalRecordUrl != null && criminalRecordUrl.isNotEmpty) {
        privateData['criminalRecordUrl'] = criminalRecordUrl;
      }
      await cgRef.collection('private').doc('verification').set(
            privateData,
            SetOptions(merge: true),
          );
    }

    final updatedProfile = CaregiverProfile(
      id: profile.id,
      name: profile.name,
      title: profile.title,
      bio: profile.bio,
      pricePerHour: profile.pricePerHour,
      rating: profile.rating,
      reviewsCount: profile.reviewsCount,
      distance: profile.distance,
      latitude: profile.latitude,
      longitude: profile.longitude,
      imageUrl: profile.imageUrl,
      voiceIntroUrl: profile.voiceIntroUrl,
      specialties: profile.specialties,
      verified: profile.verified,
      availableSlots: profile.availableSlots,
      dniUrl: nextDni,
      criminalRecordUrl: nextCriminal,
      maxDistanceRadius: profile.maxDistanceRadius,
      homeAddress: profile.homeAddress,
      verificationStatus: newStatus,
      stripeAccountId: profile.stripeAccountId,
      onboardingComplete: profile.onboardingComplete,
      isKycVerified: profile.isKycVerified,
      hasSeenCaregiverTutorial: profile.hasSeenCaregiverTutorial,
      noShowsCount: profile.noShowsCount,
      incidentDates: profile.incidentDates,
      blockedUntil: profile.blockedUntil,
      accountStatus: profile.accountStatus,
    );
    caregiverState.updateCaregiverProfileLocal(updatedProfile);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthNotifier>(context);
    final user = auth.currentCaregiver;

    if (user == null) {
      return Scaffold(appBar: AppBar(title: const Text('Verificación')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación de Identidad'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusBanner(user.verificationStatus),
                  const SizedBox(height: 24),
                  const Text(
                    'Paso 1: Documento de Identidad',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Sube una foto o PDF de tu DNI, NIE, TIE o Pasaporte. Se enviará de forma cifrada a verificación.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _verifyDocument(true),
                    icon: const Icon(Icons.upload_file),
                    label: Text(user.hasDni ? 'Actualizar DNI/NIE/Pasaporte ✓' : 'Subir DNI/NIE/Pasaporte'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.indigo,
                    ),
                  ),
                  if (_dniStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dniStatus,
                      style: TextStyle(
                        color: _dniStatus.contains('válido')
                            ? Colors.green
                            : (_dniStatus.contains('manual') ? Colors.orange.shade800 : Colors.red),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Paso 2: Certificado de Penales / Delitos Sexuales',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Sube el PDF o imagen expedido por el Ministerio de Justicia (sin antecedentes).'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _verifyDocument(false),
                    icon: const Icon(Icons.upload_file),
                    label: Text(user.hasCriminalRecord ? 'Actualizar Certificado ✓' : 'Subir Certificado Penales'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.indigo,
                    ),
                  ),
                  if (_criminalRecordStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _criminalRecordStatus,
                      style: TextStyle(
                        color: _criminalRecordStatus.contains('válido')
                            ? Colors.green
                            : (_criminalRecordStatus.contains('manual') ? Colors.orange.shade800 : Colors.red),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(String status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'approved':
      case 'verified':
        color = Colors.green;
        text = '¡Perfil Verificado! Ya eres visible para las familias.';
        icon = Icons.verified;
        break;
      case 'manual_review':
      case 'pending':
        color = Colors.orange;
        text = 'Documentación en revisión por el equipo de SeniCare.';
        icon = Icons.pending_actions;
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Documentación rechazada. Vuelve a subir archivos claros y vigentes.';
        icon = Icons.cancel_outlined;
        break;
      case 'unverified':
      default:
        color = Colors.red;
        text = 'Perfil NO verificado. Por favor completa los pasos.';
        icon = Icons.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
