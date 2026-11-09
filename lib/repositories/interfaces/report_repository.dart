import 'package:senicare/models/models.dart';

abstract class ReportRepository {
  Future<void> addReport(Report report);
}
