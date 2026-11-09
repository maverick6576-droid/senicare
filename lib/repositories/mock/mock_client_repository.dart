import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/interfaces/client_repository.dart';

class MockClientRepository implements ClientRepository {
  final Map<String, ClientProfile> _clients = {};

  @override
  Future<ClientProfile?> getClient(String id) async {
    return _clients[id];
  }

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    final existing = _clients[id];
    _clients[id] = ClientProfile(
      id: id,
      name: data['name'] ?? existing?.name ?? '',
      phone: data['phone'] ?? existing?.phone ?? '',
      homeAddress: data['homeAddress'] ?? existing?.homeAddress ?? '',
      latitude: data['latitude'] ?? existing?.latitude,
      longitude: data['longitude'] ?? existing?.longitude,
      patientDetails: data['patientDetails'] ?? existing?.patientDetails ?? '',
      onboardingComplete: data['onboardingComplete'] ?? existing?.onboardingComplete ?? true,
    );
  }
}
