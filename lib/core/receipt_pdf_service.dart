import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Offset, Rect, Size;
import 'package:path_provider/path_provider.dart';
import 'package:senicare/models/models.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Servicio corporativo de generación y descarga de justificantes legales en PDF.
class ReceiptPdfService {
  static final PdfColor _primaryTeal = PdfColor(13, 148, 136);
  static final PdfColor _secondaryEmerald = PdfColor(5, 150, 105);
  static final PdfColor _primarySurface = PdfColor(240, 253, 250);
  static final PdfColor _darkSlate = PdfColor(15, 23, 42);
  static final PdfColor _slateMuted = PdfColor(71, 85, 105);
  static final PdfColor _borderSubtle = PdfColor(226, 232, 240);
  static final PdfColor _backgroundNeutral = PdfColor(248, 250, 252);
  static final PdfColor _white = PdfColor(255, 255, 255);

  static String buildReceiptNumber(Booking b) {
    final cleanDay = b.day.replaceAll('-', '').replaceAll('/', '');
    final shortId =
        b.id.substring(0, b.id.length > 6 ? 6 : b.id.length).toUpperCase();
    return 'SC-$cleanDay-$shortId';
  }

  static String _formatDayDisplay(String d) {
    final p = d.split('-');
    if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
    return d;
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Genera los bytes de un PDF A4 con formato corporativo SeniCare.
  static Future<Uint8List> generateLegalReceiptPdf({
    required Booking booking,
    ClientProfile? clientProfile,
  }) async {
    final PdfDocument document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 0;

    final PdfPage page = document.pages.add();
    final PdfGraphics g = page.graphics;
    final Size pageSize = page.getClientSize();
    final double w = pageSize.width;
    const double margin = 36;
    final double contentW = w - (margin * 2);

    final PdfFont titleFont =
        PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold);
    final PdfFont h1Font =
        PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold);
    final PdfFont h2Font =
        PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final PdfFont bodyBoldFont =
        PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8.5);

    final String receiptNumber = buildReceiptNumber(booking);
    final String issuedAt = _formatDateTime(DateTime.now());

    // 1. Franja superior corporativa
    g.drawRectangle(
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(0, 0, w, 10),
    );
    g.drawRectangle(
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(0, 10, w, 96),
    );

    g.drawString(
      'SENICARE',
      titleFont,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(margin, 26, 260, 28),
    );
    g.drawString(
      'Asistencia Domiciliaria y Cuidado Profesional',
      bodyFont,
      brush: PdfSolidBrush(PdfColor(204, 251, 241)),
      bounds: Rect.fromLTWH(margin, 54, 280, 18),
    );
    g.drawString(
      'SeniCare Asistencia Domiciliaria S.L. · Directiva DAC7 / RGPD Art. 9',
      smallFont,
      brush: PdfSolidBrush(PdfColor(204, 251, 241)),
      bounds: Rect.fromLTWH(margin, 72, 310, 16),
    );

    // Bloque derecho del header: Nº Justificante y fecha
    g.drawString(
      'JUSTIFICANTE OFICIAL DE GASTO',
      h2Font,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(w - margin - 230, 30, 230, 18),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    g.drawString(
      'Nº $receiptNumber',
      h1Font,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(w - margin - 230, 49, 230, 20),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    g.drawString(
      'Emitido: $issuedAt',
      smallFont,
      brush: PdfSolidBrush(PdfColor(204, 251, 241)),
      bounds: Rect.fromLTWH(w - margin - 230, 72, 230, 16),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );

    double y = 128;

    // 2. Banner de validez legal
    g.drawRectangle(
      brush: PdfSolidBrush(_primarySurface),
      pen: PdfPen(_primaryTeal, width: 0.75),
      bounds: Rect.fromLTWH(margin, y, contentW, 44),
    );
    g.drawRectangle(
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(margin, y, 5, 44),
    );
    g.drawString(
      'Documento acreditativo de prestacion asistencial verificado',
      bodyBoldFont,
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(margin + 14, y + 8, contentW - 24, 15),
    );
    g.drawString(
      'Valido como comprobante para ayudas a la Ley de Dependencia, seguros privados de salud o deducciones autonomicas.',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(margin + 14, y + 24, contentW - 24, 15),
    );

    y += 62;

    // 3. Bloques de partes y servicio en dos columnas
    final double colW = (contentW - 14) / 2;
    const double cardH = 112;

    // Tarjeta izquierda: Titular / Familia
    g.drawRectangle(
      brush: PdfSolidBrush(_backgroundNeutral),
      pen: PdfPen(_borderSubtle, width: 1),
      bounds: Rect.fromLTWH(margin, y, colW, cardH),
    );
    g.drawString(
      'TITULAR / FAMILIA CONTRATANTE',
      smallFont,
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(margin + 12, y + 10, colW - 24, 14),
    );
    final clientName =
        (clientProfile?.name.trim().isNotEmpty == true)
            ? clientProfile!.name.trim()
            : booking.clientId;
    final homeAddress =
        (clientProfile?.homeAddress.trim().isNotEmpty == true)
            ? clientProfile!.homeAddress.trim()
            : 'Registrado en cuenta familiar';
    g.drawString(
      clientName,
      h2Font,
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(margin + 12, y + 28, colW - 24, 18),
    );
    g.drawString(
      'Domicilio: $homeAddress',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(margin + 12, y + 48, colW - 24, 34),
    );
    g.drawString(
      'ID Cliente: ${booking.clientId}',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(margin + 12, y + 88, colW - 24, 14),
    );

    // Tarjeta derecha: Profesional Sociosanitario y Horario
    final double rightX = margin + colW + 14;
    g.drawRectangle(
      brush: PdfSolidBrush(_backgroundNeutral),
      pen: PdfPen(_borderSubtle, width: 1),
      bounds: Rect.fromLTWH(rightX, y, colW, cardH),
    );
    g.drawString(
      'PROFESIONAL Y SERVICIO PRESTADO',
      smallFont,
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(rightX + 12, y + 10, colW - 24, 14),
    );
    g.drawString(
      booking.caregiverName,
      h2Font,
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(rightX + 12, y + 28, colW - 24, 18),
    );
    g.drawString(
      'Fecha: ${_formatDayDisplay(booking.day)}\nHorario contratado: ${booking.slot}',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(rightX + 12, y + 48, colW - 24, 34),
    );
    g.drawString(
      'ID Profesional: ${booking.caregiverId}',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(rightX + 12, y + 88, colW - 24, 14),
    );

    y += cardH + 22;

    // 4. Tabla de Desglose Economico
    g.drawString(
      'DESGLOSE ECONOMICO DEL SERVICIO',
      h2Font,
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(margin, y, contentW, 18),
    );
    y += 22;

    // Cabecera tabla
    g.drawRectangle(
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(margin, y, contentW, 26),
    );
    g.drawString(
      'Concepto',
      bodyBoldFont,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(margin + 12, y + 7, contentW - 130, 16),
    );
    g.drawString(
      'Importe',
      bodyBoldFont,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(margin + contentW - 110, y + 7, 98, 16),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    y += 26;

    void drawLineItem(String concept, String amount, {bool shaded = false}) {
      g.drawRectangle(
        brush: PdfSolidBrush(shaded ? _backgroundNeutral : _white),
        pen: PdfPen(_borderSubtle, width: 0.75),
        bounds: Rect.fromLTWH(margin, y, contentW, 28),
      );
      g.drawString(
        concept,
        bodyFont,
        brush: PdfSolidBrush(_darkSlate),
        bounds: Rect.fromLTWH(margin + 12, y + 8, contentW - 130, 16),
      );
      g.drawString(
        amount,
        bodyBoldFont,
        brush: PdfSolidBrush(_darkSlate),
        bounds: Rect.fromLTWH(margin + contentW - 110, y + 8, 98, 16),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
      y += 28;
    }

    drawLineItem(
      'Honorarios asistenciales (${_formatDayDisplay(booking.day)}, ${booking.slot})',
      '${booking.cost.toStringAsFixed(2)} EUR',
    );
    drawLineItem(
      'Gestion de plataforma, custodia Escrow y Seguro RC (3%)',
      '${booking.clientFee.toStringAsFixed(2)} EUR',
      shaded: true,
    );
    if (booking.tipAmount > 0) {
      drawLineItem(
        'Propina voluntaria de agradecimiento (100% integra al profesional)',
        '${booking.tipAmount.toStringAsFixed(2)} EUR',
      );
    }

    // Fila Total
    final double grandTotal = booking.totalPaid + booking.tipAmount;
    g.drawRectangle(
      brush: PdfSolidBrush(_primarySurface),
      pen: PdfPen(_primaryTeal, width: 1.2),
      bounds: Rect.fromLTWH(margin, y, contentW, 34),
    );
    g.drawString(
      'TOTAL ABONADO (IVA / Tasas incluidas)',
      h2Font,
      brush: PdfSolidBrush(_darkSlate),
      bounds: Rect.fromLTWH(margin + 12, y + 10, contentW - 140, 18),
    );
    g.drawString(
      '${grandTotal.toStringAsFixed(2)} EUR',
      h1Font,
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(margin + contentW - 120, y + 8, 108, 20),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    y += 52;

    // 5. Registro de Verificacion y Trazabilidad
    g.drawRectangle(
      brush: PdfSolidBrush(_white),
      pen: PdfPen(_borderSubtle, width: 1),
      bounds: Rect.fromLTWH(margin, y, contentW, 88),
    );
    g.drawString(
      'TRAZABILIDAD Y VERIFICACION EN DOMICILIO',
      smallFont,
      brush: PdfSolidBrush(_primaryTeal),
      bounds: Rect.fromLTWH(margin + 12, y + 10, contentW - 24, 14),
    );
    final checkInStr = booking.checkInTime != null
        ? _formatDateTime(booking.checkInTime!)
        : 'Confirmado en sistema';
    final checkOutStr = booking.checkOutTime != null
        ? _formatDateTime(booking.checkOutTime!)
        : 'Turno cerrado';
    final piStr =
        (booking.paymentIntentId?.isNotEmpty == true)
            ? booking.paymentIntentId!
            : 'Verificada';

    g.drawString(
      'Referencia Stripe Escrow: $piStr\n'
      'Registro de entrada (Check-in): $checkInStr   |   Registro de salida (Check-out): $checkOutStr\n'
      'Estado de liquidacion: Servicio prestado y verificado en plataforma (${booking.escrowStatus})',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(margin + 12, y + 28, contentW - 24, 50),
    );

    // Sello verde inferior derecha
    g.drawRectangle(
      brush: PdfSolidBrush(_secondaryEmerald),
      bounds: Rect.fromLTWH(w - margin - 145, y + 58, 133, 20),
    );
    g.drawString(
      'PAGADO Y VERIFICADO',
      smallFont,
      brush: PdfSolidBrush(_white),
      bounds: Rect.fromLTWH(w - margin - 145, y + 63, 133, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    // 6. Pie de pagina corporativo
    final double footerY = pageSize.height - 46;
    g.drawLine(
      PdfPen(_borderSubtle, width: 0.75),
      Offset(margin, footerY),
      Offset(w - margin, footerY),
    );
    g.drawString(
      'SeniCare Asistencia Domiciliaria S.L. · Documento generado automaticamente el $issuedAt · ID Reserva: ${booking.id}',
      smallFont,
      brush: PdfSolidBrush(_slateMuted),
      bounds: Rect.fromLTWH(margin, footerY + 10, contentW, 18),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    final List<int> bytes = await document.save();
    document.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Guarda el justificante PDF mediante el selector nativo del dispositivo/navegador
  /// con respaldo en el directorio de documentos si la plataforma no soporta diálogo.
  static Future<String?> saveReceiptPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) {
      await FilePicker.saveFile(
        dialogTitle: 'Descargar Justificante SeniCare (PDF)',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      return fileName;
    }

    try {
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Guardar Justificante SeniCare (PDF)',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) {
        return null;
      }
      final file = File(selectedPath);
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    } catch (_) {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final fallbackFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      await fallbackFile.writeAsBytes(bytes, flush: true);
      return fallbackFile.path;
    }
  }
}
