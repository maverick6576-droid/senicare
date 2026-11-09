import 'package:senicare/models/models.dart';

abstract class CaregiverRepository {
  Future<List<CaregiverProfile>> fetchCaregivers({String specialty = 'Todos', String query = '', bool refresh = false, double? mapLat, double? mapLng});
  Future<CaregiverProfile?> getCaregiver(String id);
  Future<void> updateCaregiverAvailability(String id, String day, List<String> hours);
  Future<void> updateProfile(String id, Map<String, dynamic> data);
  
  Future<List<TimeSlot>> fetchTimeSlots(String caregiverId, String date);
  Future<void> updateTimeSlot(String caregiverId, String date, TimeSlot slot);

  /// Atomically writes a full set of slots for a given day using a Firestore batch.
  /// Replaces any pre-existing slots for that day.
  Future<void> setBatchTimeSlots(String caregiverId, String date, List<TimeSlot> slots);

  /// Deletes all slot documents for a given day.
  Future<void> clearDaySlots(String caregiverId, String date);
}

