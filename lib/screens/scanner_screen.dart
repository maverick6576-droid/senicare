import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  bool _validateCheckInWindow() {
    final start = widget.booking.scheduledStartTime;
    final end = widget.booking.scheduledEndTime;
    final now = DateTime.now();

    if (start != null && now.isBefore(start.subtract(const Duration(minutes: 30)))) {
      final diff = start.difference(now);
      final waitHours = diff.inHours;
      final waitMins = diff.inMinutes % 60;
      final waitText = waitHours > 0 ? '${waitHours}h y ${waitMins}m' : '${waitMins}m';
      _showError('Aún es pronto para este turno. El fichaje se habilitará 30 min antes del inicio (en $waitText).');
      return false;
    }

    if (end != null && now.isAfter(end)) {
      _showError('El horario previsto de este servicio ya ha concluido (${widget.booking.slot}). Contacta con soporte.');
      return false;
    }

    return true;
  }

  Future<void> _handleQRDetect(String rawValue) async {
    if (_isProcessing) return;
    if (!_validateCheckInWindow()) return;
    setState(() => _isProcessing = true);

    final normalized = rawValue.trim();
    final isValidBookingQr = normalized == widget.booking.id ||
        normalized == 'client_qr_${widget.booking.clientId}' ||
        normalized == 'booking_qr_${widget.booking.id}';

    if (isValidBookingQr) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _showError('Activa el GPS de tu dispositivo o introduce el PIN de la familia.');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isProcessing = false);
          });
          return;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            _showError('Permiso de ubicación denegado. Puedes usar la pestaña de PIN.');
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _isProcessing = false);
            });
            return;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          _showError('Permisos de GPS denegados permanentemente. Usa el código PIN.');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isProcessing = false);
          });
          return;
        }

        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        
        if (widget.booking.clientLatitude != null && widget.booking.clientLongitude != null) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            widget.booking.clientLatitude!,
            widget.booking.clientLongitude!,
          );
          
          final effectiveDistance = (distance - position.accuracy).clamp(0.0, double.infinity);
          if (distance > 250 && effectiveDistance > 150) {
            _showError('Estás a ${distance.toInt()}m del domicilio. Si el GPS falla en interiores, usa el "Código PIN".');
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _isProcessing = false);
            });
            return;
          }
        }
        
        await _completeCheckIn();
      } catch (e) {
        _showError('No se pudo verificar el GPS. Puedes usar el PIN para fichar.');
        Future.delayed(const Duration(seconds: 3), () {
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
    if (!_validateCheckInWindow()) return;
    final entered = _pinController.text.trim();
    final expected = (widget.booking.bookingPin ?? '').trim();
    if (entered.isNotEmpty && entered == expected) {
      if (_isProcessing) return;
      setState(() => _isProcessing = true);
      await _completeCheckIn();
    } else {
      _showError('PIN Incorrecto. Comprueba los 4 dígitos facilitados por la familia.');
    }
  }

  Future<void> _completeCheckIn() async {
    try {
      await context.read<BookingNotifier>().checkInBooking(widget.booking.id);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AppTheme.secondaryColor,
                    size: 56,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '¡Llegada Verificada!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkSlate,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'La familia ha sido notificada en tiempo real y tu Diario del Cuidado ya está activo.',
                style: TextStyle(fontSize: 13.5, color: AppTheme.slateMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Continuar al servicio'),
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
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

