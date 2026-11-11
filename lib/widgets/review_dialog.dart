import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class ReviewDialog extends StatefulWidget {
  final List<Booking> bookings;

  const ReviewDialog({super.key, required this.bookings});

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  double _punctuality = 5.0;
  double _empathy = 5.0;
  double _communication = 5.0;
  double _hygiene = 5.0;
  double _selectedTip = 0.0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  double get _overallRating =>
      double.parse(((_punctuality + _empathy + _communication + _hygiene) / 4.0).toStringAsFixed(1));

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Widget _buildCategoryRow(
    String label,
    IconData icon,
    double currentVal,
    ValueChanged<double> onChanged, {
    bool seniorMode = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: seniorMode ? 18 : 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: seniorMode ? 15 : 13.5,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
              Text(
                currentVal.toStringAsFixed(0),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.amber,
                  fontSize: seniorMode ? 16 : 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final starValue = index + 1.0;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(starValue);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    index < currentVal ? Icons.star_rounded : Icons.star_border_rounded,
                    color: AppTheme.amber,
                    size: seniorMode ? 32 : 28,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overall = _overallRating;
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          const Icon(Icons.stars_rounded, color: AppTheme.amber, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Valorar Servicio',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: seniorMode ? 20 : 18,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$overall ★',
              style: const TextStyle(color: AppTheme.darkSlate, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Qué tal ha sido la experiencia con ${widget.bookings.first.caregiverName}?',
              style: TextStyle(
                color: AppTheme.slateMuted,
                fontSize: seniorMode ? 15.5 : 14,
              ),
            ),
            const SizedBox(height: 12),
            _buildCategoryRow(
              'Puntualidad y asistencia',
              Icons.schedule_rounded,
              _punctuality,
              (v) => setState(() => _punctuality = v),
              seniorMode: seniorMode,
            ),
            _buildCategoryRow(
              'Trato humano y empatía',
              Icons.favorite_border_rounded,
              _empathy,
              (v) => setState(() => _empathy = v),
              seniorMode: seniorMode,
            ),
            _buildCategoryRow(
              'Comunicación con la familia',
              Icons.chat_bubble_outline_rounded,
              _communication,
              (v) => setState(() => _communication = v),
              seniorMode: seniorMode,
            ),
            _buildCategoryRow(
              'Higiene y profesionalidad',
              Icons.verified_user_outlined,
              _hygiene,
              (v) => setState(() => _hygiene = v),
              seniorMode: seniorMode,
            ),
            if (overall >= 4.0 &&
                context.read<AuthNotifier>().canManageFamilyPayments) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.volunteer_activism_rounded, color: AppTheme.primary, size: 18),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '¿Añadir una propina de agradecimiento?',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.darkSlate),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'El 100% de la propina va íntegra para el cuidador sin comisión.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [0.0, 2.0, 5.0, 10.0].map((amount) {
                        final isSelected = _selectedTip == amount;
                        final label = amount == 0.0 ? 'Sin propina' : '☕ +${amount.toInt()} €';
                        return ChoiceChip(
                          label: Text(label),
                          selected: isSelected,
                          selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                          ),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedTip = amount);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Cuéntanos qué es lo que más te ha gustado del cuidado (opcional)...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (overall < 3.0 &&
                context.read<AuthNotifier>().canManageFamilyPayments)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(context: context, builder: (_) => DisputeDialog(booking: widget.bookings.first));
                    },
                    icon: const Icon(Icons.report_problem, size: 16),
                    label: const Text('Abrir Disputa / Informar de un problema'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Más tarde'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting
              ? null
              : () async {
                  HapticFeedback.mediumImpact();
                  setState(() => _isSubmitting = true);
                  try {
                    final auth = context.read<AuthNotifier>();
                    final effectiveClientId = auth.effectiveClientId ?? auth.currentUserId;
                    final allowedTip = auth.canManageFamilyPayments ? _selectedTip : 0.0;
                    await context.read<BookingNotifier>().submitReviewForBookings(
                          widget.bookings,
                          overall,
                          _commentController.text.trim(),
                          effectiveClientId,
                          punctualityRating: _punctuality,
                          empathyRating: _empathy,
                          communicationRating: _communication,
                          hygieneRating: _hygiene,
                          tipAmount: allowedTip,
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomSnackBar.show(
                        context,
                        message: allowedTip > 0
                            ? '¡Reseña y propina de ${allowedTip.toInt()}€ enviadas con éxito!'
                            : '¡Reseña enviada! Gracias por ayudar a otras familias.',
                        type: SnackBarType.success,
                      );
                    }
                  } catch (e) {
                    debugPrint('Error in submitReviewForBookings: $e');
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: 'Error al enviar reseña.', type: SnackBarType.error);
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar Valoración'),
        ),
      ],
    );
  }
}
