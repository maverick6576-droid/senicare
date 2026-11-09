import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class FirestoreReportRepository implements ReportRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> addReport(Report report) async {
    try {
      await _firestore.collection('reports').doc(report.id).set(report.toFirestore());
    } catch (e) {
      debugPrint('Error adding report: $e');
      rethrow;
    }
  }
}
