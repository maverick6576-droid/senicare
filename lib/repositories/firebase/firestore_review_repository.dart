import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreReviewRepository implements ReviewRepository {
  final FirebaseFirestore _firestore;
  FirestoreReviewRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Paginación aislada por cuidador para evitar cruzar cursores entre perfiles
  final Map<String, DocumentSnapshot?> _lastDocuments = {};
  final Map<String, bool> _hasMoreByCaregiver = {};

  @override
  Future<List<Review>> fetchReviewsForCaregiver(String caregiverId, {int limit = 10, bool refresh = false}) async {
    if (refresh) {
      _lastDocuments.remove(caregiverId);
      _hasMoreByCaregiver[caregiverId] = true;
    }

    if (!(_hasMoreByCaregiver[caregiverId] ?? true)) return [];

    Query firestoreQuery = _firestore
        .collection('reviews')
        .where('caregiverId', isEqualTo: caregiverId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    final lastDoc = _lastDocuments[caregiverId];
    if (lastDoc != null) {
      firestoreQuery = firestoreQuery.startAfterDocument(lastDoc);
    }

    final querySnapshot = await firestoreQuery.get();

    if (querySnapshot.docs.length < limit) {
      _hasMoreByCaregiver[caregiverId] = false;
    }

    if (querySnapshot.docs.isNotEmpty) {
      _lastDocuments[caregiverId] = querySnapshot.docs.last;
    }

    return querySnapshot.docs.map((doc) => Review.fromFirestore(doc)).toList();
  }

  @override
  Future<void> addReview(String caregiverId, Review review) async {
    final targetId = (review.bookingId != null && review.bookingId!.isNotEmpty)
        ? review.bookingId!
        : review.id;
    await _firestore.collection('reviews').doc(targetId).set({
      'caregiverId': caregiverId,
      'clientId': review.clientId,
      'clientName': review.clientName,
      'bookingId': targetId,
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
