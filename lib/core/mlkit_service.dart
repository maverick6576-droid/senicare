import 'dart:io';
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
  static Future<String> _extractTextFromImage(String imagePath) async {
    // If not mobile (e.g. running on Windows Desktop during dev), return a mock string
    // to prevent MissingPluginException.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await Future.delayed(const Duration(seconds: 2));
      return "ESPAÑA DOCUMENTO NACIONAL DE IDENTIDAD MOCK NAME SIN ANTECEDENTES PENALES";
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
      
      String resultText = recognizedText.text;
      
      await textRecognizer.close();
      return resultText;
    } catch (e) {
      debugPrint('Error OCR: \$e');
      return "";
    }
  }

  static Future<ValidationResult> validateDNI(String imagePath, String expectedName) async {
    final extractedText = await _extractTextFromImage(imagePath);
    final textUpper = extractedText.toUpperCase();
    final expectedNameUpper = expectedName.toUpperCase();

    // Mock logic fallback for desktop dev
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (expectedName.isNotEmpty) return ValidationResult(isApproved: true, isManualReview: false, message: "Aprobado (Mock)");
    }

    if (textUpper.isEmpty) {
      return ValidationResult(isApproved: false, isManualReview: true, message: "No se detecta texto legible. Requiere revisión manual.");
    }

    // Normalize spacing and newlines
    final normalizedText = textUpper.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedNoPunctuation = normalizedText.replaceAll(RegExp(r'[^\w\sÑñ]'), '');

    // Basic heuristic logic
    bool hasDNIKeywords = normalizedText.contains("ESPAÑA") || 
                          normalizedText.contains("ESPANA") || 
                          normalizedText.contains("DNI") || 
                          normalizedNoPunctuation.contains("D N I") ||
                          normalizedText.contains("DOCUMENTO NACIONAL");
    
    // Split expected name into words to check partial matches
    final nameParts = expectedNameUpper.split(' ').where((p) => p.length > 2).toList();
    int matches = 0;
    for (var part in nameParts) {
      if (normalizedText.contains(part) || normalizedNoPunctuation.contains(part)) matches++;
    }

    if (hasDNIKeywords && matches == nameParts.length && nameParts.isNotEmpty) {
      return ValidationResult(isApproved: true, isManualReview: false, message: "DNI válido y nombre coincide al 100%.");
    } else if (hasDNIKeywords && matches > 0) {
      return ValidationResult(isApproved: false, isManualReview: true, message: "Coincidencia parcial. Requiere revisión manual.");
    } else {
      return ValidationResult(isApproved: false, isManualReview: false, message: "Documento inválido o no coincide el titular.");
    }
  }

  static Future<ValidationResult> validateCriminalRecord(String imagePath, String expectedName) async {
    final extractedText = await _extractTextFromImage(imagePath);
    final textUpper = extractedText.toUpperCase();
    
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (expectedName.isNotEmpty) return ValidationResult(isApproved: true, isManualReview: false, message: "Aprobado (Mock)");
    }

    if (textUpper.isEmpty) {
      return ValidationResult(isApproved: false, isManualReview: true, message: "No se detecta texto legible. Requiere revisión manual.");
    }

    // Normalize spacing and newlines for easier matching
    final normalizedText = textUpper.replaceAll(RegExp(r'\s+'), ' ');

    bool hasKeywords = normalizedText.contains("MINISTERIO DE JUSTICIA") || 
                       normalizedText.contains("REGISTRO CENTRAL DE PENADOS") ||
                       normalizedText.contains("ANTECEDENTES PENALES");
                       
    bool hasNoRecords = normalizedText.contains("NO CONSTAN") || 
                        normalizedText.contains("CARECE DE") || 
                        normalizedText.contains("SIN ANTECEDENTES");
                        
    bool hasRecords = normalizedText.contains("SI CONSTAN") || 
                      normalizedText.contains("SÍ CONSTAN") || 
                      normalizedText.contains("CON ANTECEDENTES");

    // Check if the user's name is on the certificate
    final nameParts = expectedName.toUpperCase().split(' ').where((p) => p.length > 2).toList();
    int matches = 0;
    for (var part in nameParts) {
      if (normalizedText.contains(part)) matches++;
    }
    bool isNameMatching = (matches == nameParts.length && nameParts.isNotEmpty);

    if (hasRecords) {
      return ValidationResult(isApproved: false, isManualReview: false, message: "ATENCIÓN: Constan antecedentes penales. Rechazado.");
    }

    if (hasKeywords && hasNoRecords) {
      if (isNameMatching) {
        return ValidationResult(isApproved: true, isManualReview: false, message: "Certificado válido, sin antecedentes y coincide el titular.");
      } else {
        return ValidationResult(isApproved: false, isManualReview: true, message: "Certificado válido pero no parece coincidir con tu nombre. Revisión manual.");
      }
    } else if (hasKeywords) {
      return ValidationResult(isApproved: false, isManualReview: true, message: "Certificado detectado pero frase clave dudosa. Revisión manual.");
    } else {
      return ValidationResult(isApproved: false, isManualReview: false, message: "No parece un certificado de antecedentes penales oficial.");
    }
  }
}
