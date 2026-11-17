import 'package:cloud_firestore/cloud_firestore.dart';
import 'family_account.dart';

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
  final String? ownerUid;
  final List<String> memberUids;
  final Map<String, FamilyMember> members;
  final Map<String, FamilyRole> familyEmailRoles;

  // Campos de personalización de la persona a cuidar y acceso al domicilio
  final String careRecipientName;
  final String mobilityLevel;
  final String cognitiveNeeds;
  final String dietNotes;
  final String emergencyPhone;
  final String homeAccessNotes;
  final List<String> structuredHealthTags;

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
    this.ownerUid,
    this.memberUids = const [],
    this.members = const {},
    this.familyEmailRoles = const {},
    this.careRecipientName = '',
    this.mobilityLevel = '',
    this.cognitiveNeeds = '',
    this.dietNotes = '',
    this.emergencyPhone = '',
    this.homeAccessNotes = '',
    this.structuredHealthTags = const [],
  });

  String get effectiveOwnerUid =>
      (ownerUid != null && ownerUid!.trim().isNotEmpty) ? ownerUid!.trim() : id;

  bool isMember(String uid) {
    if (uid.trim().isEmpty) return false;
    return uid == id ||
        uid == effectiveOwnerUid ||
        memberUids.contains(uid) ||
        members.containsKey(uid);
  }

  FamilyRole? roleFor(String uid) {
    if (uid.trim().isEmpty) return null;
    if (uid == effectiveOwnerUid || uid == id) {
      return members[uid]?.role ?? FamilyRole.admin;
    }
    if (members.containsKey(uid)) {
      return members[uid]!.role;
    }
    if (memberUids.contains(uid)) {
      return FamilyRole.collaborator;
    }
    return null;
  }

  bool canManagePayments(String uid) =>
      roleFor(uid)?.canManagePayments ?? false;

  bool canManageMembers(String uid) =>
      roleFor(uid)?.canManageMembers ?? false;

  bool canManageCareDetails(String uid) =>
      roleFor(uid)?.canManageCareDetails ?? false;

  FamilyRole emailRoleFor(String email) {
    final normalized = email.trim().toLowerCase();
    return familyEmailRoles[normalized] ?? FamilyRole.collaborator;
  }

  List<FamilyMember> get orderedMembers {
    final map = <String, FamilyMember>{};
    for (final entry in members.entries) {
      map[entry.key] = entry.value;
    }
    if (!map.containsKey(effectiveOwnerUid)) {
      map[effectiveOwnerUid] = FamilyMember(
        uid: effectiveOwnerUid,
        email: '',
        displayName: name.isNotEmpty ? name : 'Propietario familiar',
        role: FamilyRole.admin,
        joinedVia: 'owner',
        isOwner: true,
      );
    }
    final list = map.values.toList();
    list.sort((a, b) {
      if (a.uid == effectiveOwnerUid || a.isOwner) return -1;
      if (b.uid == effectiveOwnerUid || b.isOwner) return 1;
      if (a.role != b.role) {
        return a.role == FamilyRole.admin ? -1 : 1;
      }
      return a.effectiveName
          .toLowerCase()
          .compareTo(b.effectiveName.toLowerCase());
    });
    return list;
  }

  static Map<String, FamilyMember> parseMembers(dynamic raw) {
    if (raw is! Map) return const {};
    final parsed = <String, FamilyMember>{};
    raw.forEach((key, value) {
      final uid = key.toString().trim();
      if (uid.isNotEmpty && value is Map) {
        parsed[uid] = FamilyMember.fromMap(
          uid,
          Map<String, dynamic>.from(value),
        );
      }
    });
    return Map<String, FamilyMember>.unmodifiable(parsed);
  }

  static Map<String, FamilyRole> parseEmailRoles(dynamic raw) {
    if (raw is! Map) return const {};
    final parsed = <String, FamilyRole>{};
    raw.forEach((key, value) {
      final email = key.toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        parsed[email] = FamilyRole.fromString(value);
      }
    });
    return Map<String, FamilyRole>.unmodifiable(parsed);
  }

  factory ClientProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawMemberUids = (data['memberUids'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final parsedMembers = parseMembers(data['members']);
    final owner = data['ownerUid']?.toString().trim();
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
      ownerUid: (owner != null && owner.isNotEmpty) ? owner : doc.id,
      memberUids: rawMemberUids.isNotEmpty ? rawMemberUids : [doc.id],
      members: parsedMembers,
      familyEmailRoles: parseEmailRoles(data['familyEmailRoles']),
      careRecipientName: data['careRecipientName']?.toString() ?? '',
      mobilityLevel: data['mobilityLevel']?.toString() ?? '',
      cognitiveNeeds: data['cognitiveNeeds']?.toString() ?? '',
      dietNotes: data['dietNotes']?.toString() ?? '',
      emergencyPhone: data['emergencyPhone']?.toString() ?? '',
      homeAccessNotes: data['homeAccessNotes']?.toString() ?? '',
      structuredHealthTags: (data['structuredHealthTags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    final serializedMembers = <String, dynamic>{};
    members.forEach((k, v) => serializedMembers[k] = v.toMap());
    final serializedEmailRoles = <String, dynamic>{};
    familyEmailRoles.forEach((k, v) => serializedEmailRoles[k] = v.firestoreValue);

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
      'ownerUid': effectiveOwnerUid,
      'memberUids': memberUids.isNotEmpty ? memberUids : [effectiveOwnerUid],
      if (serializedMembers.isNotEmpty) 'members': serializedMembers,
      if (serializedEmailRoles.isNotEmpty)
        'familyEmailRoles': serializedEmailRoles,
      if (careRecipientName.isNotEmpty) 'careRecipientName': careRecipientName,
      if (mobilityLevel.isNotEmpty) 'mobilityLevel': mobilityLevel,
      if (cognitiveNeeds.isNotEmpty) 'cognitiveNeeds': cognitiveNeeds,
      if (dietNotes.isNotEmpty) 'dietNotes': dietNotes,
      if (emergencyPhone.isNotEmpty) 'emergencyPhone': emergencyPhone,
      if (homeAccessNotes.isNotEmpty) 'homeAccessNotes': homeAccessNotes,
      if (structuredHealthTags.isNotEmpty)
        'structuredHealthTags': structuredHealthTags,
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
    String? ownerUid,
    List<String>? memberUids,
    Map<String, FamilyMember>? members,
    Map<String, FamilyRole>? familyEmailRoles,
    String? careRecipientName,
    String? mobilityLevel,
    String? cognitiveNeeds,
    String? dietNotes,
    String? emergencyPhone,
    String? homeAccessNotes,
    List<String>? structuredHealthTags,
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
      ownerUid: ownerUid ?? this.ownerUid,
      memberUids: memberUids != null
          ? List<String>.unmodifiable(memberUids)
          : List<String>.unmodifiable(this.memberUids),
      members: members != null
          ? Map<String, FamilyMember>.unmodifiable(members)
          : Map<String, FamilyMember>.unmodifiable(this.members),
      familyEmailRoles: familyEmailRoles != null
          ? Map<String, FamilyRole>.unmodifiable(familyEmailRoles)
          : Map<String, FamilyRole>.unmodifiable(this.familyEmailRoles),
      careRecipientName: careRecipientName ?? this.careRecipientName,
      mobilityLevel: mobilityLevel ?? this.mobilityLevel,
      cognitiveNeeds: cognitiveNeeds ?? this.cognitiveNeeds,
      dietNotes: dietNotes ?? this.dietNotes,
      emergencyPhone: emergencyPhone ?? this.emergencyPhone,
      homeAccessNotes: homeAccessNotes ?? this.homeAccessNotes,
      structuredHealthTags: structuredHealthTags != null
          ? List<String>.unmodifiable(structuredHealthTags)
          : List<String>.unmodifiable(this.structuredHealthTags),
    );
  }
}
