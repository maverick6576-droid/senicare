import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockReviewRepository implements ReviewRepository {
  @override
  Future<List<Review>> fetchReviewsForCaregiver(String caregiverId, {int limit = 10, bool refresh = false}) async {
    return [
      Review(
        id: 'r1',
        caregiverId: caregiverId,
        clientId: 'c1',
        clientName: 'María G.',
        rating: 5.0,
        comment: 'Excelente profesional, muy cariñosa con mi madre.',
      ),
      Review(
        id: 'r2',
        caregiverId: caregiverId,
        clientId: 'c2',
        clientName: 'Juan P.',
        rating: 4.5,
        comment: 'Llegó puntual y realizó todas las tareas acordadas perfectamente.',
      ),
    ];
  }

  @override
  Future<void> addReview(String caregiverId, Review review) async {}
}

