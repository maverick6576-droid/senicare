import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

void main() {
  group('Firebase Repositories with FakeFirebaseFirestore & MockFirebaseAuth', () {
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
    });

    test('FirebaseAuthRepository signs up caregiver, persists consent & resolves role', () async {
      final mockAuth = MockFirebaseAuth();
      final repo = FirebaseAuthRepository(auth: mockAuth, firestore: fakeDb);

      await repo.signUpWithEmail(
        'ana.care@senicare.es',
        'SecretPass123!',
        'caregiver',
        {
          'name': 'Ana Cuidadora',
          'pricePerHour': 18.0,
          'specialties': ['Alzheimer', 'Movilidad'],
        },
      );

      final uid = repo.currentUserId;
      expect(uid, isNotNull);
      expect(await repo.getUserRole(uid!), 'caregiver');

      final userDoc = await fakeDb.collection('users').doc(uid).get();
      expect(userDoc.data()?['email'], 'ana.care@senicare.es');
      expect(userDoc.data()?['legalPolicyVersion'], '2026-11');

      final cgDoc = await fakeDb.collection('caregivers').doc(uid).get();
      expect(cgDoc.exists, isTrue);
      expect(cgDoc.data()?['name'], 'Ana Cuidadora');

      await repo.updateFCMToken('fcm_test_token_1');
      final updatedUserDoc = await fakeDb.collection('users').doc(uid).get();
      expect(updatedUserDoc.data()?['fcmToken'], 'fcm_test_token_1');

      await repo.signOut();
      expect(repo.currentUserId, isNull);
    });

    test('FirestoreBookingRepository creates, streams, updates, releases and deletes bookings', () async {
      final repo = FirestoreBookingRepository(firestore: fakeDb);
      final booking = Booking(
        id: '',
        clientId: 'client_1',
        caregiverId: 'cg_1',
        caregiverName: 'Luis Cuidado',
        day: '2026-11-20',
        slot: '10:00 - 12:00',
        cost: 36.0,
        clientFee: 1.8,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 6.48,
        caregiverPayout: 29.52,
        totalPaid: 37.8,
      );

      final bookingId = await repo.createBooking(booking);
      expect(bookingId, isNotEmpty);

      final clientBookings = await repo.streamBookings('client_1', 'client').first;
      expect(clientBookings.length, 1);
      expect(clientBookings.first.caregiverName, 'Luis Cuidado');

      await repo.updateBookingStatus(bookingId, 'confirmed');
      var stored = await fakeDb.collection('bookings').doc(bookingId).get();
      expect(stored.data()?['status'], 'confirmed');

      await repo.releaseEscrow(bookingId);
      stored = await fakeDb.collection('bookings').doc(bookingId).get();
      expect(stored.data()?['status'], 'completed');

      await repo.deleteBooking(bookingId);
      stored = await fakeDb.collection('bookings').doc(bookingId).get();
      expect(stored.exists, isFalse);
    });

    test('FirestoreCaregiverRepository filters caregivers, protects private verification and manages slots', () async {
      final mockUser = MockUser(uid: 'cg_owner', email: 'owner@senicare.es');
      final ownerAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final strangerAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'other_user', email: 'other@senicare.es'),
        signedIn: true,
      );

      await fakeDb.collection('caregivers').doc('cg_owner').set({
        'name': 'María López',
        'title': 'Gerocultora',
        'bio': 'Experta en Alzheimer',
        'pricePerHour': 17.0,
        'rating': 4.9,
        'reviewsCount': 12,
        'distance': '1.2 km',
        'latitude': 41.39,
        'longitude': 2.17,
        'imageUrl': '',
        'specialties': ['Alzheimer', 'Movilidad'],
        'verified': true,
        'verificationStatus': 'approved',
        'availableSlots': {},
      });
      await fakeDb
          .collection('caregivers')
          .doc('cg_owner')
          .collection('private')
          .doc('verification')
          .set({
        'dniUrl': 'https://private/dni.jpg',
        'criminalRecordUrl': 'https://private/crim.pdf',
      });
      await fakeDb.collection('caregivers').doc('cg_pending').set({
        'name': 'Pendiente',
        'title': 'Auxiliar',
        'bio': 'Pendiente',
        'pricePerHour': 15.0,
        'rating': 0.0,
        'reviewsCount': 0,
        'distance': '2 km',
        'imageUrl': '',
        'specialties': ['Compañía'],
        'verified': false,
        'verificationStatus': 'pending',
        'availableSlots': {},
      });

      final ownerRepo = FirestoreCaregiverRepository(firestore: fakeDb, auth: ownerAuth);
      final strangerRepo = FirestoreCaregiverRepository(firestore: fakeDb, auth: strangerAuth);

      final list = await ownerRepo.fetchCaregivers(specialty: 'Alzheimer', query: 'María', refresh: true);
      expect(list.length, 1);
      expect(list.first.id, 'cg_owner');

      final asOwner = await ownerRepo.getCaregiver('cg_owner');
      expect(asOwner?.dniUrl, 'https://private/dni.jpg');

      final asStranger = await strangerRepo.getCaregiver('cg_owner');
      expect(asStranger?.dniUrl, isEmpty);

      await ownerRepo.updateProfile('cg_owner', {'pricePerHour': 19.5});
      final updated = await ownerRepo.getCaregiver('cg_owner');
      expect(updated?.pricePerHour, 19.5);

      await ownerRepo.setBatchTimeSlots('cg_owner', '2026-11-25', [
        TimeSlot(id: '09:00', dateTime: DateTime(2026, 11, 25, 9), isAvailable: true),
        TimeSlot(id: '10:00', dateTime: DateTime(2026, 11, 25, 10), isAvailable: false),
      ]);
      final slots = await ownerRepo.fetchTimeSlots('cg_owner', '2026-11-25');
      expect(slots.length, 10);
      expect(slots.firstWhere((s) => s.dateTime.hour == 10).isAvailable, isFalse);

      await ownerRepo.clearDaySlots('cg_owner', '2026-11-25');
      final afterClear = await ownerRepo.fetchTimeSlots('cg_owner', '2026-11-25');
      expect(afterClear.firstWhere((s) => s.dateTime.hour == 10).isAvailable, isTrue);
    });

    test('FirestoreChatRepository sanitizes contact details, streams messages and handles reactions', () async {
      final repo = FirestoreChatRepository(firestore: fakeDb);

      expect(
        FirestoreChatRepository.sanitizeMessageText('Llámame al 612345678 o escribe a test@mail.com'),
        contains('[Contacto bloqueado hasta confirmar reserva]'),
      );

      await repo.sendMessage(
        'client_a',
        'cg_a',
        'Carlos Cuidador',
        ChatMessage(
          sender: ChatSender.Client,
          senderId: 'client_a',
          text: 'Mi correo es hola@ejemplo.com',
          timestamp: DateTime(2026, 11, 12, 10),
        ),
        clientName: 'Familia Pérez',
        allowContactSharing: false,
      );

      final messages = await repo.streamMessages('client_a', 'cg_a').first;
      expect(messages.length, 1);
      expect(messages.first.text, 'Mi correo es [Contacto bloqueado hasta confirmar reserva]');

      final activeChats = await repo.streamActiveChats('client_a', 'client').first;
      expect(activeChats.length, 1);
      expect(activeChats.first.caregiverName, 'Carlos Cuidador');

      await repo.toggleReaction('client_a', 'cg_a', messages.first.id, 'cg_a', '❤️');
      await repo.resetUnreadCount('client_a', 'cg_a', 'caregiver');
      await repo.deleteMessageForEveryone('client_a', 'cg_a', messages.first.id);

      final afterDelete = await repo.streamMessages('client_a', 'cg_a').first;
      expect(afterDelete.first.isDeleted, isTrue);
    });

    test('FirestoreClientRepository caches profiles and invalidates on update', () async {
      await fakeDb.collection('clients').doc('cli_1').set({
        'name': 'Familia Gómez',
        'phone': '600111222',
        'homeAddress': 'Calle Mayor 1',
        'patientDetails': 'Movilidad reducida',
        'onboardingComplete': true,
      });

      final repo = FirestoreClientRepository(firestore: fakeDb);
      final first = await repo.getClient('cli_1');
      expect(first?.name, 'Familia Gómez');

      // Direct DB edit stays invisible until cache invalidation
      await fakeDb.collection('clients').doc('cli_1').update({'name': 'Familia Gómez Updated'});
      final cached = await repo.getClient('cli_1');
      expect(cached?.name, 'Familia Gómez');

      repo.invalidateCache('cli_1');
      final fresh = await repo.getClient('cli_1');
      expect(fresh?.name, 'Familia Gómez Updated');

      await repo.updateClient('cli_1', {'phone': '699000111'});
      final afterUpdate = await repo.getClient('cli_1');
      expect(afterUpdate?.phone, '699000111');
    });

    test('FirestoreFamilyRepository resolves active family and tracks tutorial flags', () async {
      await fakeDb.collection('clients').doc('fam_1').set({
        'name': 'Familia Ruiz',
        'phone': '600222333',
        'homeAddress': 'Av. Diagonal 10',
        'patientDetails': 'Cuidado diario',
        'onboardingComplete': true,
        'ownerUid': 'fam_1',
        'memberUids': ['fam_1', 'member_2'],
      });
      await fakeDb.collection('users').doc('member_2').set({'activeFamilyId': 'fam_1'});

      final repo = FirestoreFamilyRepository(firestore: fakeDb);
      expect(await repo.resolveActiveFamilyId(uid: 'member_2'), 'fam_1');
      expect(await repo.resolveActiveFamilyId(uid: 'fam_1'), 'fam_1');

      await repo.inviteByEmail(familyId: 'fam_1', email: 'hija@familia.es', role: FamilyRole.collaborator);
      var famDoc = await fakeDb.collection('clients').doc('fam_1').get();
      expect(famDoc.data()?['authorizedFamilyEmails'], contains('hija@familia.es'));

      await repo.removeEmailInvite(familyId: 'fam_1', email: 'hija@familia.es');
      famDoc = await fakeDb.collection('clients').doc('fam_1').get();
      expect(famDoc.data()?['authorizedFamilyEmails'], isNot(contains('hija@familia.es')));

      expect(await repo.hasSeenMemberTutorial('member_2'), isFalse);
      await repo.markMemberTutorialSeen('member_2');
      expect(await repo.hasSeenMemberTutorial('member_2'), isTrue);
    });

    test('FirestoreJobOfferRepository creates offers, filters nearby and manages applications', () async {
      final repo = FirestoreJobOfferRepository(firestore: fakeDb);
      final offer = JobOffer(
        id: '',
        clientId: 'cli_1',
        clientName: 'Familia Torres',
        clientLatitude: 41.3851,
        clientLongitude: 2.1734,
        title: 'Acompañamiento mañana',
        description: 'Paseo y medicación',
        pricePerHour: 16.0,
        totalHours: 4,
        isRecurring: false,
        startDate: DateTime(2026, 11, 22),
        isUrgent: false,
        urgencyBonusRate: 0.0,
        createdAt: DateTime(2026, 11, 12),
      );

      final offerId = await repo.createOffer(offer);
      expect(offerId, isNotEmpty);

      final clientOffers = await repo.streamClientOffers('cli_1').first;
      expect(clientOffers.length, 1);

      final nearby = await repo.streamNearbyOffers(41.39, 2.17, 15.0).first;
      expect(nearby.length, 1);

      final farAway = await repo.streamNearbyOffers(40.4168, -3.7038, 10.0).first;
      expect(farAway, isEmpty);

      await repo.applyToOffer(JobApplication(
        id: 'cg_app_1',
        offerId: offerId,
        caregiverId: 'cg_app_1',
        caregiverName: 'Elena Cuidadora',
        caregiverImageUrl: '',
        caregiverRating: 4.8,
        caregiverReviewsCount: 5,
        message: 'Disponible',
        proposedPrice: 16.0,
        appliedAt: DateTime(2026, 11, 12),
      ));

      final apps = await repo.streamOfferApplications(offerId).first;
      expect(apps.length, 1);
      expect(apps.first.proposedPrice, 16.0);

      await repo.updateApplicationDetails(offerId, 'cg_app_1', message: 'Mensaje editado', proposedPrice: 17.5);
      final updatedApps = await repo.streamOfferApplications(offerId).first;
      expect(updatedApps.first.proposedPrice, 17.5);

      await repo.withdrawApplication(offerId, 'cg_app_1', 'cg_app_1');
      final afterWithdraw = await repo.streamOfferApplications(offerId).first;
      expect(afterWithdraw, isEmpty);
    });

    test('FirestoreReportRepository persists incident reports', () async {
      final repo = FirestoreReportRepository(firestore: fakeDb);
      await repo.addReport(Report(
        id: 'rep_1',
        reporterId: 'cli_1',
        reportedId: 'cg_1',
        bookingId: 'bk_1',
        reason: 'Retraso grave',
        description: 'Llegó 40 minutos tarde sin aviso.',
      ));

      final doc = await fakeDb.collection('reports').doc('rep_1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['reason'], 'Retraso grave');
    });

    test('FirestoreReviewRepository writes and paginates reviews cleanly', () async {
      final repo = FirestoreReviewRepository(firestore: fakeDb);
      await repo.addReview(
        'cg_rev_1',
        Review(
          id: 'rev_1',
          caregiverId: 'cg_rev_1',
          clientId: 'cli_1',
          clientName: 'Marta',
          bookingId: 'bk_rev_1',
          rating: 5.0,
          punctualityRating: 5.0,
          comment: 'Trato excelente',
          createdAt: DateTime(2026, 11, 12),
        ),
      );

      final reviews = await repo.fetchReviewsForCaregiver('cg_rev_1', limit: 10, refresh: true);
      expect(reviews.length, 1);
      expect(reviews.first.comment, 'Trato excelente');
    });

    test('FirestoreStatsRepository implements StatsRepository, increments hours and tiers commission', () async {
      final StatsRepository repo = FirestoreStatsRepository(firestore: fakeDb);
      expect(await repo.getAccumulatedHours('cli_1', 'cg_1'), 0);

      await repo.addCompletedHours('cli_1', 'cg_1', 12);
      expect(await repo.getAccumulatedHours('cli_1', 'cg_1'), 12);

      await repo.addCompletedHours('cli_1', 'cg_1', 15);
      expect(await repo.getAccumulatedHours('cli_1', 'cg_1'), 27);

      final statsList = await repo.getCaregiverClientStats('cg_1');
      expect(statsList.length, 1);
      expect(statsList.first['accumulatedHours'], 27);

      expect(FirestoreStatsRepository.calculateCommissionRate(10), 0.18);
      expect(FirestoreStatsRepository.calculateCommissionRate(25), 0.12);
      expect(FirestoreStatsRepository.calculateCommissionRate(90), 0.06);
    });
  });
}
