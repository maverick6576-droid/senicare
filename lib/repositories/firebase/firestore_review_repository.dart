import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreReviewRepository implements ReviewRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Para soportar paginación
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;

  @override
  Future<List<Review>> fetchReviewsForCaregiver(String caregiverId, {int limit = 10, bool refresh = false}) async {
    if (refresh) {
      _lastDocument = null;
      _hasMore = true;
    }

    if (!_hasMore) return [];

    Query firestoreQuery = _firestore
        .collection('reviews')
        .where('caregiverId', isEqualTo: caregiverId)
        .limit(limit);

    if (_lastDocument != null) {
      firestoreQuery = firestoreQuery.startAfterDocument(_lastDocument!);
    }

    final querySnapshot = await firestoreQuery.get();
    
    if (querySnapshot.docs.length < limit) {
      _hasMore = false;
    }

    if (querySnapshot.docs.isNotEmpty) {
      _lastDocument = querySnapshot.docs.last;
    }

    return querySnapshot.docs.map((doc) => Review.fromFirestore(doc)).toList();
  }

  @override
  Future<void> addReview(String caregiverId, Review review) async {
    await _firestore.collection('reviews').doc(review.id).set({
      'caregiverId': caregiverId,
      'clientId': review.clientId,
      'clientName': review.clientName,
      'rating': review.rating,
      'punctualityRating': review.punctualityRating,
      'empathyRating': review.empathyRating,
      'communicationRating': review.communicationRating,
      'hygieneRating': review.hygieneRating,
      'comment': review.comment,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // La valoración media (rating y reviewsCount) en caregivers/{caregiverId}
    // se recalcula de forma segura en Cloud Function (syncCaregiverRatingOnReviewCreated).
  }
}