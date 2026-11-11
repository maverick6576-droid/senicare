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
  final bool hasSeenClientTutorial;

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
    this.hasSeenClientTutorial = false,
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
      hasSeenClientTutorial: data['clientTutorialSeen'] == true,
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
      'clientTutorialSeen': hasSeenClientTutorial,
    };
  }

  ClientProfile copyWith({
    String? id,
    String? name,
    String? phone,
    String? homeAddress,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    String? patientDetails,
    bool? onboardingComplete,
    List<String>? defaultCareChecklist,
    List<String>? authorizedFamilyEmails,
    bool? hasSeenClientTutorial,
  }) {
    return ClientProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      homeAddress: homeAddress ?? this.homeAddress,
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      patientDetails: patientDetails ?? this.patientDetails,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      defaultCareChecklist: defaultCareChecklist != null
          ? List<String>.unmodifiable(defaultCareChecklist)
          : List<String>.unmodifiable(this.defaultCareChecklist),
      authorizedFamilyEmails: authorizedFamilyEmails != null
          ? List<String>.unmodifiable(authorizedFamilyEmails)
          : List<String>.unmodifiable(this.authorizedFamilyEmails),
      hasSeenClientTutorial:
          hasSeenClientTutorial ?? this.hasSeenClientTutorial,
    );
  }
}
