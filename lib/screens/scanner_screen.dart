import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';

class ScannerScreen extends StatefulWidget {
  final Booking booking;
  const ScannerScreen({super.key, required this.booking});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isProcessing = false;
  final TextEditingController _pinController = TextEditingController();

  Future<void> _handleQRDetect(String rawValue) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final normalized = rawValue.trim();
    final isValidBookingQr = normalized == widget.booking.id ||
        normalized == 'client_qr_${widget.booking.clientId}' ||
        normalized == 'booking_qr_${widget.booking.id}';

    if (isValidBookingQr) {
      try {
        final position = await Geolocator.getCurrentPosition();
        
        if (widget.booking.clientLatitude != null && widget.booking.clientLongitude != null) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            widget.booking.clientLatitude!,
            widget.booking.clientLongitude!,
          );
          
          if (distance > 100) {
            _showError('Estás a ${distance.toInt()}m de la casa. Debes estar a menos de 100m.');
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _isProcessing = false);
            });
            return;
          }
        }
        
        await _completeCheckIn();
      } catch (e) {
        _showError('No se pudo obtener la ubicación GPS.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    } else {
      _showError('QR Inválido. No pertenece a esta familia.');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isProcessing = false);
      });
    }
  }

  void _handlePINSubmit() async {
    if (_pinController.text == widget.booking.bookingPin) {
      if (_isProcessing) return;
      setState(() => _isProcessing = true);
      await _completeCheckIn();
    } else {
      _showError('PIN Incorrecto');
    }
  }

  Future<void> _completeCheckIn() async {
    try {
      await context.read<BookingNotifier>().checkInBooking(widget.booking.id);
      if (!mounted) return;
      CustomSnackBar.show(context, message: '✅ Fichaje completado con éxito', type: SnackBarType.success);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showError('Error interno o regla de seguridad denegada: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: '⚠️ $message', type: SnackBarType.error);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fichar Llegada'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Escanear QR'),
              Tab(icon: Icon(Icons.password), text: 'Código PIN'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: QR Scanner
            Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (_isProcessing) return;
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        _handleQRDetect(barcode.rawValue!);
                        break;
                      }
                    }
                  },
                ),
                if (_isProcessing)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  bottom: 24, left: 24, right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Escanea el QR de la nevera o puerta del domicilio.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ),
                )
              ],
            ),
            // Tab 2: PIN Input
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: AppTheme.primary),
                  const SizedBox(height: 16),
                  const Text('Introduce el PIN de 4 dígitos proporcionado por la familia.', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '----',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handlePINSubmit,
                      child: _isProcessing 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text('Validar PIN'),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

