import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/interfaces/client_repository.dart';

class MockClientRepository implements ClientRepository {
  final Map<String, ClientProfile> _clients = {};

  Iterable<ClientProfile> get allClients => _clients.values;

  void seedClient(ClientProfile profile) {
    _clients[profile.id] = profile;
  }

  @override
  Future<ClientProfile?> getClient(String id) async {
    return _clients[id];
  }

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    final existing = _clients[id];
    final checklist = data.containsKey('defaultCareChecklist')
        ? (data['defaultCareChecklist'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[]
        : List<String>.from(existing?.defaultCareChecklist ?? const []);
    final familyEmails = data.containsKey('authorizedFamilyEmails')
        ? (data['authorizedFamilyEmails'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[]
        : List<String>.from(existing?.authorizedFamilyEmails ?? const []);

    final ownerUid = data.containsKey('ownerUid')
        ? data['ownerUid']?.toString()
        : (existing?.ownerUid ?? id);

    final memberUids = data.containsKey('memberUids')
        ? (data['memberUids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            <String>[ownerUid ?? id]
        : List<String>.from(
            existing?.memberUids.isNotEmpty == true
                ? existing!.memberUids
                : <String>[ownerUid ?? id],
          );

    final members = data.containsKey('members')
        ? ClientProfile.parseMembers(data['members'])
        : Map<String, FamilyMember>.from(existing?.members ?? const {});

    final emailRoles = data.containsKey('familyEmailRoles')
        ? ClientProfile.parseEmailRoles(data['familyEmailRoles'])
        : Map<String, FamilyRole>.from(
            existing?.familyEmailRoles ?? const {},
          );

    _clients[id] = ClientProfile(
      id: id,
      name: data.containsKey('name')
          ? (data['name']?.toString() ?? '')
          : (existing?.name ?? ''),
      phone: data.containsKey('phone')
          ? (data['phone']?.toString() ?? '')
          : (existing?.phone ?? ''),
      homeAddress: data.containsKey('homeAddress')
          ? (data['homeAddress']?.toString() ?? '')
          : (existing?.homeAddress ?? ''),
      latitude: data.containsKey('latitude')
          ? (data['latitude'] as num?)?.toDouble()
          : existing?.latitude,
      longitude: data.containsKey('longitude')
          ? (data['longitude'] as num?)?.toDouble()
          : existing?.longitude,
      patientDetails: data.containsKey('patientDetails')
          ? (data['patientDetails']?.toString() ?? '')
          : (existing?.patientDetails ?? ''),
      onboardingComplete: data.containsKey('onboardingComplete')
          ? (data['onboardingComplete'] as bool? ?? false)
          : (existing?.onboardingComplete ?? true),
      defaultCareChecklist: List<String>.unmodifiable(checklist),
      authorizedFamilyEmails: List<String>.unmodifiable(familyEmails),
      hasSeenClientTutorial: data.containsKey('clientTutorialSeen')
          ? data['clientTutorialSeen'] == true
          : (existing?.hasSeenClientTutorial ?? false),
      ownerUid: ownerUid,
      memberUids: List<String>.unmodifiable(memberUids),
      members: Map<String, FamilyMember>.unmodifiable(members),
      familyEmailRoles: Map<String, FamilyRole>.unmodifiable(emailRoles),
    );
  }
}
