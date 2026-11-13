import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ValidationResult {
  final bool isApproved;
  final bool isManualReview;
  final String message;

  ValidationResult({required this.isApproved, required this.isManualReview, required this.message});
}

class MLKitService {
  static bool get _isDesktopWithoutMobileOcr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<String> _extractTextFromImage(String imagePath) async {
    if (kIsWeb || _isDesktopWithoutMobileOcr) {
      return "";
    }

    try {
      if (imagePath.toLowerCase().endsWith('.pdf')) {
        final File file = File(imagePath);
        final List<int> bytes = await file.readAsBytes();
        final PdfDocument document = PdfDocument(inputBytes: bytes);
        final String text = PdfTextExtractor(document).extractText();
        document.dispose();
        return text;
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      final String resultText = recognizedText.text;
      await textRecognizer.close();
      return resultText;
    } catch (e) {
      debugPrint('Error OCR: $e');
      return "";
    }
  }

  static int _countMatchingNameParts(String normalizedText, String normalizedNoPunct, String expectedName) {
    final nameParts = expectedName
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.length > 2)
        .toList();
    if (nameParts.isEmpty) return 0;
    int matches = 0;
    for (final part in nameParts) {
      if (normalizedText.contains(part) || normalizedNoPunct.contains(part)) {
        matches++;
      }
    }
    return matches;
  }

  static List<String> _extractNameParts(String expectedName) => expectedName
      .toUpperCase()
      .split(RegExp(r'\s+'))
      .where((p) => p.length > 2)
      .toList();

  static ValidationResult evaluateIdentityOcrText(String extractedText, String expectedName) {
    final textUpper = extractedText.toUpperCase().trim();
    if (textUpper.isEmpty) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "No se detectó texto OCR automático. Enviado a revisión manual.",
      );
    }

    final normalizedText = textUpper.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedNoPunct = normalizedText.replaceAll(RegExp(r'[^\w\sÑñ]'), '');

    final hasIdentityKeywords = normalizedText.contains("ESPAÑA") ||
        normalizedText.contains("ESPANA") ||
        normalizedText.contains("DNI") ||
        normalizedNoPunct.contains("D N I") ||
        normalizedText.contains("DOCUMENTO NACIONAL") ||
        normalizedText.contains("NIE") ||
        normalizedText.contains("TIE") ||
        normalizedText.contains("TARJETA DE IDENTIDAD") ||
        normalizedText.contains("PERMISO DE RESIDENCIA") ||
        normalizedText.contains("PASAPORTE") ||
        normalizedText.contains("PASSPORT");

    final hasSpanishIdPattern = RegExp(r'\b([XYZ]\d{7}[A-Z]|\d{8}[A-Z])\b')
        .hasMatch(normalizedNoPunct.replaceAll(' ', ''));

    final nameParts = _extractNameParts(expectedName);
    final matches = _countMatchingNameParts(normalizedText, normalizedNoPunct, expectedName);

    if ((hasIdentityKeywords || hasSpanishIdPattern) &&
        nameParts.isNotEmpty &&
        matches == nameParts.length) {
      return ValidationResult(
        isApproved: true,
        isManualReview: false,
        message: "Documento de identidad (DNI/NIE/Pasaporte) válido y titular coincidente.",
      );
    } else if (hasIdentityKeywords || hasSpanishIdPattern || matches > 0) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "Documento detectado con coincidencia parcial. Requiere revisión manual.",
      );
    }

    return ValidationResult(
      isApproved: false,
      isManualReview: false,
      message: "Documento inválido o ilegible. Usa DNI, NIE, TIE o Pasaporte vigente.",
    );
  }

  static Future<ValidationResult> validateDNI(String imagePath, String expectedName, {String? preExtractedText}) async {
    if (kIsWeb || _isDesktopWithoutMobileOcr) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "Pre-validación en web/escritorio: requiere revisión manual del equipo.",
      );
    }
    final extractedText = (preExtractedText != null && preExtractedText.trim().isNotEmpty)
        ? preExtractedText
        : await _extractTextFromImage(imagePath);
    return evaluateIdentityOcrText(extractedText, expectedName);
  }

  static Future<ValidationResult> validateCriminalRecord(String imagePath, String expectedName) async {
    if (kIsWeb || _isDesktopWithoutMobileOcr) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "Pre-validación en web/escritorio: requiere revisión manual del equipo.",
      );
    }

    final extractedText = await _extractTextFromImage(imagePath);
    final textUpper = extractedText.toUpperCase();
    if (textUpper.trim().isEmpty) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "No se detecta texto legible en el PDF/imagen. Enviado a revisión manual.",
      );
    }

    final normalizedText = textUpper.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedNoPunct = normalizedText.replaceAll(RegExp(r'[^\w\sÑñ]'), '');

    final hasKeywords = normalizedText.contains("MINISTERIO DE JUSTICIA") ||
        normalizedText.contains("REGISTRO CENTRAL DE PENADOS") ||
        normalizedText.contains("REGISTRO CENTRAL DE DELINCUENTES SEXUALES") ||
        normalizedText.contains("ANTECEDENTES PENALES") ||
        normalizedText.contains("DELITOS DE NATURALEZA SEXUAL") ||
        normalizedText.contains("CERTIFICADO DE ANTECEDENTES");

    final hasNoRecords = normalizedText.contains("NO CONSTAN") ||
        normalizedText.contains("CARECE DE") ||
        normalizedText.contains("SIN ANTECEDENTES");

    final hasRecords = normalizedText.contains("SI CONSTAN") ||
        normalizedText.contains("SÍ CONSTAN") ||
        normalizedText.contains("CON ANTECEDENTES");

    final hasCsvCode = normalizedText.contains("CSV") ||
        normalizedText.contains("CODIGO SEGURO DE VERIFICACION") ||
        normalizedText.contains("CÓDIGO SEGURO DE VERIFICACIÓN");

    final nameParts = _extractNameParts(expectedName);
    final matches = _countMatchingNameParts(normalizedText, normalizedNoPunct, expectedName);
    final isNameMatching = nameParts.isNotEmpty && matches == nameParts.length;

    if (hasRecords) {
      return ValidationResult(
        isApproved: false,
        isManualReview: false,
        message: "ATENCIÓN: Constan antecedentes penales/sexuales. Rechazado.",
      );
    }

    if (hasKeywords && hasNoRecords) {
      if (isNameMatching) {
        return ValidationResult(
          isApproved: true,
          isManualReview: false,
          message: hasCsvCode
              ? "Certificado oficial válido con CSV, sin antecedentes y titular coincidente."
              : "Certificado válido, sin antecedentes y titular coincidente.",
        );
      }
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "Certificado válido pero el nombre no coincide al 100%. Revisión manual.",
      );
    } else if (hasKeywords) {
      return ValidationResult(
        isApproved: false,
        isManualReview: true,
        message: "Certificado oficial detectado pero requiere verificación manual.",
      );
    }

    return ValidationResult(
      isApproved: false,
      isManualReview: false,
      message: "No parece un certificado oficial de Antecedentes Penales o Delitos Sexuales.",
    );
  }
}
