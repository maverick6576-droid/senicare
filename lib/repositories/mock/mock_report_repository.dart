import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockReportRepository implements ReportRepository {
  @override
  Future<void> addReport(Report report) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
