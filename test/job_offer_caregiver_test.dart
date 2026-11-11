import 'package:flutter_test/flutter_test.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

void main() {
  late MockJobOfferRepository repo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    repo = MockJobOfferRepository();
    DependencyInjection.jobOffers = repo;
  });

  JobOffer makeOffer({
    String id = '',
    String clientName = 'María López',
    double lat = 41.3851,
    double lng = 2.1734,
    double pricePerHour = 15.0,
    int totalHours = 4,
    bool isUrgent = false,
    double urgencyBonusRate = 0.0,
    DateTime? startDate,
    JobOfferStatus status = JobOfferStatus.open,
  }) {
    return JobOffer(
      id: id,
      clientId: 'client_1',
      clientName: clientName,
      clientLatitude: lat,
      clientLongitude: lng,
      title: 'Cuidado de tarde',
      description: 'Acompañamiento',
      pricePerHour: pricePerHour,
      totalHours: totalHours,
      isRecurring: false,
      startDate: startDate ?? DateTime.now().add(const Duration(days: 2)),
      status: status,
      isUrgent: isUrgent,
      urgencyBonusRate: urgencyBonusRate,
      createdAt: DateTime.now(),
    );
  }

  test('JobOffer.familyLabel formatea nombres variados de forma segura', () {
    expect(makeOffer(clientName: '').familyLabel, 'Familia cercana');
    expect(makeOffer(clientName: 'Cliente').familyLabel, 'Familia cercana');
    expect(makeOffer(clientName: 'Familia García').familyLabel, 'Familia García');
    expect(makeOffer(clientName: 'Ana María López').familyLabel, 'Familia López');
    expect(makeOffer(clientName: 'Carlos').familyLabel, 'Familia de Carlos');
  });

  test('Cálculo neto y comisión efectiva respeta tramos y descuento urgente', () {
    expect(FirestoreStatsRepository.calculateEffectiveOfferCommissionRate(0, 0.0), closeTo(0.18, 0.0001));
    expect(FirestoreStatsRepository.calculateEffectiveOfferCommissionRate(0, 0.10), closeTo(0.08, 0.0001));
    expect(FirestoreStatsRepository.calculateEffectiveOfferCommissionRate(100, 0.10), closeTo(0.05, 0.0001));

    final netStandard = FirestoreStatsRepository.estimateOfferNetTotal(
      totalHours: 4,
      hourlyRate: 15.0,
      urgencyBonusRate: 0.0,
      accumulatedHours: 0,
    );
    expect(netStandard, closeTo(49.2, 0.001));

    final netUrgent = FirestoreStatsRepository.estimateOfferNetTotal(
      totalHours: 4,
      hourlyRate: 15.0,
      urgencyBonusRate: 0.10,
      accumulatedHours: 0,
    );
    expect(netUrgent, closeTo(55.2, 0.001));
  });

  test('streamNearbyOffers filtra caducadas/lejanas y prioriza urgentes y fecha próxima', () async {
    await repo.createOffer(makeOffer(
      clientName: 'Caducada',
      startDate: DateTime.now().subtract(const Duration(hours: 2)),
    ));
    await repo.createOffer(makeOffer(
      clientName: 'Lejana',
      lat: 40.4168,
      lng: -3.7038,
    ));
    await repo.createOffer(makeOffer(
      clientName: 'Normal Pronta',
      isUrgent: false,
      startDate: DateTime.now().add(const Duration(days: 2)),
    ));
    await repo.createOffer(makeOffer(
      clientName: 'Urgente',
      isUrgent: true,
      urgencyBonusRate: 0.10,
      startDate: DateTime.now().add(const Duration(days: 3)),
    ));

    final nearby = await repo.streamNearbyOffers(41.3851, 2.1734, 25.0).first;
    expect(nearby.length, 2);
    expect(nearby.first.clientName, 'Urgente');
    expect(nearby.last.clientName, 'Normal Pronta');
  });

  test('JobOfferNotifier evita duplicados, permite editar y retirar solicitud y limpia estado al salir', () async {
    final notifier = JobOfferNotifier();
    final offerId = await repo.createOffer(makeOffer());

    notifier.initForCaregiver(41.3851, 2.1734, 30.0, caregiverId: 'cg_1');
    await Future.delayed(const Duration(milliseconds: 50));

    final app = JobApplication(
      id: 'app_1',
      offerId: offerId,
      caregiverId: 'cg_1',
      caregiverName: 'Elena Cuidadora',
      caregiverImageUrl: '',
      caregiverRating: 4.9,
      caregiverReviewsCount: 12,
      message: 'Disponible mañana',
      proposedPrice: 16.0,
      appliedAt: DateTime.now(),
    );

    await notifier.applyToOffer(app);
    await notifier.applyToOffer(JobApplication(
      id: 'app_2',
      offerId: offerId,
      caregiverId: 'cg_1',
      caregiverName: 'Elena Cuidadora',
      caregiverImageUrl: '',
      caregiverRating: 4.9,
      caregiverReviewsCount: 12,
      message: 'Mensaje actualizado',
      proposedPrice: 17.5,
      appliedAt: DateTime.now(),
    ));

    final storedApps = await repo.streamOfferApplications(offerId).first;
    expect(storedApps.length, 1);
    expect(storedApps.first.proposedPrice, 17.5);
    expect(notifier.myApplicationsByOfferId[offerId]?.proposedPrice, 17.5);

    await notifier.updateApplication(
      offerId,
      storedApps.first.id,
      message: 'Nueva nota',
      proposedPrice: 15.5,
      caregiverId: 'cg_1',
    );
    expect(notifier.myApplicationsByOfferId[offerId]?.proposedPrice, 15.5);

    final ownApp = await repo.streamCaregiverApplicationForOffer(offerId, 'cg_1').first;
    expect(ownApp?.message, 'Nueva nota');

    await notifier.withdrawApplication(offerId, storedApps.first.id, 'cg_1');
    expect(notifier.myApplicationsByOfferId.containsKey(offerId), false);
    expect(notifier.myApplications, isEmpty);

    notifier.clear(notify: false);
    expect(notifier.nearbyOffers, isEmpty);
    notifier.dispose();
  });
}
