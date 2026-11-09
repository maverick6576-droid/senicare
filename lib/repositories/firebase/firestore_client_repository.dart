import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/interfaces/client_repository.dart';

class FirestoreClientRepository implements ClientRepository {
  final CollectionReference _collection = FirebaseFirestore.instance.collection('clients');
  final Map<String, ClientProfile> _cache = {};

  @override
  Future<ClientProfile?> getClient(String id) async {
    if (_cache.containsKey(id)) {
      return _cache[id];
    }
    try {
      final doc = await _collection.doc(id).get();
      if (doc.exists) {
        final profile = ClientProfile.fromFirestore(doc);
        _cache[id] = profile;
        return profile;
      }
      return null;
    } catch (e) {
      print('Error fetching client: $e');
      throw Exception('Error fetching client: $e');
    }
  }

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    try {
      await _collection.doc(id).set(data, SetOptions(merge: true));
    } catch (e) {
      print('Error updating client: $e');
      throw Exception('Error updating client: $e');
    }
  }
}
