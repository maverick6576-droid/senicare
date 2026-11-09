import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockCaregiverRepository implements CaregiverRepository {
  final List<CaregiverProfile> _mockCaregivers = [
    CaregiverProfile(
      id: 'c1',
      name: 'Elena Sanz',
      title: 'Enfermera Geriátrica',
      bio: 'Especialista en movilidad y cuidados post-operatorios con más de 10 años de experiencia. Apasionada por el bienestar emocional de los mayores.',
      pricePerHour: 18.0,
      rating: 4.9,
      reviewsCount: 124,
      distance: '2.5 km',
      latitude: 41.3888,
      longitude: 2.15899,
      imageUrl: 'https://i.pravatar.cc/300?img=47',
      specialties: ['Movilidad', 'Cocina Médica'],
      verified: true,
      verificationStatus: 'approved',
      maxDistanceRadius: 2.0,
      homeAddress: 'Carrer de Mallorca, 401, Barcelona',
      availableSlots: {
        'Lunes': ['09:00', '10:00', '16:00'],
        'Martes': ['10:00', '11:00'],
      },
    ),
    CaregiverProfile(
      id: 'c2',
      name: 'Javier Domínguez',
      title: 'Acompañante y Soporte Digital',
      bio: 'Ayudo a tus mayores a conectar con la familia usando tecnología, además de ofrecer una cálida compañía y paseos diarios.',
      pricePerHour: 15.0,
      rating: 4.7,
      reviewsCount: 89,
      distance: '4.1 km',
      latitude: 41.4036,
      longitude: 2.1744,
      imageUrl: 'https://i.pravatar.cc/300?img=11',
      specialties: ['Compañía', 'Soporte Digital'],
      verified: true,
      verificationStatus: 'approved',
      maxDistanceRadius: 5.0,
      homeAddress: 'Carrer de la Marina, 253, Barcelona',
      availableSlots: {
        'Miércoles': ['15:00', '16:00', '17:00'],
        'Jueves': ['09:00', '12:00'],
      },
    ),
    CaregiverProfile(
      id: 'c3',
      name: 'María Fernández',
      title: 'Cuidadora Especializada',
      bio: 'Enfermera titulada. Cuidados nocturnos, control de medicación y alimentación específica. Experiencia en Alzheimer.',
      pricePerHour: 22.0,
      rating: 5.0,
      reviewsCount: 201,
      distance: '1.2 km',
      latitude: 41.3784,
      longitude: 2.1925,
      imageUrl: 'https://i.pravatar.cc/300?img=43',
      specialties: ['Movilidad', 'Cocina Médica', 'Compañía'],
      verified: true,
      verificationStatus: 'approved',
      maxDistanceRadius: 20.0,
      homeAddress: 'Avinguda Diagonal, 593, Barcelona',
      availableSlots: {
        'Viernes': ['20:00', '21:00'],
        'Sábado': ['08:00', '09:00'],
      },
    ),
  ];

  @override
  Future<List<CaregiverProfile>> fetchCaregivers({String specialty = 'Todos', String query = '', bool refresh = false, double? mapLat, double? mapLng}) async {
    return _mockCaregivers.where((c) {
      if (c.verificationStatus != 'approved') return false;
      
      final matchesSpecialty = specialty == 'Todos' || c.specialties.contains(specialty);
      final matchesSearch = c.name.toLowerCase().contains(query.toLowerCase()) || 
                            c.title.toLowerCase().contains(query.toLowerCase());
      return matchesSpecialty && matchesSearch;
    }).toList();
  }

  @override
  Future<void> updateCaregiverAvailability(String id, String day, List<String> hours) async {
    final idx = _mockCaregivers.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _mockCaregivers[idx].availableSlots[day] = hours;
    }
  }

  @override
  Future<CaregiverProfile?> getCaregiver(String id) async {
    try {
      return _mockCaregivers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    final index = _mockCaregivers.indexWhere((c) => c.id == id);
    if (index != -1) {
      final old = _mockCaregivers[index];
      _mockCaregivers[index] = CaregiverProfile(
        id: old.id,
        name: data['name'] ?? old.name,
        title: old.title,
        bio: data['bio'] ?? old.bio,
        pricePerHour: (data['pricePerHour'] ?? old.pricePerHour).toDouble(),
        rating: old.rating,
        reviewsCount: old.reviewsCount,
        distance: old.distance,
        latitude: data['latitude'] ?? old.latitude,
        longitude: data['longitude'] ?? old.longitude,
        imageUrl: data['imageUrl'] ?? old.imageUrl,
        specialties: data['specialties'] != null ? List<String>.from(data['specialties']) : old.specialties,
        verified: data['isVerified'] ?? data['verified'] ?? old.verified,
        maxDistanceRadius: (data['maxDistanceRadius'] ?? old.maxDistanceRadius).toDouble(),
        homeAddress: data['homeAddress'] ?? old.homeAddress,
        availableSlots: old.availableSlots,
        dniUrl: data['dniUrl'] ?? old.dniUrl,
        criminalRecordUrl: data['criminalRecordUrl'] ?? old.criminalRecordUrl,
        verificationStatus: data['verificationStatus'] ?? old.verificationStatus,
        stripeAccountId: data['stripeAccountId'] ?? old.stripeAccountId,
        onboardingComplete: data['onboardingComplete'] ?? old.onboardingComplete,
        isKycVerified: data['isKycVerified'] ?? old.isKycVerified,
      );
    } else {
      _mockCaregivers.add(CaregiverProfile(
        id: id,
        name: data['name'] ?? 'Sin nombre',
        title: 'Cuidador',
        bio: data['bio'] ?? '',
        pricePerHour: (data['pricePerHour'] ?? 15.0).toDouble(),
        rating: 0.0,
        reviewsCount: 0,
        distance: 'A calcular',
        imageUrl: data['imageUrl'] ?? '',
        specialties: data['specialties'] != null ? List<String>.from(data['specialties']) : [],
        verified: data['isVerified'] ?? data['verified'] ?? false,
        maxDistanceRadius: (data['maxDistanceRadius'] ?? 10.0).toDouble(),
        homeAddress: data['homeAddress'] ?? '',
        availableSlots: {},
        dniUrl: data['dniUrl'] ?? '',
        criminalRecordUrl: data['criminalRecordUrl'] ?? '',
        verificationStatus: data['verificationStatus'] ?? 'pending',
        stripeAccountId: data['stripeAccountId'],
        onboardingComplete: data['onboardingComplete'] ?? false,
        isKycVerified: data['isKycVerified'] ?? false,
      ));
    }
  }

  static final Map<String, Map<String, List<TimeSlot>>> _mockTimeSlots = {};

  @override
  Future<List<TimeSlot>> fetchTimeSlots(String caregiverId, String date) async {
    if (!_mockTimeSlots.containsKey(caregiverId)) {
      _mockTimeSlots[caregiverId] = {};
    }
    if (!_mockTimeSlots[caregiverId]!.containsKey(date)) {
      List<TimeSlot> defaultSlots = [];
      for (int i = 9; i <= 17; i++) {
        final hourString = '${i.toString().padLeft(2, '0')}:00';
        defaultSlots.add(TimeSlot(
          id: '${date}_$hourString',
          dateTime: DateTime.parse('${date}T$hourString:00'),
          isAvailable: true,
        ));
      }
      _mockTimeSlots[caregiverId]![date] = defaultSlots;
    }
    return _mockTimeSlots[caregiverId]![date]!;
  }

  @override
  Future<void> updateTimeSlot(String caregiverId, String date, TimeSlot slot) async {
    final slots = await fetchTimeSlots(caregiverId, date);
    final idx = slots.indexWhere((s) => s.id == slot.id);
    if (idx != -1) {
      slots[idx] = slot;
    } else {
      slots.add(slot);
      slots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
  }

  @override
  Future<void> setBatchTimeSlots(String caregiverId, String date, List<TimeSlot> slots) async {
    if (!_mockTimeSlots.containsKey(caregiverId)) {
      _mockTimeSlots[caregiverId] = {};
    }
    final sorted = List<TimeSlot>.from(slots)
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    _mockTimeSlots[caregiverId]![date] = sorted;
  }

  @override
  Future<void> clearDaySlots(String caregiverId, String date) async {
    _mockTimeSlots[caregiverId]?.remove(date);
  }
}

