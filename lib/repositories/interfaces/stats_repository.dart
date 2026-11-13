abstract class StatsRepository {
  Future<int> getAccumulatedHours(String clientId, String caregiverId);
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId);
  Future<void> addCompletedHours(String clientId, String caregiverId, int hoursToAdd);
}
