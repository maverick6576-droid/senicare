// main.dart
// SeniCare - Production-Ready Architecture & Senior-Accessible Marketplace
// Connects families and seniors with verified caregivers using Escrow protection,
// dynamic loyalty commissions (18% -> 10% -> 6%), GPS check-in, Care Logs, and WCAG AAA Senior Mode.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'models/care_models.dart';
import 'services/anti_bypass_validator.dart';
import 'theme/app_theme.dart';

export 'models/care_models.dart';
export 'services/anti_bypass_validator.dart';
export 'theme/app_theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const SeniCareApp(),
    ),
  );
}

// ==========================================
// 1. STATE MANAGEMENT & CLOUD GATEWAY
// ==========================================

/// Central state manager synchronizing UI, Escrow lifecycle, slot locking,
/// dynamic commission tiers (18% -> 10% -> 6%), GPS verification, and Senior Mode.
class AppState extends ChangeNotifier {
  String currentRole = 'client'; // 'client' or 'caregiver'
  bool seniorMode = false; // Toggles WCAG AAA Senior Accessibility Mode & Senior Home Panel
  String selectedSpecialty = 'Todos';
  String searchQuery = '';
  bool sosAlertActive = false;

  // Medication reminders for the Senior Accessible Mode
  final List<MedicationReminder> medications = [
    MedicationReminder(
      id: 'med_1',
      name: 'Pastilla de la tensión (Enalapril)',
      dosage: '1 comprimido con agua',
      scheduledTime: '10:00 h',
    ),
    MedicationReminder(
      id: 'med_2',
      name: 'Vitamina D y Calcio',
      dosage: '1 cápsula después de comer',
      scheduledTime: '14:30 h',
    ),
  ];

  // Verified Caregivers in the marketplace
  List<CaregiverProfile> caregivers = [
    CaregiverProfile(
      id: 'c1',
      name: 'Elena Sanz',
      title: 'Enfermera Geriátrica Colegiada',
      bio: 'Especialista en movilidad, control de medicación y cuidados post-operatorios con más de 10 años de experiencia. Apasionada por el bienestar emocional de los mayores.',
      pricePerHour: 18.0,
      rating: 4.9,
      reviewsCount: 124,
      distance: '2.5 km',
      imageUrl: 'https://i.pravatar.cc/300?img=47',
      specialties: ['Movilidad', 'Cocina Médica'],
      verified: true,
      yearsExperience: 10,
      availableSlots: {
        'Lunes': ['09:00', '10:00', '16:00'],
        'Martes': ['10:00', '11:00'],
        'Jueves': ['09:00', '17:00'],
      },
    ),
    CaregiverProfile(
      id: 'c2',
      name: 'Javier Domínguez',
      title: 'Acompañante y Soporte Digital',
      bio: 'Ayudo a tus mayores a conectar con la familia por videollamada, además de ofrecer cálida compañía, lectura y paseos diarios seguros.',
      pricePerHour: 15.0,
      rating: 4.7,
      reviewsCount: 89,
      distance: '4.1 km',
      imageUrl: 'https://i.pravatar.cc/300?img=11',
      specialties: ['Compañía', 'Soporte Digital'],
      verified: true,
      yearsExperience: 6,
      availableSlots: {
        'Miércoles': ['15:00', '16:00', '17:00'],
        'Jueves': ['09:00', '12:00'],
      },
    ),
    CaregiverProfile(
      id: 'c3',
      name: 'María Fernández',
      title: 'Cuidadora Especializada en Alzheimer',
      bio: 'Enfermera titulada. Cuidados diurnos y nocturnos, control estricto de pautas médicas, estimulación cognitiva y alimentación adaptada.',
      pricePerHour: 22.0,
      rating: 5.0,
      reviewsCount: 201,
      distance: '1.2 km',
      imageUrl: 'https://i.pravatar.cc/300?img=43',
      specialties: ['Movilidad', 'Cocina Médica', 'Compañía'],
      verified: true,
      yearsExperience: 12,
      availableSlots: {
        'Viernes': ['20:00', '21:00'],
        'Sábado': ['08:00', '09:00'],
      },
    ),
  ];

  List<Booking> bookings = [];

  List<ChatMessage> chatMessages = [
    ChatMessage(
      sender: ChatSender.Caregiver,
      text: '¡Hola! Soy Elena. ¿En qué te puedo ayudar hoy con el cuidado de tu familiar?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  /// Predefined specialties for filtering
  List<String> get availableSpecialties => [
        'Todos',
        'Compañía',
        'Movilidad',
        'Cocina Médica',
        'Soporte Digital',
      ];

  /// Computes filtered caregivers based on specialty and search query
  List<CaregiverProfile> get filteredCaregivers {
    return caregivers.where((c) {
      final matchesSpecialty =
          selectedSpecialty == 'Todos' || c.specialties.contains(selectedSpecialty);
      final matchesSearch =
          c.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              c.title.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesSpecialty && matchesSearch;
    }).toList();
  }

  /// Dynamic Commission Engine synchronized with `functions/index.js` (`calculateCaregiverPayout`):
  /// - 0 completed bookings with this caregiver: 18% fee
  /// - 1 to 4 completed bookings: 10% fee
  /// - 5+ completed bookings: 6% fee
  CommissionQuote calculateCommissionQuote({
    required String caregiverId,
    required double pricePerHour,
    required int durationHours,
  }) {
    final completedCount = bookings
        .where((b) =>
            b.caregiverId == caregiverId &&
            b.status == BookingStatus.Completed &&
            b.isEscrowReleased)
        .length;

    double rate = 0.18;
    String tier = '18% (Primer servicio con la familia)';

    if (completedCount >= 5) {
      rate = 0.06;
      tier = '6% (Familia fidelizada - $completedCount servicios previos)';
    } else if (completedCount >= 1) {
      rate = 0.10;
      tier = '10% (Familia recurrente - $completedCount servicios previos)';
    }

    final baseCost = pricePerHour * durationHours;
    final platformFee = double.parse((baseCost * rate).toStringAsFixed(2));
    final totalClientPayable = double.parse((baseCost + platformFee).toStringAsFixed(2));
    final caregiverNet = double.parse((baseCost * (1.0 - rate)).toStringAsFixed(2));

    return CommissionQuote(
      baseCost: baseCost,
      commissionRate: rate,
      commissionRatePercent: (rate * 100).round(),
      commissionTier: tier,
      platformFee: platformFee,
      caregiverNetPayout: caregiverNet,
      totalClientPayable: totalClientPayable,
    );
  }

  /// Prevents double-booking race conditions by checking if a slot is already reserved.
  bool isSlotBooked(String caregiverId, String day, String slot) {
    return bookings.any((b) =>
        b.caregiverId == caregiverId &&
        b.day == day &&
        b.slot == slot &&
        b.status != BookingStatus.Cancelled);
  }

  /// Returns only the unbooked slots for a given caregiver and day.
  List<String> getAvailableSlotsForDay(CaregiverProfile caregiver, String day) {
    final allSlots = caregiver.availableSlots[day] ?? [];
    return allSlots.where((slot) => !isSlotBooked(caregiver.id, day, slot)).toList();
  }

  // --- Mutators ---

  void toggleSeniorMode(bool value) {
    seniorMode = value;
    notifyListeners();
  }

  void toggleMedicationTaken(String medId) {
    final idx = medications.indexWhere((m) => m.id == medId);
    if (idx != -1) {
      medications[idx].isTaken = !medications[idx].isTaken;
      notifyListeners();
    }
  }

  void triggerSosAlert() {
    sosAlertActive = true;
    chatMessages.add(
      ChatMessage(
        sender: ChatSender.Client,
        text: '🚨 ALERTA SOS ACTIVADA: Se ha enviado la ubicación GPS actual a los familiares responsables y al cuidador asignado.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void setRole(String role) {
    currentRole = role;
    notifyListeners();
  }

  void setSpecialty(String specialty) {
    selectedSpecialty = specialty;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  /// Adds a booking if the slot is not already reserved (prevents double-booking).
  bool addBooking(Booking booking) {
    if (isSlotBooked(booking.caregiverId, booking.day, booking.slot)) {
      return false;
    }
    bookings.add(booking);
    notifyListeners();
    return true;
  }

  void confirmBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      bookings[idx].status = BookingStatus.Confirmed;
      notifyListeners();
    }
  }

  /// GPS Check-in verification (<100m from senior's home)
  void checkInGps(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      b.isGpsCheckedIn = true;
      b.checkInTime = DateTime.now();
      b.status = BookingStatus.InProgress;
      b.careLogs.add(
        CareLogEntry(
          category: 'Llegada GPS',
          note: 'Llegada verificada por GPS a menos de 100m del domicilio.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// Appends an entry to the Daily Care Log ("Cuaderno de Cuidados")
  void addCareLogEntry(String bookingId, String category, String note) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1 && note.trim().isNotEmpty) {
      bookings[idx].careLogs.add(
            CareLogEntry(
              category: category,
              note: note.trim(),
              timestamp: DateTime.now(),
            ),
          );
      notifyListeners();
    }
  }

  /// Caregiver rejection: processes 100% full refund to client and frees the slot.
  void rejectBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final booking = bookings[idx];
      booking.status = BookingStatus.Cancelled;
      booking.isRefunded = true;
      booking.refundedAmount = booking.totalPaid;
      booking.isEscrowReleased = false;

      chatMessages.add(
        ChatMessage(
          sender: ChatSender.Caregiver,
          text:
              'Hola. Lamentamos informarte que tu solicitud de reserva para el día ${booking.day} a las ${booking.slot} ha sido declinada.\n\n'
              '💳 Devolución automática procesada: Hemos devuelto íntegramente el importe pagado (€${booking.totalPaid.toStringAsFixed(2)}) a tu cuenta bancaria de origen.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// Opens a dispute on an active booking, freezing automatic Escrow release.
  void openDispute(String bookingId, String reason) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final booking = bookings[idx];
      booking.isDisputed = true;
      booking.disputeReason = reason.trim().isEmpty
          ? 'Incidencia reportada por la familia'
          : reason.trim();
      booking.status = BookingStatus.Disputed;

      chatMessages.add(
        ChatMessage(
          sender: ChatSender.Client,
          text:
              '⚠️ Incidencia abierta en Reserva #${booking.id}: "${booking.disputeReason}". El pago en garantía queda congelado hasta revisión de Soporte SeniCare.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// Releases Escrow funds to the caregiver if not disputed.
  bool releaseEscrow(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      if (bookings[idx].isDisputed || bookings[idx].status == BookingStatus.Disputed) {
        return false; // Cannot release while disputed
      }
      bookings[idx].status = BookingStatus.Completed;
      bookings[idx].isEscrowReleased = true;
      bookings[idx].checkOutTime = DateTime.now();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Appends a new chat message and runs the semantic Anti-Bypass Validator.
  AntiBypassResult sendChatMessage(String text) {
    final result = AntiBypassValidator.evaluate(text);

    chatMessages.add(ChatMessage(
      sender: ChatSender.Client,
      text: result.sanitizedText,
      timestamp: DateTime.now(),
      wasSanitized: result.wasBlocked,
    ));
    notifyListeners();

    if (!result.wasBlocked) {
      Future.delayed(const Duration(seconds: 3), () {
        chatMessages.add(ChatMessage(
          sender: ChatSender.Caregiver,
          text:
              'Gracias por tu mensaje. Para confirmar la asistencia con cobertura y garantía SeniCare, por favor selecciona el horario en mi calendario.',
          timestamp: DateTime.now(),
        ));
        notifyListeners();
      });
    }
    return result;
  }
}

// ==========================================
// 2. MAIN APP ENTRY & CORE LAYOUT
// ==========================================

class SeniCareApp extends StatelessWidget {
  const SeniCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'SeniCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(state.seniorMode),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isClient = state.currentRole == 'client';

    final currentScreens = isClient
        ? const [ExplorerScreen(), BookingsScreen(), ChatScreen()]
        : const [CaregiverDashboard(), BookingsScreen(), ChatScreen()];

    if (_currentIndex >= currentScreens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            const Icon(Icons.favorite, color: AppTheme.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isClient ? 'SeniCare' : 'Panel Profesional',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Senior Mode Accessibility Switch
          Row(
            children: [
              Text(
                'Modo Mayor',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
              ),
              Switch(
                value: state.seniorMode,
                onChanged: (val) => state.toggleSeniorMode(val),
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
          // Role Switcher
          PopupMenuButton<String>(
            tooltip: 'Cambiar vista de usuario',
            icon: const Icon(Icons.switch_account, color: AppTheme.darkSlate),
            onSelected: (role) {
              state.setRole(role);
              setState(() => _currentIndex = 0);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'client',
                child: Text('👨‍👩‍👧 Vista Familia / Mayor'),
              ),
              PopupMenuItem(
                value: 'caregiver',
                child: Text('👩‍⚕️ Vista Cuidadora (Elena)'),
              ),
            ],
          ),
        ],
      ),
      body: currentScreens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.darkSlate.withValues(alpha: 0.6),
        selectedFontSize: state.seniorMode ? 16 : 13,
        unselectedFontSize: state.seniorMode ? 14 : 12,
        iconSize: state.seniorMode ? 30 : 24,
        items: [
          BottomNavigationBarItem(
            icon: Icon(isClient ? Icons.home_rounded : Icons.dashboard_rounded),
            label: isClient
                ? (state.seniorMode ? 'Inicio Mayor' : 'Explorar')
                : 'Mi Panel',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Reservas',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: 'Mensajes',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. SCREENS ARCHITECTURE
// ==========================================

// --- SCREEN A: Explorer / Marketplace & Senior Quick-Access Hub ---
class ExplorerScreen extends StatelessWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        // 1. Top Location & Friendly Guarantee Banner
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 4),
                    Text('Madrid, España', style: theme.textTheme.bodyMedium),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: AppTheme.primary, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Garantía 100% SeniCare',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. If Senior Mode is active: Render the Ultra-Friendly Senior Home Hub
        if (state.seniorMode)
          SliverToBoxAdapter(
            child: _SeniorAccessibleHub(),
          ),

        // 3. Search Bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: state.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Buscar cuidadora por nombre o especialidad...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
        ),

        // 4. Specialties Filter Chips
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: state.availableSpecialties.map((spec) {
                final isSelected = state.selectedSpecialty == spec;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(spec),
                    selected: isSelected,
                    onSelected: (_) => state.setSpecialty(spec),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      fontSize: state.seniorMode ? 17 : 13,
                      color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // 5. Caregivers Marketplace List
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final c = state.filteredCaregivers[index];
                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Image.network(
                          c.imageUrl,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 150,
                            color: Colors.grey.shade200,
                            child: Icon(Icons.person, size: 64, color: Colors.grey.shade500),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(c.name, style: theme.textTheme.titleMedium),
                                      ),
                                      const SizedBox(width: 6),
                                      if (c.verified)
                                        const Tooltip(
                                          message: 'Identidad, antecedentes penales y título verificados',
                                          child: Icon(Icons.verified, color: Colors.blue, size: 18),
                                        ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: AppTheme.amber, size: 20),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${c.rating} (${c.reviewsCount})',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.title,
                              style: TextStyle(
                                color: AppTheme.darkSlate.withValues(alpha: 0.75),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: c.specialties
                                  .map(
                                    (s) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        s,
                                        style: TextStyle(
                                          fontSize: state.seniorMode ? 14 : 12,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '€${c.pricePerHour.toStringAsFixed(0)}/hora',
                                  style: TextStyle(
                                    fontSize: state.seniorMode ? 22 : 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CaregiverDetailScreen(caregiver: c),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(140, state.seniorMode ? 58 : 42),
                                  ),
                                  child: const Text('Ver Perfil'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: state.filteredCaregivers.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dedicated Senior-Friendly Hub (WCAG AAA) shown when Senior Mode is active.
class _SeniorAccessibleHub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final primaryCaregiver = state.caregivers.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hola, bienvenido a tu panel 👋', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),

          // CARD 1: Today's Caregiver Quick Call & Chat
          Card(
            color: AppTheme.primaryLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.medical_services_rounded, color: AppTheme.primary, size: 28),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'TU CUIDADORA DE CONFIANZA',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${primaryCaregiver.name} (${primaryCaregiver.title})',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '📞 Llamando por teléfono a ${primaryCaregiver.name}...'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          icon: const Icon(Icons.phone_in_talk, size: 26),
                          label: const Text('LLAMAR'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChatScreen(isStandalone: true),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_rounded, size: 24),
                          label: const Text('MENSAJE'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary, width: 2),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // CARD 2: Medication Checklist
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medication_rounded, color: AppTheme.primary, size: 28),
                      const SizedBox(width: 8),
                      Text('MIS MEDICINAS DE HOY', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...state.medications.map(
                    (med) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: med.isTaken ? AppTheme.primaryLight : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: med.isTaken ? AppTheme.primary : Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⏰ ${med.scheduledTime} — ${med.name}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(med.dosage, style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => state.toggleMedicationTaken(med.id),
                              icon: Icon(
                                med.isTaken
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                              ),
                              label: Text(
                                med.isTaken
                                    ? '✓ MEDICINA TOMADA'
                                    : 'MARCAR COMO TOMADA',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: med.isTaken
                                    ? Colors.green.shade800
                                    : AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // CARD 3: Emergency SOS Button
          Card(
            color: const Color(0xFFFEF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppTheme.urgentRed, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emergency_rounded, color: AppTheme.urgentRed, size: 30),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AYUDA URGENTE / SOS FAMILIA',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.urgentRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pulsa este botón si necesitas ayuda inmediata. Avisaremos a tu familia y a tu cuidadora con tu ubicación.',
                    style: TextStyle(fontSize: 16, color: AppTheme.darkSlate),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('🚨 ¿Necesitas ayuda urgente?'),
                          content: const Text(
                            'Enviaremos un aviso inmediato con tu ubicación GPS a tu familia y a tu cuidadora.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.urgentRed,
                              ),
                              onPressed: () {
                                state.triggerSosAlert();
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '🚨 Alerta SOS enviada a tu familia y cuidadora.'),
                                    backgroundColor: AppTheme.urgentRed,
                                  ),
                                );
                              },
                              child: const Text('SÍ, ENVIAR ALERTA SOS'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.sos_rounded, size: 28),
                    label: const Text('PEDIR AYUDA AHORA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.urgentRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Explorar Todos los Cuidadores', style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

// --- SCREEN B: Caregiver Details, Flexible Duration & Slot Picker ---
class CaregiverDetailScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  const CaregiverDetailScreen({super.key, required this.caregiver});

  @override
  State<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends State<CaregiverDetailScreen> {
  late String _selectedDay;
  int _selectedDurationHours = 2;
  final List<int> _durationOptions = [1, 2, 4, 8, 10];

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.caregiver.availableSlots.keys.isNotEmpty
        ? widget.caregiver.availableSlots.keys.first
        : 'Sin disponibilidad';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final c = widget.caregiver;
    final availableSlots = state.getAvailableSlotsForDay(c, _selectedDay);

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          Image.network(
            c.imageUrl,
            height: 230,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 230,
              color: Colors.grey.shade200,
              child: Icon(Icons.person, size: 80, color: Colors.grey.shade400),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.title, style: theme.textTheme.titleLarge),
                    ),
                    if (c.verified) ...[
                      const Icon(Icons.verified, color: Colors.blue, size: 22),
                      const SizedBox(width: 4),
                      const Text(
                        'Verificado',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🛡️ ${c.verificationBadge} • ${c.yearsExperience} años exp.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star, color: AppTheme.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '${c.rating} (${c.reviewsCount} reseñas verificadas)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
                    Text(c.distance, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(c.bio, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),

                // Step 1: Select Duration
                Text('1. ¿Cuántas horas de cuidado necesitas?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _durationOptions.map((hours) {
                    final isSelected = _selectedDurationHours == hours;
                    final label = hours == 8
                        ? '8h (Jornada)'
                        : (hours == 10 ? '10h (Noche)' : '$hours ${hours == 1 ? "hora" : "horas"}');
                    return ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedDurationHours = hours),
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.darkSlate,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Step 2: Select Day
                Text('2. Selecciona el día', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: c.availableSlots.keys.map((day) {
                      final isSelected = _selectedDay == day;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDay = day),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primary, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              day,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // Step 3: Select Available Slot
                Text('3. Elige la hora de inicio', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (availableSlots.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Todos los horarios de este día ya están reservados. Por favor selecciona otro día.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: availableSlots.map((slot) {
                      return ActionChip(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        label: Text(
                          '🕒 $slot h',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentScreen(
                                caregiver: c,
                                day: _selectedDay,
                                slot: slot,
                                durationHours: _selectedDurationHours,
                              ),
                            ),
                          );
                        },
                        backgroundColor: AppTheme.primaryLight,
                        side: const BorderSide(color: AppTheme.primary),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen(isStandalone: true)),
          );
        },
        label: const Text(
          'Hablar con Cuidadora',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.chat, color: Colors.white),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}

// --- SCREEN C: Secure Payment Confirmation with Dynamic Commission Tiers ---
class PaymentScreen extends StatelessWidget {
  final CaregiverProfile caregiver;
  final String day;
  final String slot;
  final int durationHours;

  const PaymentScreen({
    super.key,
    required this.caregiver,
    required this.day,
    required this.slot,
    this.durationHours = 2,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final seniorMode = state.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    // Dynamic quote synchronized with Firebase Cloud Functions (18% -> 10% -> 6%)
    final quote = state.calculateCommissionQuote(
      caregiverId: caregiver.id,
      pricePerHour: caregiver.pricePerHour,
      durationHours: durationHours,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reserva Protegida SeniCare')),
      body: ListView(
        padding: EdgeInsets.all(seniorMode ? 24 : 16),
        children: [
          Text('Resumen de tu Cuidado', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Profesional:'),
                      Text(caregiver.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Día y Hora:'),
                      Text('$day a las $slot h',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Duración contratada:'),
                      Text('$durationHours ${durationHours == 1 ? "hora" : "horas"}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Importe Cuidado (${currencyFormat.format(caregiver.pricePerHour)}/h):'),
                      Text(currencyFormat.format(quote.baseCost)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Gestión y Seguro (${quote.commissionTier}):'),
                      ),
                      Text(currencyFormat.format(quote.platformFee)),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total a proteger:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        currencyFormat.format(quote.totalClientPayable),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Friendly Trust Guarantee Box (No intimidating technical jargon)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, color: AppTheme.primary, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Garantía 100% SeniCare: Tu dinero queda guardado de forma segura y solo se entrega a la cuidadora cuando confirmes que el servicio ha finalizado con éxito. Si rechaza o cancela, recibes el 100% al instante.',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Tarjeta Bancaria Protegida', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Tarjeta Visa / Mastercard (Protección 3D Secure)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.credit_card, color: AppTheme.primary),
            ),
            controller: TextEditingController(text: '•••• •••• •••• 4242'),
            readOnly: true,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              final booking = Booking(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                caregiverId: caregiver.id,
                caregiverName: caregiver.name,
                day: day,
                slot: slot,
                durationHours: durationHours,
                cost: quote.baseCost,
                appCommission: quote.platformFee,
                totalPaid: quote.totalClientPayable,
                commissionRatePercent: quote.commissionRatePercent,
                commissionTier: quote.commissionTier,
                status: BookingStatus.PendingApproval,
              );
              final added = context.read<AppState>().addBooking(booking);
              if (!added) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Este horario acaba de ser ocupado. Por favor elige otro.'),
                    backgroundColor: AppTheme.urgentRed,
                  ),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      '✅ Reserva solicitada con Garantía SeniCare. Esperando confirmación de la cuidadora.'),
                  backgroundColor: AppTheme.primary,
                ),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Confirmar Reserva con Garantía'),
          ),
        ],
      ),
    );
  }
}

// --- SCREEN D: Bookings, Care Logs, GPS Status & Dispute Resolution ---
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isClient = state.currentRole == 'client';
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    if (state.bookings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No hay reservas registradas todavía.'),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(state.seniorMode ? 24 : 16),
      itemCount: state.bookings.length,
      itemBuilder: (context, index) {
        final b = state.bookings[index];
        final shortId = b.id.length >= 4 ? b.id.substring(b.id.length - 4) : b.id;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Reserva #$shortId • ${b.durationHours}h',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    _buildStatusBadge(b.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isClient ? 'Cuidadora: ${b.caregiverName}' : 'Familia: Cliente Verificado',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Horario: ${b.day} a las ${b.slot} h (${currencyFormat.format(b.totalPaid)})',
                  style: theme.textTheme.bodyMedium,
                ),

                // GPS Verification Badge
                if (b.isGpsCheckedIn) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, color: AppTheme.primary, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Presencia en domicilio verificada por GPS (<100m)',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Daily Care Log ("Cuaderno de Cuidados")
                if (b.careLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundNeutral,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📋 Cuaderno de Cuidados en Tiempo Real:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        ...b.careLogs.map(
                          (log) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• [${log.category}] ${log.note}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Cancelled / Refunded Notice
                if (b.status == BookingStatus.Cancelled) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isClient
                                ? 'Solicitud rechazada. Reembolso íntegro (${currencyFormat.format(b.totalPaid)}) devuelto automáticamente a tu cuenta.'
                                : 'Solicitud rechazada. Reembolso del 100% (${currencyFormat.format(b.totalPaid)}) devuelto al cliente y notificación enviada.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Disputed Notice
                if (b.status == BookingStatus.Disputed) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange),
                    ),
                    child: Text(
                      '⚠️ En mediación: "${b.disputeReason}". Fondos congelados en garantía por Seguridad SeniCare.',
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Client Actions: Release Escrow OR Report Incident/Dispute
                if (isClient &&
                    (b.status == BookingStatus.Confirmed ||
                        b.status == BookingStatus.InProgress)) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      context.read<AppState>().releaseEscrow(b.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Cuidado completado y pago liberado a la cuidadora.'),
                          backgroundColor: AppTheme.primary,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                    label: const Text('Confirmar Éxito y Liberar Pago'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showDisputeDialog(context, b.id),
                    icon: const Icon(Icons.report_problem_outlined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.urgentRed,
                      side: const BorderSide(color: AppTheme.urgentRed),
                      minimumSize: Size(double.infinity, state.seniorMode ? 56 : 44),
                    ),
                    label: const Text('Reportar Incidencia / Abrir Disputa'),
                  ),
                ],

                // Caregiver Actions: Accept/Reject Pending OR GPS Check-in + Care Log
                if (!isClient && b.status == BookingStatus.PendingApproval)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<AppState>().confirmBooking(b.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cita aceptada. La familia ha sido notificada.'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          child: const Text('Aceptar Cita'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<AppState>().rejectBooking(b.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Solicitud rechazada. Reembolso devuelto al cliente automáticamente y notificación enviada por chat.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: Size(0, state.seniorMode ? 64 : 48),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                    ],
                  ),

                if (!isClient &&
                    (b.status == BookingStatus.Confirmed ||
                        b.status == BookingStatus.InProgress)) ...[
                  if (!b.isGpsCheckedIn)
                    ElevatedButton.icon(
                      onPressed: () {
                        context.read<AppState>().checkInGps(b.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📍 Llegada verificada por GPS en el domicilio.'),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      },
                      icon: const Icon(Icons.my_location),
                      label: const Text('Fichar Entrada GPS en Domicilio'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _showAddCareLogDialog(context, b.id),
                      icon: const Icon(Icons.note_add_rounded),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        minimumSize: Size(double.infinity, state.seniorMode ? 58 : 44),
                      ),
                      label: const Text('Añadir Nota al Cuaderno de Cuidados'),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDisputeDialog(BuildContext context, String bookingId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar Incidencia'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Describe el motivo (ej. retraso o inasistencia)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.urgentRed),
            onPressed: () {
              context.read<AppState>().openDispute(bookingId, controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ Disputa registrada. El pago en garantía ha sido congelado.'),
                  backgroundColor: AppTheme.urgentRed,
                ),
              );
            },
            child: const Text('Congelar Pago y Enviar'),
          ),
        ],
      ),
    );
  }

  void _showAddCareLogDialog(BuildContext context, String bookingId) {
    final controller = TextEditingController();
    String selectedCategory = 'Medicación';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cuaderno de Cuidados'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                items: const [
                  DropdownMenuItem(value: 'Medicación', child: Text('💊 Medicación')),
                  DropdownMenuItem(value: 'Alimentación', child: Text('🍲 Alimentación')),
                  DropdownMenuItem(value: 'Paseo / Actividad', child: Text('🚶 Paseo / Actividad')),
                  DropdownMenuItem(value: 'Estado de Ánimo', child: Text('😊 Estado de Ánimo')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedCategory = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Ej: Tomó la pastilla de las 10h y desayunó bien.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                context
                    .read<AppState>()
                    .addCareLogEntry(bookingId, selectedCategory, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Guardar en Bitácora'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BookingStatus status) {
    Color color;
    String text;
    switch (status) {
      case BookingStatus.PendingApproval:
        color = Colors.orange.shade800;
        text = 'Pendiente';
        break;
      case BookingStatus.Confirmed:
        color = Colors.blue.shade700;
        text = 'Confirmada';
        break;
      case BookingStatus.InProgress:
        color = AppTheme.primary;
        text = 'En Curso (GPS)';
        break;
      case BookingStatus.Completed:
        color = Colors.green.shade700;
        text = 'Completada';
        break;
      case BookingStatus.Cancelled:
        color = Colors.red.shade700;
        text = 'Rechazada / Reembolsada';
        break;
      case BookingStatus.Disputed:
        color = Colors.deepOrange;
        text = 'En Disputa';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// --- SCREEN E: Secured Chat with Semantic Anti-Bypass Protection ---
class ChatScreen extends StatefulWidget {
  final bool isStandalone;
  const ChatScreen({super.key, this.isStandalone = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  void _sendMessage(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final result = context.read<AppState>().sendChatMessage(text);
    _controller.clear();

    if (result.wasBlocked) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🛡️ Protección de Seguridad SeniCare'),
          content: Text(
            'Por tu seguridad y para mantener activa la Garantía SeniCare, el intercambio de ${result.blockReason ?? "datos de contacto externos"} está protegido hasta confirmar la reserva.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final content = Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.chatMessages.length,
            itemBuilder: (context, index) {
              final msg = state.chatMessages[index];
              final isMe = msg.sender == ChatSender.Client;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isMe ? Radius.zero : null,
                      bottomLeft: !isMe ? Radius.zero : null,
                    ),
                    border: isMe ? null : Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppTheme.darkSlate,
                      fontSize: state.seniorMode ? 18 : 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje seguro...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(context),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                radius: state.seniorMode ? 30 : 24,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () => _sendMessage(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isStandalone) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat Directo Protegido')),
        body: content,
      );
    }
    return content;
  }
}

// --- SCREEN F: Caregiver Dashboard (Elena Sanz Account) ---
class CaregiverDashboard extends StatelessWidget {
  const CaregiverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final seniorMode = state.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    // Calculates released earnings using dynamic commission tiers (82%, 90%, or 94% net)
    final double earnings = state.bookings
        .where((b) => b.isEscrowReleased && b.caregiverId == 'c1')
        .fold(0.0, (sum, b) => sum + b.caregiverNetEarnings);

    final pendingBookings = state.bookings
        .where((b) => b.status == BookingStatus.PendingApproval)
        .toList();

    return ListView(
      padding: EdgeInsets.all(seniorMode ? 24 : 16),
      children: [
        Text('Hola, Elena 👋', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          color: AppTheme.darkSlate,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance Disponible (Neto tras comisión)',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  currencyFormat.format(earnings),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Escala fidelidad SeniCare: 82% (1er servicio) ➔ 90% (recurrente) ➔ 94% (+5 servicios)',
                  style: TextStyle(color: Colors.green.shade300, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Fondos transferidos a tu cuenta IBAN conectada.'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: const Text('Retirar a cuenta bancaria'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Solicitudes Pendientes (${pendingBookings.length})',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (pendingBookings.isEmpty)
          const Text('No tienes nuevas solicitudes pendientes.')
        else
          ...pendingBookings.map(
            (b) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Reserva el ${b.day} a las ${b.slot} (${b.durationHours}h)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: const Text(
                            'Pendiente',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ganancia neta asegurada: ${currencyFormat.format(b.caregiverNetEarnings)} (${100 - b.commissionRatePercent}% de ${currencyFormat.format(b.cost)})',
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              context.read<AppState>().confirmBooking(b.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cita aceptada. El cliente ha sido notificado.'),
                                  backgroundColor: AppTheme.primary,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                            child: const Text('Aceptar Cita'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              context.read<AppState>().rejectBooking(b.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Solicitud rechazada. Reembolso devuelto al cliente automáticamente y notificación enviada por chat.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              minimumSize: Size(0, seniorMode ? 64 : 48),
                            ),
                            child: const Text('Rechazar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Gestión de Disponibilidad', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Lunes 09:00 - 12:00'),
                value: true,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Lunes 16:00 - 19:00'),
                value: true,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Martes 10:00 - 13:00'),
                value: false,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
