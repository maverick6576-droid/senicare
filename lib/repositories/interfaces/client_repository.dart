import 'package:senicare/models/models.dart';

abstract class ClientRepository {
  Future<ClientProfile?> getClient(String id);
  Future<void> updateClient(String id, Map<String, dynamic> data);
}
