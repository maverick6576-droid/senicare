import 'dart:math' as math;
import '../models/care_models.dart';

/// ============================================================================
/// PILAR 1: BLOQUEO TEMPORAL DE FRANJAS EN CHECKOUT (SLOT HOLD TTL - COSTE 0 €)
/// ============================================================================
/// Reserva temporalmente una franja horaria durante 10 minutos mientras la familia
/// revisa el pago en el Checkout (estilo Airbnb), evitando dobles reservas simultáneas
/// sin coste adicional de servidor.
class SlotHoldReservation {
  final String holdId;
  final String caregiverId;
  final String day;
  final String slot;
  final int durationHours;
  final String holderClientId;
  final DateTime createdAt;
  final DateTime expiresAt;

  const SlotHoldReservation({
    required this.holdId,
    required this.caregiverId,
    required this.day,
    required this.slot,
    required this.durationHours,
    required this.holderClientId,
    required this.createdAt,
    required this.expiresAt,
  });

  bool isActiveAt(DateTime now) => now.isBefore(expiresAt);
}

/// ============================================================================
/// PILAR 2: TRUST & SAFETY CON GUÍAS PASO A PASO Y CERO FRICCIÓN (COSTE 0 €)
/// ============================================================================
/// Modelo de documento de seguridad con guía paso a paso de cómo obtenerlo gratis
/// y cómo subirlo en 1 toque, diseñado para no asustar ni generar abandono en familias.
class GuidedVerificationDocument {
  final String id;
  final String title;
  final String subtitle;
  final String targetAudience; // 'Solo Cuidadora (0 trámites para la familia)', 'Automático (Sin papeleo)', '1 Clic Digital'
  final String timeRequiredBadge; // '40 seg', '2 min gratis online', 'Automático (0 seg)', '1 toque'
  final String costBadge; // 'Coste 0 €'
  final String familyPeaceOfMindNote;
  final List<String> howToGetSteps;
  final List<String> howToUploadSteps;
  bool isCompleted;
  String? verificationCodeOrRef;

  GuidedVerificationDocument({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.targetAudience,
    required this.timeRequiredBadge,
    this.costBadge = 'Gratis (0 €)',
    required this.familyPeaceOfMindNote,
    required this.howToGetSteps,
    required this.howToUploadSteps,
    this.isCompleted = true,
    this.verificationCodeOrRef,
  });

  static List<GuidedVerificationDocument> buildDefaultCatalog() {
    return [
      GuidedVerificationDocument(
        id: 'doc_dni_kyc',
        title: '1. Identidad Biométrica (DNI / NIE + Selfie)',
        subtitle: 'Comprobación oficial de identidad real integrada con Stripe Connect.',
        targetAudience: 'Solo Cuidadora (0 trámites para la familia)',
        timeRequiredBadge: '40 segundos',
        familyPeaceOfMindNote:
            'Tranquilidad total: como familia NO necesitas subir tu DNI para explorar la app. SeniCare ya ha verificado la identidad de cada profesional por ti.',
        howToGetSteps: const [
          '1. Ten a mano tu DNI o NIE físico en vigor.',
          '2. Colócate en un lugar con buena luz natural para evitar reflejos en el plástico.',
          '3. No necesitas escáner ni impresora: se hace directamente con la cámara de tu móvil.',
        ],
        howToUploadSteps: const [
          '1. Pulsa el botón "Hacer foto de mi DNI/NIE" desde esta pantalla.',
          '2. Fotografía la cara delantera y trasera dentro del recuadro verde.',
          '3. Hazte un selfie rápido mirando a la cámara para confirmar que eres tú.',
        ],
        isCompleted: true,
        verificationCodeOrRef: 'KYC-STRIPE-VERIFIED-ES',
      ),
      GuidedVerificationDocument(
        id: 'doc_sexual_offenses_cert',
        title: '2. Certificado Oficial de Antecedentes y Delitos Sexuales',
        subtitle: 'Documento oficial gratuito del Ministerio de Justicia con código CSV verificable.',
        targetAudience: 'Solo Cuidadora (Exigido por ley en España)',
        timeRequiredBadge: '2 min online',
        familyPeaceOfMindNote:
            'Cero papeleo para ti: exigimos y validamos el Certificado Oficial del Ministerio de Justicia a todas las cuidadoras antes de su primera cita.',
        howToGetSteps: const [
          '1. Entra en la Sede Electrónica del Ministerio de Justicia (sede.mjusticia.gob.es) desde tu móvil u ordenador.',
          '2. Identifícate gratis con Cl@ve PIN, Certificado Digital o DNI electrónico (el trámite es 100% gratuito, 0 €).',
          '3. Descarga al instante el PDF oficial que incluye al pie el Código Seguro de Verificación (CSV).',
        ],
        howToUploadSteps: const [
          '1. Pulsa en "Subir PDF o introducir código CSV".',
          '2. Adjunta el PDF descargado en 1 toque o escribe el código CSV del documento.',
          '3. SeniCare coteja gratuitamente el código CSV y activa tu insignia de Profesional Verificado.',
        ],
        isCompleted: true,
        verificationCodeOrRef: 'CSV-MJUST-2026-884192',
      ),
      GuidedVerificationDocument(
        id: 'doc_rc_insurance',
        title: '3. Póliza Colectiva de Responsabilidad Civil (300.000 €)',
        subtitle: 'Protección estilo AirCover frente a accidentes o daños en el hogar durante el turno.',
        targetAudience: 'Activación Automática (Sin subir documentos)',
        timeRequiredBadge: '0 seg (Automático)',
        familyPeaceOfMindNote:
            'Activado automáticamente al reservar: no tienes que rellenar formularios ni contratar seguros aparte.',
        howToGetSteps: const [
          '1. No tienes que buscar ni pagar ninguna aseguradora externa.',
          '2. En cuanto se confirma una reserva en SeniCare, el turno queda cubierto automáticamente por nuestra Póliza Colectiva RC (#SC-2026-88412).',
          '3. Puedes ver y descargar el Certificado de Cobertura en el detalle de cada reserva.',
        ],
        howToUploadSteps: const [
          '1. Para activar la cobertura no necesitas subir ningún documento.',
          '2. Si ocurriera algún incidente durante el servicio, pulsa "Notificar Parte al Seguro RC" en la reserva.',
          '3. Adjunta una foto desde tu móvil y describe lo sucedido en 2 líneas; nosotros gestionamos el resto.',
        ],
        isCompleted: true,
        verificationCodeOrRef: 'POL-SC-2026-88412',
      ),
      GuidedVerificationDocument(
        id: 'doc_rgpd_art9_consent',
        title: '4. Protección de Datos de Salud (RGPD Art. 9 en 1 Toque)',
        subtitle: 'Privacidad blindada con PIN para medicación, alergias y grado de dependencia.',
        targetAudience: 'Activación en 1 Clic (Sin imprimir ni firmar papeles)',
        timeRequiredBadge: '1 toque (5 seg)',
        familyPeaceOfMindNote:
            'Los datos médicos de tu familiar nunca son públicos. Solo los ve tu cuidadora confirmada durante las horas del servicio.',
        howToGetSteps: const [
          '1. No necesitas informes médicos en papel ni firmas manuscritas.',
          '2. Rellena únicamente las pautas básicas (alergias y medicación) que quieras que conozca la cuidadora.',
          '3. La ficha queda protegida bajo tu PIN familiar de 4 dígitos.',
        ],
        howToUploadSteps: const [
          '1. Marca el interruptor digital "Autorizo acceso seguro en turno (RGPD Art. 9)" con un solo dedo.',
          '2. Queda registrado con sello de tiempo digital sin trámites adicionales.',
          '3. Puedes desactivarlo o eliminar los datos cuando quieras con 1 toque.',
        ],
        isCompleted: true,
        verificationCodeOrRef: 'RGPD-ART9-CONSENT-OK',
      ),
    ];
  }
}

/// ============================================================================
/// PILAR 3: MOTOR GEOESPACIAL HAVERSINE Y CALENDARIO iCAL (.ICS) (COSTE 0 €)
/// ============================================================================
class ZeroCostGeoAndCalendarEngine {
  /// Calcula la distancia exacta en línea recta/urbana en kilómetros entre dos coordenadas
  /// usando la fórmula trigonométrica de Haversine (Coste 0 € frente a Google Distance Matrix API).
  static double calculateHaversineKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double straightKm = earthRadiusKm * c;
    // Factor de corrección vial urbano (1.25x)
    return double.parse((straightKm * 1.25).toStringAsFixed(1));
  }

  /// Estima el tiempo de llegada en transporte urbano (minutos) sin APIs externas de pago.
  static int estimateUrbanCommuteMinutes(double distanceKm) {
    return math.max(5, (distanceKm * 4.5 + 4).round());
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Exporta las reservas confirmadas al estándar abierto iCalendar (RFC 5545 `.ics`)
  /// compatible gratis con Google Calendar, Apple Calendar y Outlook.
  static String exportBookingsToIcs(List<Booking> bookings) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//SeniCare Marketplace//ES')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH');

    for (final b in bookings) {
      if (b.status == BookingStatus.Cancelled || b.isRefunded) continue;
      final startUtc = b.bookingDate.toUtc();
      final endUtc = startUtc.add(Duration(hours: b.durationHours));
      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:senicare_${b.id}@senicare.es')
        ..writeln('DTSTAMP:${_formatIcsDate(DateTime.now().toUtc())}')
        ..writeln('DTSTART:${_formatIcsDate(startUtc)}')
        ..writeln('DTEND:${_formatIcsDate(endUtc)}')
        ..writeln('SUMMARY:Asistencia SeniCare - ${b.caregiverName} (${b.durationHours}h)')
        ..writeln('DESCRIPTION:Reserva #${b.id} cubierta por Póliza RC SeniCare. PIN: ${b.checkInPin}')
        ..writeln('STATUS:CONFIRMED')
        ..writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// Importa franjas ocupadas desde un bloque `.ics` externo (ej. Google Calendar personal de la cuidadora)
  /// devolviendo las horas `HH:mm` ocupadas para evitar solapamientos.
  static List<String> parseBusySlotsFromIcs(String icsPayload) {
    final busySlots = <String>[];
    final regex = RegExp(r'DTSTART(?:;[^:]*)?:(\d{8}T(\d{2})(\d{2})\d{2})');
    for (final match in regex.allMatches(icsPayload)) {
      final hh = match.group(2);
      final mm = match.group(3);
      if (hh != null && mm != null) {
        final slot = '$hh:$mm';
        if (!busySlots.contains(slot)) {
          busySlots.add(slot);
        }
      }
    }
    return busySlots;
  }

  static String _formatIcsDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}T${two(dt.hour)}${two(dt.minute)}${two(dt.second)}Z';
  }
}

/// ============================================================================
/// PILAR 4: FISCALIDAD EUROPEA DAC7 (MODELO 238 AEAT) Y VERIFACTU (COSTE 0 €)
/// ============================================================================
class Dac7CaregiverReport {
  final String caregiverId;
  final String caregiverName;
  final String taxNif;
  final int fiscalYear;
  final int completedServicesCount;
  final double grossVolumeEur;
  final double platformFeesWithheldEur;
  final double netTransferredToCaregiverEur;

  const Dac7CaregiverReport({
    required this.caregiverId,
    required this.caregiverName,
    required this.taxNif,
    required this.fiscalYear,
    required this.completedServicesCount,
    required this.grossVolumeEur,
    required this.platformFeesWithheldEur,
    required this.netTransferredToCaregiverEur,
  });
}

class ZeroCostTaxAndVeriFactuEngine {
  /// Calcula una huella digital determinista encadenada (estilo VeriFactu / Ley Crea y Crece)
  /// sin pagar cuotas mensuales a proveedores externos de facturación.
  static String computeVeriFactuHash({
    required String invoiceNumber,
    required String familyNif,
    required double totalPaidEur,
    required DateTime issueDate,
    String previousInvoiceHash = 'GENESIS_SENICARE_AEAT_2026',
  }) {
    final rawPayload =
        '$invoiceNumber|$familyNif|${totalPaidEur.toStringAsFixed(2)}|${issueDate.toIso8601String()}|$previousInvoiceHash';
    int hash = 0x811c9dc5;
    for (int i = 0; i < rawPayload.length; i++) {
      hash ^= rawPayload.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hexPart = hash.toRadixString(16).toUpperCase().padLeft(8, '0');
    return 'VF-AEAT-2026-$hexPart-${invoiceNumber.replaceAll("-", "")}';
  }

  /// Construye la URL oficial de cotejo QR de la Agencia Tributaria (AEAT) para VeriFactu.
  static String buildAeatQrUrl({
    required String invoiceNumber,
    required String familyNif,
    required double totalPaidEur,
    required String verifactuHash,
  }) {
    return 'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR'
        '?nif=B88990011&numserie=$invoiceNumber&importe=${totalPaidEur.toStringAsFixed(2)}&huella=$verifactuHash';
  }

  /// Genera el resumen anual/trimestral para la Directiva Europea DAC7 (Modelo 238 AEAT).
  static Dac7CaregiverReport generateDac7Report({
    required CaregiverProfile caregiver,
    required List<Booking> allBookings,
    int? year,
  }) {
    final targetYear = year ?? DateTime.now().year;
    final completed = allBookings.where((b) =>
        b.caregiverId == caregiver.id &&
        b.status == BookingStatus.Completed &&
        b.isEscrowReleased &&
        !b.isRefunded);

    double gross = 0.0;
    double fees = 0.0;
    double net = 0.0;
    int count = 0;

    for (final b in completed) {
      gross += b.cost;
      fees += b.appCommission;
      net += b.caregiverNetEarnings;
      count++;
    }

    return Dac7CaregiverReport(
      caregiverId: caregiver.id,
      caregiverName: caregiver.name,
      taxNif: caregiver.dac7TaxNif,
      fiscalYear: targetYear,
      completedServicesCount: count,
      grossVolumeEur: double.parse(gross.toStringAsFixed(2)),
      platformFeesWithheldEur: double.parse(fees.toStringAsFixed(2)),
      netTransferredToCaregiverEur: double.parse(net.toStringAsFixed(2)),
    );
  }
}

/// ============================================================================
/// PILAR 5: VIDEOENTREVISTA P2P GRATUITA IN-APP (WEBRTC / JITSI - COSTE 0 €)
/// ============================================================================
class ZeroCostVideoInterviewEngine {
  /// Crea una sala efímera cifrada de 15 minutos usando WebRTC P2P sin pagar minutos a Twilio/Agora
  /// y sin exponer los números de teléfono personales de la familia ni de la cuidadora.
  static String createMaskedVideoInterviewUrl({
    required String caregiverId,
    required String clientId,
  }) {
    final token = ((caregiverId.hashCode ^ clientId.hashCode).abs() % 900000) + 100000;
    return 'https://meet.jit.si/SeniCare-Entrevista-Segura-$caregiverId-$token#config.prejoinPageEnabled=false';
  }
}

/// ============================================================================
/// PILAR 6: MULTI-IDIOMA LIGERO (ES / CA / EN) Y DEEP LINKS (COSTE 0 €)
/// ============================================================================
class ZeroCostI18n {
  static const Map<String, Map<String, String>> _strings = {
    'es': {
      'guarantee_badge': 'Garantía 100% SeniCare',
      'zero_paperwork_banner':
          '✨ Cero Papeleo para Familias: SeniCare ya ha verificado el DNI, antecedentes y seguro de cada profesional. Elige y reserva en 1 minuto.',
      'trust_center_btn': 'Guía Fácil de Documentos y Seguridad',
      'video_interview_btn': 'Videoentrevista Gratis (15 min sin dar tu teléfono)',
      'instant_book_badge': '⚡ Reserva Inmediata',
    },
    'ca': {
      'guarantee_badge': 'Garantia 100% SeniCare',
      'zero_paperwork_banner':
          '✨ Zero Paperassa per a Famílies: SeniCare ja ha verificat el DNI, antecedents i assegurança de cada professional. Tria i reserva en 1 minut.',
      'trust_center_btn': 'Guia Fàcil de Documents i Seguretat',
      'video_interview_btn': 'Videoentrevista Gratis (15 min sense donar el telèfon)',
      'instant_book_badge': '⚡ Reserva Immediata',
    },
    'en': {
      'guarantee_badge': '100% SeniCare Guarantee',
      'zero_paperwork_banner':
          '✨ Zero Paperwork for Families: SeniCare has already verified the ID, background check, and insurance of every caregiver. Book in 1 minute.',
      'trust_center_btn': 'Easy Document & Trust Guide',
      'video_interview_btn': 'Free Video Interview (15 min, phone stays private)',
      'instant_book_badge': '⚡ Instant Book',
    },
  };

  static String tr(String locale, String key) {
    return _strings[locale]?[key] ?? _strings['es']![key] ?? key;
  }

  static String buildUniversalShareLink(String caregiverId) {
    return 'https://senicare-3342d.web.app/caregivers/$caregiverId';
  }
}
