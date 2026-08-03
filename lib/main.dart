// main.dart
// SeniCare - High-Fidelity MVP
// A single-file Flutter application matching families/seniors with verified caretakers.
// Features accessibility options (Senior Mode) and robust mock state management.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Used for currency formatting

void main() {
  runApp(
    // Injecting the AppState into the widget tree via Provider for reactive state management.
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const SeniCareApp(),
    ),
  );
}

// ==========================================
// 1. DATA MODELS & ENUMS
// ==========================================

/// Defines the lifecycle stages of a Booking transaction in the Escrow system.
enum BookingStatus { PendingApproval, Confirmed, Completed, Cancelled }

/// Identifies the sender in the chat interface.
enum ChatSender { Client, Caregiver }

/// Core data model representing a Caretaker's profile in the marketplace.
class CaregiverProfile {
  final String id;
  final String name;
  final String title;
  final String bio;
  final double pricePerHour;
  final double rating;
  final int reviewsCount;
  final String distance;
  final String imageUrl;
  final List<String> specialties;
  final bool verified;
  // Simulates real-time availability: Day of the week -> List of available hour strings
  final Map<String, List<String>> availableSlots;

  CaregiverProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.bio,
    required this.pricePerHour,
    required this.rating,
    required this.reviewsCount,
    required this.distance,
    required this.imageUrl,
    required this.specialties,
    required this.verified,
    required this.availableSlots,
  });
}

/// Represents a secure transaction and reservation.
class Booking {
  final String id;
  final String caregiverId;
  final String caregiverName;
  final String day;
  final String slot;
  BookingStatus status;
  final double cost;
  final double appCommission;
  final double totalPaid;
  bool isEscrowReleased;

  Booking({
    required this.id,
    required this.caregiverId,
    required this.caregiverName,
    required this.day,
    required this.slot,
    this.status = BookingStatus.PendingApproval,
    required this.cost,
    required this.appCommission,
    required this.totalPaid,
    this.isEscrowReleased = false,
  });
}

/// A single message entity for the secured chat.
class ChatMessage {
  final ChatSender sender;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
  });
}

// ==========================================
// 2. STATE MANAGEMENT (Provider)
// ==========================================

/// Central in-memory state manager that triggers UI updates using ChangeNotifier.
class AppState extends ChangeNotifier {
  String currentRole = 'client'; // Defines the visible dashboard: 'client' or 'caregiver'
  bool seniorMode = false;       // Toggles accessibility styling (larger fonts, touch targets)
  String selectedSpecialty = 'Todos';
  String searchQuery = '';
  
  // Mock data representing Caregivers in the database
  List<CaregiverProfile> caregivers = [
    CaregiverProfile(
      id: 'c1',
      name: 'Elena Sanz',
      title: 'Enfermera Geriátrica',
      bio: 'Especialista en movilidad y cuidados post-operatorios con más de 10 años de experiencia. Apasionada por el bienestar emocional de los mayores.',
      pricePerHour: 18.0,
      rating: 4.9,
      reviewsCount: 124,
      distance: '2.5 km',
      imageUrl: 'https://i.pravatar.cc/300?img=47',
      specialties: ['Movilidad', 'Cocina Médica'],
      verified: true,
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
      imageUrl: 'https://i.pravatar.cc/300?img=11',
      specialties: ['Compañía', 'Soporte Digital'],
      verified: true,
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
      imageUrl: 'https://i.pravatar.cc/300?img=43',
      specialties: ['Movilidad', 'Cocina Médica', 'Compañía'],
      verified: true,
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
      text: '¡Hola! Soy Elena. ¿En qué te puedo ayudar hoy?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    )
  ];

  /// The predefined list of categories for the horizontal filter row
  List<String> get availableSpecialties => ['Todos', 'Compañía', 'Movilidad', 'Cocina Médica', 'Soporte Digital'];

  /// Computes the active list of caregivers based on search query and selected filter
  List<CaregiverProfile> get filteredCaregivers {
    return caregivers.where((c) {
      final matchesSpecialty = selectedSpecialty == 'Todos' || c.specialties.contains(selectedSpecialty);
      final matchesSearch = c.name.toLowerCase().contains(searchQuery.toLowerCase()) || 
                            c.title.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesSpecialty && matchesSearch;
    }).toList();
  }

  // --- Mutators ---

  void toggleSeniorMode(bool value) {
    seniorMode = value;
    notifyListeners(); // Rebuilds the entire app Theme and UI
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

  void addBooking(Booking booking) {
    bookings.add(booking);
    notifyListeners();
  }

  void confirmBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      bookings[idx].status = BookingStatus.Confirmed;
      notifyListeners();
    }
  }

  void rejectBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      bookings[idx].status = BookingStatus.Cancelled;
      notifyListeners();
    }
  }

  void releaseEscrow(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      bookings[idx].status = BookingStatus.Completed;
      bookings[idx].isEscrowReleased = true;
      notifyListeners();
    }
  }

  /// Appends a new message and runs the Anti-Bypass Algorithm
  void sendChatMessage(String text) {
    // Anti-Bypass Algorithm: Regex to detect common Spanish phone number formats
    final phoneRegex = RegExp(r'(\+34\s?)?[67]\d{2}(\s?\d{2}){3}|[67]\d{8}');
    String safeText = text;
    bool blocked = false;

    // Evaluate input against restricted patterns
    if (phoneRegex.hasMatch(text)) {
      safeText = text.replaceAll(phoneRegex, '[Bloqueado hasta reservar]');
      blocked = true;
    }

    // Append client message
    chatMessages.add(ChatMessage(
      sender: ChatSender.Client,
      text: safeText,
      timestamp: DateTime.now(),
    ));
    notifyListeners();

    // Auto-Responder Simulation if message was clean
    if (!blocked) {
      Future.delayed(const Duration(seconds: 3), () {
        chatMessages.add(ChatMessage(
          sender: ChatSender.Caregiver,
          text: 'Gracias por tu mensaje. Para poder confirmar la asistencia, por favor completa la reserva en mi calendario.',
          timestamp: DateTime.now(),
        ));
        notifyListeners();
      });
    }
  }
}

// ==========================================
// 3. THEME & ACCESSIBILITY TOKENS
// ==========================================

/// Defines central design tokens dynamically adaptable for accessibility.
class AppTheme {
  // Use a highly accessible emerald that passes the 7:1 contrast ratio against white text.
  static const Color primary = Color(0xFF036646); 
  static const Color darkSlate = Color(0xFF1E293B);
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  static const Color amber = Colors.amber;

  /// Generates the ThemeData reacting to the Senior Mode switch
  static ThemeData getTheme(bool seniorMode) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: darkSlate,
        background: backgroundNeutral,
      ),
      scaffoldBackgroundColor: backgroundNeutral,
      // Dynamic typography: Scales up significantly if seniorMode is true.
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: seniorMode ? 18 : 14, color: darkSlate, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(fontSize: seniorMode ? 22 : 16, color: darkSlate, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontSize: seniorMode ? 24 : 18, color: darkSlate, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(fontSize: seniorMode ? 28 : 22, color: darkSlate, fontWeight: FontWeight.bold),
      ),
      // Dynamic touch targets for buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, seniorMode ? 64 : 48), // AAA compliance padding
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(fontSize: seniorMode ? 18 : 14, fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 2,
        margin: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}

// ==========================================
// 4. MAIN APP ENTRY & CORE LAYOUT
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

/// The root scaffold orchestrating the Bottom Navigation and App Bar role switcher.
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

    // Different navigation flows based on simulated Role
    final currentScreens = isClient
        ? const [ExplorerScreen(), BookingsScreen(), ChatScreen()]
        : const [CaregiverDashboard(), BookingsScreen(), ChatScreen()];

    // Prevent bounds exception when switching roles
    if (_currentIndex >= currentScreens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isClient ? 'SeniCare' : 'Panel de Cuidador', 
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)
        ),
        actions: [
          // Senior Mode Accessibility Toggle
          Row(
            children: [
              Text('Modo Accesible (Mayor)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
              Switch(
                value: state.seniorMode,
                onChanged: (val) => state.toggleSeniorMode(val),
                activeColor: AppTheme.primary,
              ),
            ],
          ),
          // Role Debug Switcher via Popup Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline, color: AppTheme.darkSlate),
            onSelected: (role) {
              state.setRole(role);
              setState(() => _currentIndex = 0);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'client', child: Text('Modo Cliente')),
              PopupMenuItem(value: 'caregiver', child: Text('Modo Cuidador (Elena)')),
            ],
          )
        ],
      ),
      body: currentScreens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(isClient ? Icons.search : Icons.dashboard),
            label: isClient ? 'Explorar' : 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Reservas',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. SCREENS ARCHITECTURE
// ==========================================

// --- SCREEN A: Explorer / Marketplace ---
class ExplorerScreen extends StatelessWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Top Location Header & Escrow Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
              const SizedBox(width: 4),
              Text('Madrid, ES', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security, color: Colors.green, size: 14),
                    SizedBox(width: 4),
                    Text('Stripe Escrow Verified', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            onChanged: state.setSearchQuery,
            decoration: InputDecoration(
              hintText: 'Buscar cuidadores...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        // Filters Row
        SingleChildScrollView(
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
                  onSelected: (val) => state.setSpecialty(spec),
                  selectedColor: AppTheme.primary.withOpacity(0.2),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Caregiver Cards List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.filteredCaregivers.length,
            itemBuilder: (context, index) {
              final c = state.filteredCaregivers[index];
              return Card(
                child: Column(
                  children: [
                    // Resilient Remote Image handling via errorBuilder
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(
                        c.imageUrl,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 140,
                          color: Colors.grey.shade200,
                          child: Icon(Icons.person, size: 64, color: Colors.grey.shade400),
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
                                    Text(c.name, style: theme.textTheme.titleMedium),
                                    const SizedBox(width: 4),
                                    if (c.verified) const Icon(Icons.verified, color: Colors.blue, size: 16),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: AppTheme.amber, size: 18),
                                  Text('${c.rating} (${c.reviewsCount})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(c.title, style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          // Dynamic Specialities Wrap
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: c.specialties.map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: AppTheme.backgroundNeutral, borderRadius: BorderRadius.circular(4)),
                              child: Text(s, style: const TextStyle(fontSize: 10, color: AppTheme.darkSlate)),
                            )).toList(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('\$${c.pricePerHour.toStringAsFixed(0)}/h', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => CaregiverDetailScreen(caregiver: c),
                                  ));
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: Size(120, state.seniorMode ? 56 : 40),
                                ),
                                child: const Text('Ver Perfil'),
                              )
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        )
      ],
    );
  }
}

// --- SCREEN B: Caregiver Details & Booking Screen ---
class CaregiverDetailScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  const CaregiverDetailScreen({super.key, required this.caregiver});

  @override
  State<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends State<CaregiverDetailScreen> {
  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    // Default to the first available day
    _selectedDay = widget.caregiver.availableSlots.keys.isNotEmpty 
        ? widget.caregiver.availableSlots.keys.first 
        : 'Sin disponibilidad';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.caregiver;
    final slots = c.availableSlots[_selectedDay] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          // Caregiver Hero Profile Image
          Image.network(
            c.imageUrl,
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 240,
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
                      const Icon(Icons.verified, color: Colors.blue, size: 20),
                      const SizedBox(width: 4),
                      const Text(
                        'Verificado',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: AppTheme.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('${c.rating} (${c.reviewsCount} reseñas)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    const Icon(Icons.location_on, color: Colors.grey, size: 20),
                    Text(c.distance, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(c.bio, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Text('Reserva tu cita', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                // Interactive Calendar Carousel
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: c.availableSlots.keys.map((day) {
                      final isSelected = _selectedDay == day;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDay = day),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primary),
                          ),
                          child: Center(
                            child: Text(day, style: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // Slots render logic for the active day
                if (slots.isEmpty)
                  const Text('No hay horarios disponibles para este día.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: slots.map((slot) {
                      return ActionChip(
                        label: Text(slot),
                        onPressed: () {
                          // Navigate deep to Secure Payment Screen
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PaymentScreen(caregiver: c, day: _selectedDay, slot: slot),
                          ));
                        },
                        backgroundColor: AppTheme.backgroundNeutral,
                        side: const BorderSide(color: AppTheme.primary),
                      );
                    }).toList(),
                  )
              ],
            ),
          )
        ],
      ),
      // Direct Chat Navigation CTA
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen(isStandalone: true)));
        },
        label: const Text('Chat Directo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.chat, color: Colors.white),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}

// --- SCREEN C: Secure Payment Confirmation ---
class PaymentScreen extends StatelessWidget {
  final CaregiverProfile caregiver;
  final String day;
  final String slot;

  const PaymentScreen({super.key, required this.caregiver, required this.day, required this.slot});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final seniorMode = state.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final double baseCost = caregiver.pricePerHour * 2; // Business logic: fixed 2-hour duration for MVP
    final double appFee = baseCost * 0.15;
    final double total = baseCost + appFee;

    return Scaffold(
      appBar: AppBar(title: const Text('Pago Seguro')),
      body: ListView(
        padding: EdgeInsets.all(seniorMode ? 24 : 16),
        children: [
          Text('Resumen de Reserva', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          // Breakdown Billing Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Cuidador:'), Text(caregiver.name, style: const TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Fecha:'), Text('$day a las $slot', style: const TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 8),
                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Duración:'), Text('2 horas', style: TextStyle(fontWeight: FontWeight.bold))]),
                  const Divider(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Costo Base:'), Text(currencyFormat.format(baseCost))]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Tarifa Servicio (15%):'), Text(currencyFormat.format(appFee))]),
                  const Divider(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(currencyFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 22)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Escrow Guarantee Indicator Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary)),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: AppTheme.primary),
                SizedBox(width: 12),
                Expanded(child: Text('Stripe Connect mantiene tus fondos seguros. El dinero no se libera al cuidador hasta que confirmes el servicio exitoso.', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Método de Pago (Stripe Sandbox)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          // Mock Sandboxed Form Fields
          TextField(
            decoration: const InputDecoration(labelText: 'Número de Tarjeta', border: OutlineInputBorder(), prefixIcon: Icon(Icons.credit_card)),
            controller: TextEditingController(text: '4242 4242 4242 4242'),
            readOnly: true,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              // Deposit Action triggers State Mutator
              final booking = Booking(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                caregiverId: caregiver.id,
                caregiverName: caregiver.name,
                day: day,
                slot: slot,
                cost: baseCost,
                appCommission: appFee,
                totalPaid: total,
                status: BookingStatus.PendingApproval,
              );
              context.read<AppState>().addBooking(booking);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Depósito asegurado. Reserva pendiente de aprobación.')));
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Confirmar y Asegurar Depósito'),
          ),
        ],
      ),
    );
  }
}

// --- SCREEN D: Bookings & Escrow Release Center ---
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isClient = state.currentRole == 'client';
    final theme = Theme.of(context);

    if (state.bookings.isEmpty) {
      return const Center(child: Text('No hay reservas registradas.'));
    }

    return ListView.builder(
      padding: EdgeInsets.all(state.seniorMode ? 24 : 16),
      itemCount: state.bookings.length,
      itemBuilder: (context, index) {
        final b = state.bookings[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reserva #${b.id.substring(b.id.length - 4)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    _buildStatusBadge(b.status),
                  ],
                ),
                const SizedBox(height: 16),
                Text(isClient ? 'Cuidador: ${b.caregiverName}' : 'Cliente: Usuario Demo', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Fecha: ${b.day} a las ${b.slot}', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                
                // Dynamic Action buttons depending on role and current status
                if (isClient && b.status == BookingStatus.Confirmed)
                  ElevatedButton(
                    onPressed: () {
                      context.read<AppState>().releaseEscrow(b.id);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago liberado exitosamente al cuidador.')));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                    child: const Text('Confirmar Éxito y Liberar Pago'),
                  ),
                if (!isClient && b.status == BookingStatus.PendingApproval)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.read<AppState>().confirmBooking(b.id),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          child: const Text('Aceptar Cita'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.read<AppState>().rejectBooking(b.id),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: Size(0, state.seniorMode ? 64 : 48),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                    ],
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(BookingStatus status) {
    Color color;
    String text;
    switch (status) {
      case BookingStatus.PendingApproval:
        color = Colors.orange;
        text = 'Pendiente';
        break;
      case BookingStatus.Confirmed:
        color = Colors.blue;
        text = 'Confirmada';
        break;
      case BookingStatus.Completed:
        color = Colors.green;
        text = 'Completada';
        break;
      case BookingStatus.Cancelled:
        color = Colors.red;
        text = 'Cancelada';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// --- SCREEN E: Secured Chat with Anti-Bypass Algorithm ---
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

    // The state manager handles the string mutation and regex logic. 
    // We replicate the regex logic here just to show the UI alert when a block occurs.
    final phoneRegex = RegExp(r'(\+34\s?)?[67]\d{2}(\s?\d{2}){3}|[67]\d{8}');
    if (phoneRegex.hasMatch(text)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Acción Bloqueada'),
          content: const Text('Por seguridad, el intercambio de datos de contacto está bloqueado hasta confirmar una reserva a través de la plataforma.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
    }
    
    // Dispatch to global state
    context.read<AppState>().sendChatMessage(text);
    _controller.clear();
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
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
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
                    style: TextStyle(color: isMe ? Colors.white : AppTheme.darkSlate),
                  ),
                ),
              );
            },
          ),
        ),
        // Input Area
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (_) => _sendMessage(context),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                radius: state.seniorMode ? 32 : 24,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () => _sendMessage(context),
                ),
              )
            ],
          ),
        )
      ],
    );

    // Render within an explicit Scaffold if pushed from another screen independently
    if (widget.isStandalone) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat Directo')),
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
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // Business Logic: Calculates released earnings minus platform commission
    double earnings = state.bookings
        .where((b) => b.isEscrowReleased && b.caregiverId == 'c1')
        .fold(0.0, (sum, b) => sum + (b.cost * 0.85));

    final pendingBookings = state.bookings.where((b) => b.status == BookingStatus.PendingApproval).toList();

    return ListView(
      padding: EdgeInsets.all(seniorMode ? 24 : 16),
      children: [
        Text('Hola, Elena', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        // Earning Wallet Card Widget
        Card(
          color: AppTheme.darkSlate,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Balance Disponible', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                const SizedBox(height: 8),
                Text(currencyFormat.format(earnings), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulación: Fondos enviados a tu cuenta bancaria.')));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: const Text('Retirar a cuenta bancaria'),
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Booking Requests List
        Text('Solicitudes Pendientes (${pendingBookings.length})', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (pendingBookings.isEmpty)
          const Text('No tienes nuevas solicitudes.')
        else
          ...pendingBookings.map((b) => Card(
            child: ListTile(
              title: Text('Reserva el ${b.day} a las ${b.slot}'),
              subtitle: Text('Ganancia estimada: ${currencyFormat.format(b.cost * 0.85)}'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ve a la pestaña Reservas para gestionar esta solicitud.')));
              },
            ),
          )),
        const SizedBox(height: 24),
        // Active Slot Management Widget
        Text('Gestión de Disponibilidad', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Lunes 09:00 - 12:00'),
                value: true,
                onChanged: (v) {}, // Mock visual change only for MVP scope
                activeColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Lunes 16:00 - 19:00'),
                value: true,
                onChanged: (v) {},
                activeColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Martes 10:00 - 13:00'),
                value: false,
                onChanged: (v) {},
                activeColor: AppTheme.primary,
              ),
            ],
          ),
        )
      ],
    );
  }
}
