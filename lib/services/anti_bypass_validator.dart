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

/// Semantic and pattern-based Anti-Bypass validator for the SeniCare chat.
/// Protects families and caregivers by keeping communication inside the insured platform
/// prior to confirming a reservation.
class AntiBypassValidator {
  // 1. Numeric phones (Spanish mobile 6/7 and landline 8/9, even with spaces, dots, or hyphens)
  static final RegExp _phoneRegex = RegExp(
    r'(\+?\d{1,3}[\s\.\-]?)?([6789]\d[\s\.\-]?(\d[\s\.\-]?){7})',
    caseSensitive: false,
  );

  // 2. Email addresses and obfuscated emails ("arroba", "gmail", "hotmail", "outlook")
  static final RegExp _emailRegex = RegExp(
    r'([a-zA-Z0-9._%+-]+\s*(@|\barroba\b)\s*[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|\b(gmail|hotmail|outlook|yahoo)\b',
    caseSensitive: false,
  );

  // 3. External messaging / social networks
  static final RegExp _externalSocialRegex = RegExp(
    r'\b(whatsapp|wasap|telegram|t\.me|instagram|insta|facebook)\b|@[a-zA-Z0-9_]{3,}',
    caseSensitive: false,
  );

  // 4. Spoken Spanish number words (3 or more consecutive number words used to spell out a phone)
  static final RegExp _spokenNumbersRegex = RegExp(
    r'(\b(cero|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)\b[\s,\.\-]*){3,}',
    caseSensitive: false,
  );

  static AntiBypassResult evaluate(String input) {
    String safeText = input;
    bool blocked = false;
    String? reason;

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
