import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CaregiverProfile {
  final String id;
  final String name;
  final String title;
  final String bio;
  final double pricePerHour;
  final double rating;
  final int reviewsCount;
  final String distance;
  final double? latitude;
  final double? longitude;
  final String imageUrl;
  final String voiceIntroUrl;
  final List<String> specialties;
  final bool verified;
  final Map<String, List<String>> availableSlots;
  final String dniUrl;
  final String criminalRecordUrl;
  final bool hasDniSubmitted;
  final bool hasCriminalSubmitted;
  final double maxDistanceRadius;
  final String homeAddress;
  final String verificationStatus;
  final String? stripeAccountId;
  final bool onboardingComplete;
  final bool isKycVerified;
  final bool hasSeenCaregiverTutorial;
  final int noShowsCount;

  bool get hasDni => dniUrl.trim().isNotEmpty || hasDniSubmitted;
  bool get hasCriminalRecord => criminalRecordUrl.trim().isNotEmpty || hasCriminalSubmitted;
  bool get hasStripeAccount => stripeAccountId != null && stripeAccountId!.isNotEmpty;
  bool get isSuperCaregiver => (verified || verificationStatus == 'approved') && rating >= 4.7 && reviewsCount >= 2 && noShowsCount == 0;
  int get retentionRate => rating >= 4.9 ? 97 : (rating >= 4.7 ? 94 : (rating >= 4.5 ? 90 : 86));
  bool get hasOfficialCertification {
    if (!(verified || verificationStatus == 'approved')) return false;
    final combined = '${title.toLowerCase()} ${bio.toLowerCase()} ${specialties.join(" ").toLowerCase()}';
    return combined.contains('sociosanit') ||
        combined.contains('tcae') ||
        combined.contains('auxiliar') ||
        combined.contains('enferm') ||
        combined.contains('geriatr') ||
        combined.contains('alzheimer') ||
        hasCriminalRecord;
  }
  final List<DateTime> incidentDates;
  final DateTime? blockedUntil;
  final String accountStatus;

  CaregiverProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.bio,
    required this.pricePerHour,
    required this.rating,
    required this.reviewsCount,
    required this.distance,
    this.latitude,
    this.longitude,
    required this.imageUrl,
    this.voiceIntroUrl = '',
    required this.specialties,
    required this.verified,
    required this.availableSlots,
    this.dniUrl = '',
    this.criminalRecordUrl = '',
    bool? hasDniSubmitted,
    bool? hasCriminalSubmitted,
    this.maxDistanceRadius = 10.0,
    this.homeAddress = '',
    this.verificationStatus = 'unverified',
    this.stripeAccountId,
    this.onboardingComplete = false,
    this.isKycVerified = false,
    this.hasSeenCaregiverTutorial = false,
    this.noShowsCount = 0,
    this.incidentDates = const [],
    this.blockedUntil,
    this.accountStatus = 'active',
  })  : hasDniSubmitted = hasDniSubmitted ?? dniUrl.trim().isNotEmpty,
        hasCriminalSubmitted = hasCriminalSubmitted ?? criminalRecordUrl.trim().isNotEmpty;

  factory CaregiverProfile.fromFirestore(DocumentSnapshot doc) {
    try {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
      final dni = data['dniUrl']?.toString() ?? '';
      final criminal = data['criminalRecordUrl']?.toString() ?? '';
      return CaregiverProfile(
        id: doc.id,
        name: data['name']?.toString() ?? 'Sin nombre',
        title: data['title']?.toString() ?? '',
        bio: data['bio']?.toString() ?? '',
        pricePerHour: (data['pricePerHour'] ?? 0).toDouble(),
        rating: (data['rating'] ?? 0).toDouble(),
        reviewsCount: data['reviewsCount'] ?? 0,
        distance: data['distance']?.toString() ?? '',
        imageUrl: data['imageUrl']?.toString() ?? '',
        voiceIntroUrl: data['voiceIntroUrl']?.toString() ?? '',
        specialties: List<String>.from(data['specialties'] ?? []),
        verified: data['isVerified'] ?? data['verified'] ?? false,
        availableSlots: (data['availableSlots'] as Map? ?? const {}).map(
          (k, e) => MapEntry(k.toString(), List<String>.from(e as List)),
        ),
        dniUrl: dni,
        criminalRecordUrl: criminal,
        hasDniSubmitted: data['hasDniSubmitted'] == true || dni.trim().isNotEmpty,
        hasCriminalSubmitted: data['hasCriminalSubmitted'] == true || criminal.trim().isNotEmpty,
        latitude: (data['latitude'] as num?)?.toDouble(),
        longitude: (data['longitude'] as num?)?.toDouble(),
        maxDistanceRadius: (data['maxDistanceRadius'] as num?)?.toDouble() ?? 10.0,
        homeAddress: data['homeAddress']?.toString() ?? '',
        verificationStatus: data['verificationStatus']?.toString() ?? 'unverified',
        stripeAccountId: data['stripeAccountId']?.toString(),
        onboardingComplete: data['onboardingComplete'] ?? false,
        isKycVerified: data['isKycVerified'] ?? false,
        hasSeenCaregiverTutorial: data['caregiverTutorialSeen'] == true,
        noShowsCount: data['noShowsCount'] ?? 0,
        incidentDates: (data['incidentDates'] as List<dynamic>?)?.map((d) => (d as Timestamp).toDate()).toList() ?? [],
        blockedUntil: (data['blockedUntil'] as Timestamp?)?.toDate(),
        accountStatus: data['status']?.toString() ?? 'active',
      );
    } catch (e) {
      debugPrint('Error parsing CaregiverProfile ${doc.id}: $e');
      // En caso de corrupción crítica de datos, devolvemos un perfil vacío/seguro en lugar de crashear
      return CaregiverProfile(
        id: doc.id,
        name: 'Perfil no disponible',
        title: 'Error de datos',
        bio: 'Ocurrió un error al cargar la información de este cuidador.',
        pricePerHour: 0.0,
        rating: 0.0,
        reviewsCount: 0,
        distance: '-',
        imageUrl: '',
        specialties: [],
        verified: false,
        availableSlots: {},
        dniUrl: '',
        criminalRecordUrl: '',
        latitude: null,
        longitude: null,
        maxDistanceRadius: 10.0,
        homeAddress: '',
        verificationStatus: 'unverified',
        stripeAccountId: null,
        onboardingComplete: false,
        isKycVerified: false,
      );
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'title': title,
      'bio': bio,
      'pricePerHour': pricePerHour,
      'rating': rating,
      'reviewsCount': reviewsCount,
      'distance': distance,
      'imageUrl': imageUrl,
      'voiceIntroUrl': voiceIntroUrl,
      'specialties': specialties,
      'isVerified': verified,
      'availableSlots': availableSlots,
      'hasDniSubmitted': hasDni,
      'hasCriminalSubmitted': hasCriminalRecord,
      'latitude': latitude,
      'longitude': longitude,
      'maxDistanceRadius': maxDistanceRadius,
      'homeAddress': homeAddress,
      'verificationStatus': verificationStatus,
      'stripeAccountId': stripeAccountId,
      'onboardingComplete': onboardingComplete,
      'isKycVerified': isKycVerified,
      'caregiverTutorialSeen': hasSeenCaregiverTutorial,
      'noShowsCount': noShowsCount,
      'incidentDates': incidentDates.map((d) => Timestamp.fromDate(d)).toList(),
      if (blockedUntil != null) 'blockedUntil': Timestamp.fromDate(blockedUntil!),
      'status': accountStatus,
    };
  }
}
