import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  bool _isLoading = false;
  String _dniStatus = '';
  String _criminalRecordStatus = '';

  Future<void> _verifyDocument(bool isDni) async {
    final auth = Provider.of<AuthNotifier>(context, listen: false);
    final user = auth.currentCaregiver;
    if (user == null) return;

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _isLoading = true;
        if (isDni) {
          _dniStatus = 'Analizando DNI...';
        } else {
          _criminalRecordStatus = 'Analizando Penales...';
        }
      });

      String path = result.files.single.path!;
      ValidationResult validation;

      if (isDni) {
        validation = await MLKitService.validateDNI(path, user.name);
        setState(() => _dniStatus = validation.message);
      } else {
        validation = await MLKitService.validateCriminalRecord(path, user.name);
        setState(() => _criminalRecordStatus = validation.message);
      }

      // If approved or manual review, update backend
      if (validation.isApproved || validation.isManualReview) {
        String newStatus = validation.isApproved ? 'verified' : 'manual_review';
        await _updateVerificationStatus(user, newStatus);
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateVerificationStatus(CaregiverProfile profile, String newStatus) async {
    final caregiverState = Provider.of<CaregiverNotifier>(context, listen: false);
    if (useFirebaseBackend) {
      await FirebaseFirestore.instance.collection('caregivers').doc(profile.id).update({
        'verificationStatus': newStatus,
        'isVerified': newStatus == 'verified',
      });
    }
    // Update local state
    final updatedProfile = CaregiverProfile(
      id: profile.id,
      name: profile.name,
      title: profile.title,
      bio: profile.bio,
      pricePerHour: profile.pricePerHour,
      rating: profile.rating,
      reviewsCount: profile.reviewsCount,
      distance: profile.distance,
      imageUrl: profile.imageUrl,
      specialties: profile.specialties,
      verified: newStatus == 'verified',
      availableSlots: profile.availableSlots,
      verificationStatus: newStatus,
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
          : Padding(
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
                  const Text('Sube una foto o PDF de tu DNI o NIE. El sistema automatizado lo validará en segundos.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _verifyDocument(true),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir DNI/NIE'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.indigo,
                    ),
                  ),
                  if (_dniStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_dniStatus, style: TextStyle(color: _dniStatus.contains('Aprobado') || _dniStatus.contains('válido') ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Paso 2: Certificado de Penales',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Sube una foto o PDF de tu Certificado de Antecedentes Penales expedido por el Ministerio de Justicia.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _verifyDocument(false),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir Certificado Penales'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.indigo,
                    ),
                  ),
                  if (_criminalRecordStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_criminalRecordStatus, style: TextStyle(color: _criminalRecordStatus.contains('Aprobado') || _criminalRecordStatus.contains('válido') ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
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
      case 'verified':
        color = Colors.green;
        text = '¡Perfil Verificado!';
        icon = Icons.verified;
        break;
      case 'manual_review':
        color = Colors.orange;
        text = 'En revisión manual por el equipo.';
        icon = Icons.pending_actions;
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
