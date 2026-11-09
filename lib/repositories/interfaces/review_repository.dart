import 'package:senicare/models/models.dart';

abstract class ReviewRepository {
  Future<List<Review>> fetchReviewsForCaregiver(String caregiverId, {int limit = 10, bool refresh = false});
  Future<void> addReview(String caregiverId, Review review);
}

