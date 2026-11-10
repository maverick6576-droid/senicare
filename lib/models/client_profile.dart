import 'package:cloud_firestore/cloud_firestore.dart';

class ClientProfile {
  final String id;
  final String name;
  final String phone;
  final String homeAddress;
  final double? latitude;
  final double? longitude;
  final String patientDetails;
  final bool onboardingComplete;
  final List<String> defaultCareChecklist;
  final List<String> authorizedFamilyEmails;

  ClientProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.homeAddress,
    this.latitude,
    this.longitude,
    required this.patientDetails,
    required this.onboardingComplete,
    this.defaultCareChecklist = const [],
    this.authorizedFamilyEmails = const [],
  });

  factory ClientProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClientProfile(
      id: doc.id,
      name: data['name']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      homeAddress: data['homeAddress']?.toString() ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      patientDetails: data['patientDetails']?.toString() ?? '',
      onboardingComplete: data['onboardingComplete'] ?? false,
      defaultCareChecklist: (data['defaultCareChecklist'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      authorizedFamilyEmails: (data['authorizedFamilyEmails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'homeAddress': homeAddress,
      'latitude': latitude,
      'longitude': longitude,
      'patientDetails': patientDetails,
      'onboardingComplete': onboardingComplete,
      'defaultCareChecklist': defaultCareChecklist,
      'authorizedFamilyEmails': authorizedFamilyEmails,
    };
  }
}
