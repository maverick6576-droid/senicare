class AntiBypassResult {
  final String sanitizedText;
  final bool wasBlocked;
  final String? blockReason;

  const AntiBypassResult({
    required this.sanitizedText,
    required this.wasBlocked,
    this.blockReason,
  });
}

/// Context-aware Semantic and Pattern-based Anti-Bypass validator for the SeniCare chat.
/// - Pre-booking (`hasConfirmedBooking == false`): Protects families and caregivers by keeping
///   communication inside the insured platform prior to confirming a reservation.
/// - Post-booking (`hasConfirmedBooking == true`): Unlocks phone numbers, intercom codes,
///   and home addresses so the family and caregiver can coordinate arrival smoothly.
class AntiBypassValidator {
  // 1. Numeric phones (Spanish mobile 6/7 and landline 8/9, even with spaces, dots, underscores, or hyphens)
  static final RegExp _phoneRegex = RegExp(
    r'(\+?\d{1,3}[\s\.\-_]?)?([6789]\d[\s\.\-_]?(\d[\s\.\-_]?){7})',
    caseSensitive: false,
  );

  // 2. Email addresses and obfuscated emails ("arroba", "gmail", "hotmail", "outlook")
  static final RegExp _emailRegex = RegExp(
    r'([a-zA-Z0-9._%+-]+\s*(@|\barroba\b)\s*[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|\b(gmail|hotmail|outlook|yahoo)\b',
    caseSensitive: false,
  );

  // 3. External messaging / social networks (including spaced/dotted obfuscation e.g. w.h.a.t.s.a.p.p)
  static final RegExp _externalSocialRegex = RegExp(
    r'\b(whatsapp|wasap|w[\s\.\-_]*h[\s\.\-_]*a[\s\.\-_]*t[\s\.\-_]*s|telegram|t\.me|instagram|insta|facebook)\b|@[a-zA-Z0-9_]{3,}',
    caseSensitive: false,
  );

  // 4. Spoken Spanish number words (3 or more consecutive number words used to spell out a phone)
  static final RegExp _spokenNumbersRegex = RegExp(
    r'(\b(cero|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)\b[\s,\.\-]*){3,}',
    caseSensitive: false,
  );

  // 5. Off-platform cash / Bizum / IBAN evasion patterns (including obfuscated b.i.z.u.m / b i z u m)
  static final RegExp _offPlatformPaymentRegex = RegExp(
    r'\b(bizum|b[\s\.\-_]+i[\s\.\-_]+z[\s\.\-_]+u[\s\.\-_]+m|en\s+mano|en\s+efectivo|pago\s+directo|fuera\s+de\s+la\s+app|sin\s+declarar)\b|\bES\d{2}[\s\-]?(\d{4}[\s\-]?){5}\b',
    caseSensitive: false,
  );

  static AntiBypassResult evaluate(
    String input, {
    bool hasConfirmedBooking = false,
  }) {
    String safeText = input;
    bool blocked = false;
    String? reason;

    // Off-platform payment solicitation (Bizum / cash in hand / IBAN) is always blocked to preserve RC insurance & Escrow
    if (_offPlatformPaymentRegex.hasMatch(safeText)) {
      safeText = safeText.replaceAll(
        _offPlatformPaymentRegex,
        '[Pago externo bloqueado: Usa Garantía SeniCare]',
      );
      blocked = true;
      reason = 'intento de pago fuera de la plataforma (Bizum / efectivo / IBAN)';
    }

    // Once a booking is confirmed and insured in Escrow, allow full contact & address exchange
    if (hasConfirmedBooking) {
      return AntiBypassResult(
        sanitizedText: safeText,
        wasBlocked: blocked,
        blockReason: reason,
      );
    }

    if (_phoneRegex.hasMatch(safeText)) {
      safeText = safeText.replaceAll(_phoneRegex, '[Teléfono protegido hasta reservar]');
      blocked = true;
      reason = 'número de teléfono';
    }

    if (_spokenNumbersRegex.hasMatch(safeText)) {
      safeText = safeText.replaceAll(_spokenNumbersRegex, '[Teléfono protegido hasta reservar]');
      blocked = true;
      reason = 'número telefónico escrito en texto';
    }

    if (_emailRegex.hasMatch(safeText)) {
      safeText = safeText.replaceAll(_emailRegex, '[Correo protegido hasta reservar]');
      blocked = true;
      reason = 'dirección de correo electrónico';
    }

    if (_externalSocialRegex.hasMatch(safeText)) {
      safeText = safeText.replaceAll(_externalSocialRegex, '[Contacto externo protegido]');
      blocked = true;
      reason = 'red social o mensajería externa';
    }

    return AntiBypassResult(
      sanitizedText: safeText,
      wasBlocked: blocked,
      blockReason: reason,
    );
  }
}
