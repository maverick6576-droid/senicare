import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';

/// Holds global keys for all spotlight targets across caregiver tabs.
/// Created and owned by [MainLayout] so standalone screens remain decoupled.
class CaregiverTutorialTargets {
  final GlobalKey bottomNavKey = GlobalKey(debugLabel: 'tut_bottom_nav');
  final GlobalKey topRightActionsKey = GlobalKey(debugLabel: 'tut_top_right');

  // Inicio (CaregiverDashboard)
  final GlobalKey dashboardAvailabilityKey =
      GlobalKey(debugLabel: 'tut_dash_availability');
  final GlobalKey dashboardStatsKey = GlobalKey(debugLabel: 'tut_dash_stats');
  final GlobalKey dashboardServiceFlowKey =
      GlobalKey(debugLabel: 'tut_dash_service');
  final GlobalKey dashboardCommissionsKey =
      GlobalKey(debugLabel: 'tut_dash_commissions');

  // Ofertas (OffersHubScreen)
  final GlobalKey offersHeaderKey = GlobalKey(debugLabel: 'tut_offers_header');

  // Reservas (BookingsScreen)
  final GlobalKey bookingsToolbarKey =
      GlobalKey(debugLabel: 'tut_bookings_toolbar');

  // Mensajes (InboxScreen)
  final GlobalKey inboxToolbarKey = GlobalKey(debugLabel: 'tut_inbox_toolbar');
  final GlobalKey inboxNewChatFabKey =
      GlobalKey(debugLabel: 'tut_inbox_new_chat');

  // Mi Perfil (CaregiverProfileEditScreen)
  final GlobalKey profileStatusKey =
      GlobalKey(debugLabel: 'tut_profile_status');
  final GlobalKey profileDocsKey = GlobalKey(debugLabel: 'tut_profile_docs');
}

/// Exposes [CaregiverTutorialTargets] to caregiver tab widgets hosted in
/// [MainLayout]. Routes pushed outside [MainLayout] safely get `null`.
class TutorialScope extends InheritedWidget {
  final CaregiverTutorialTargets targets;

  const TutorialScope({
    super.key,
    required this.targets,
    required super.child,
  });

  static CaregiverTutorialTargets? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TutorialScope>()?.targets;
  }

  @override
  bool updateShouldNotify(TutorialScope oldWidget) =>
      targets != oldWidget.targets;
}

class CaregiverTutorialStep {
  final String tag;
  final String title;
  final String description;
  final List<String> bullets;
  final IconData icon;
  final int tabIndex;
  final double scrollAlignment;
  final GlobalKey? Function(CaregiverTutorialTargets targets) targetSelector;
  final GlobalKey? Function(CaregiverTutorialTargets targets)? fallbackSelector;

  const CaregiverTutorialStep({
    required this.tag,
    required this.title,
    required this.description,
    this.bullets = const [],
    required this.icon,
    required this.tabIndex,
    this.scrollAlignment = 0.14,
    required this.targetSelector,
    this.fallbackSelector,
  });

  static List<CaregiverTutorialStep> get steps => [
        CaregiverTutorialStep(
          tag: 'Primeros pasos',
          title: '¡Bienvenido/a a SeniCare!',
          description:
              'Esta guía te explica de forma sencilla cómo funciona toda la app. Desde aquí abajo te mueves entre las 5 secciones: Inicio, Ofertas, Reservas, Mensajes y Mi Perfil.',
          icon: Icons.explore_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Inicio · Horarios',
          title: 'Marca tus días disponibles',
          description:
              'Pulsa en "Horarios" para elegir qué días y horas puedes trabajar. Así las familias solo te pedirán turnos cuando estés libre.',
          icon: Icons.calendar_month_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.dashboardAvailabilityKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Inicio · Ingresos',
          title: 'Controla lo que has cobrado',
          description:
              'En "Cobrado" ves el dinero ya ingresado y lo que está en custodia segura (se libera a las 24h de terminar un turno). En "Realizados" ves tus servicios completados.',
          icon: Icons.euro_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.dashboardStatsKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Inicio · Tu turno',
          title: 'Cómo hacer cada servicio',
          description:
              'Cuando tengas un servicio confirmado, sigue estos 3 pasos fáciles:',
          bullets: const [
            'Pulsa "Estoy en camino" al salir hacia el domicilio.',
            'Al llegar, ficha entrada escaneando el QR o con el PIN.',
            'Marca las tareas realizadas y pulsa "Finalizar" al irte.',
          ],
          icon: Icons.verified_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.dashboardServiceFlowKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Inicio · Comisiones',
          title: 'Cuanto más cuidas, más ganas',
          description:
              'Empiezas recibiendo el 82% neto de tu tarifa. Al acumular horas con una familia, tu comisión baja hasta solo el 6% (recibes el 94%). ¡Las propinas son 100% para ti!',
          icon: Icons.trending_up_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.dashboardCommissionsKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Ofertas · Empleo',
          title: 'Encuentra ofertas cerca de ti',
          description:
              'Las familias publican trabajos dentro de tu radio en kilómetros. Filtra por "Urgentes" o "Mejor pagadas", entra en la que te interese para postularte y sigue su estado en "Mis Solicitudes".',
          icon: Icons.work_outline_rounded,
          tabIndex: 1,
          targetSelector: (t) => t.offersHeaderKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Reservas · Agenda',
          title: 'Gestiona turnos e incidencias',
          description:
              'Filtra por "Por aceptar" para confirmar solicitudes o "Hoy" para ver tus citas del día. Desde aquí fichas entrada/salida, consultas "Mi horario" y revisas tu historial pagado.',
          icon: Icons.event_note_rounded,
          tabIndex: 2,
          targetSelector: (t) => t.bookingsToolbarKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Mensajes · Chat',
          title: 'Habla directo con las familias',
          description:
              'Chatea en tiempo real como en WhatsApp: envía mensajes, audios o fotos del cuidado. Toca el botón "+" abajo a la derecha si quieres iniciar conversación desde una reserva.',
          icon: Icons.chat_bubble_outline_rounded,
          tabIndex: 3,
          targetSelector: (t) => t.inboxToolbarKey,
          fallbackSelector: (t) => t.inboxNewChatFabKey,
        ),
        CaregiverTutorialStep(
          tag: 'Mi Perfil · Visibilidad',
          title: 'Tu ficha y vista previa',
          description:
              'Comprueba qué pasos te faltan para estar visible, pulsa "Editar perfil" para cambiar tu tarifa, experiencia, especialidades o radio, y toca "Vista previa" para ver cómo te ven las familias.',
          icon: Icons.badge_outlined,
          tabIndex: 4,
          targetSelector: (t) => t.profileStatusKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Mi Perfil · Seguridad',
          title: 'Documentos y cuenta bancaria',
          description:
              'Sube aquí tu DNI/NIE y Certificado de Penales para conseguir el sello de Verificado, y conecta tu cuenta bancaria (Stripe) para recibir tus cobros puntualmente.',
          icon: Icons.account_balance_rounded,
          tabIndex: 4,
          scrollAlignment: 0.25,
          targetSelector: (t) => t.profileDocsKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
        CaregiverTutorialStep(
          tag: 'Ajustes y Ayuda',
          title: 'Letra grande y repetir tutorial',
          description:
              'Arriba a la derecha (en Ajustes ⚙️ o el menú ⋮) puedes activar el Modo Senior (+30% de letra más grande), revisar tu seguro y volver a ver este tutorial siempre que quieras.',
          icon: Icons.settings_rounded,
          tabIndex: 0,
          targetSelector: (t) => t.topRightActionsKey,
          fallbackSelector: (t) => t.bottomNavKey,
        ),
      ];
}

class CaregiverTutorialOverlay extends StatefulWidget {
  final CaregiverTutorialTargets targets;
  final int currentTabIndex;
  final ValueChanged<int> onSwitchTab;
  final VoidCallback onExit;
  final VoidCallback onFinish;

  const CaregiverTutorialOverlay({
    super.key,
    required this.targets,
    required this.currentTabIndex,
    required this.onSwitchTab,
    required this.onExit,
    required this.onFinish,
  });

  @override
  State<CaregiverTutorialOverlay> createState() =>
      _CaregiverTutorialOverlayState();
}

class _CaregiverTutorialOverlayState extends State<CaregiverTutorialOverlay> {
  final List<CaregiverTutorialStep> _steps = CaregiverTutorialStep.steps;
  int _stepIndex = 0;
  Rect? _spotlightRect;
  Rect? _previousRect;
  int _resolveGeneration = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolveStep();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _goToStep(int newIndex) {
    if (newIndex < 0 || newIndex >= _steps.length) return;
    _retryTimer?.cancel();
    setState(() {
      _previousRect = _spotlightRect;
      _stepIndex = newIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolveStep();
    });
  }

  void _resolveStep() {
    final gen = ++_resolveGeneration;
    final step = _steps[_stepIndex];

    if (widget.currentTabIndex != step.tabIndex) {
      widget.onSwitchTab(step.tabIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _resolveGeneration) {
          _attemptLocateTarget(gen, attempt: 0);
        }
      });
    } else {
      _attemptLocateTarget(gen, attempt: 0);
    }
  }

  Future<void> _attemptLocateTarget(int gen, {required int attempt}) async {
    if (!mounted || gen != _resolveGeneration) return;
    final step = _steps[_stepIndex];
    final primaryKey = step.targetSelector(widget.targets);
    final primaryCtx = primaryKey?.currentContext;

    if (primaryCtx == null) {
      // Show fallback spotlight right away so user never sees a blank wait.
      if (attempt == 0) {
        final fallbackCtx =
            step.fallbackSelector?.call(widget.targets)?.currentContext ??
                widget.targets.bottomNavKey.currentContext;
        if (fallbackCtx != null) {
          _applyRectFromContext(fallbackCtx);
        }
      }
      if (attempt < 10) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 60), () {
          if (mounted && gen == _resolveGeneration) {
            _attemptLocateTarget(gen, attempt: attempt + 1);
          }
        });
      }
      return;
    }

    if (Scrollable.maybeOf(primaryCtx) != null) {
      try {
        await Scrollable.ensureVisible(
          primaryCtx,
          alignment: step.scrollAlignment,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
      if (!mounted || gen != _resolveGeneration) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || gen != _resolveGeneration) return;
        final updatedCtx = primaryKey?.currentContext;
        if (updatedCtx != null) {
          _applyRectFromContext(updatedCtx);
        }
      });
      return;
    }

    _applyRectFromContext(primaryCtx);
  }

  void _applyRectFromContext(BuildContext targetCtx) {
    final overlayBox = context.findRenderObject() as RenderBox?;
    final targetBox = targetCtx.findRenderObject();
    if (overlayBox == null ||
        !overlayBox.hasSize ||
        targetBox is! RenderBox ||
        !targetBox.hasSize ||
        !targetBox.attached) {
      return;
    }

    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final raw = topLeft & targetBox.size;
    final screen = overlayBox.size;
    final padded = Rect.fromLTRB(
      math.max(4.0, raw.left - 6.0),
      math.max(4.0, raw.top - 6.0),
      math.min(screen.width - 4.0, raw.right + 6.0),
      math.min(screen.height - 4.0, raw.bottom + 6.0),
    );

    if (mounted) {
      setState(() {
        _previousRect = _spotlightRect ?? padded;
        _spotlightRect = padded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    final isSenior = config.seniorMode;
    final fontMult = isSenior ? 1.15 : 1.0;

    final step = _steps[_stepIndex];
    final bool isFirst = _stepIndex == 0;
    final bool isLast = _stepIndex == _steps.length - 1;

    final mq = MediaQuery.of(context);
    final size = mq.size;
    final safeTop = mq.padding.top + 10.0;
    final safeBottom = mq.padding.bottom + 12.0;

    final Rect? targetRect = _spotlightRect;
    final double spaceAbove =
        targetRect != null ? (targetRect.top - safeTop) : 0.0;
    final double spaceBelow = targetRect != null
        ? ((size.height - safeBottom) - targetRect.bottom)
        : size.height;

    final bool placeCardBelow = targetRect == null || spaceBelow >= spaceAbove;
    final double rawAvailable = targetRect == null
        ? (size.height - safeTop - safeBottom)
        : (placeCardBelow ? spaceBelow : spaceAbove) - 16.0;
    final double maxCardHeight = rawAvailable.clamp(190.0, size.height * 0.58);

    return KeyedSubtree(
      key: const Key('caregiver_tutorial_overlay'),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Intercept background touches so user cannot click dimmed widgets
            _buildSpotlightBackdrop(targetRect),
            Positioned(
              left: 16,
              right: 16,
              top: placeCardBelow ? null : safeTop,
              bottom: placeCardBelow ? safeBottom : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxCardHeight),
                child: _buildTutorialCard(
                  step: step,
                  isFirst: isFirst,
                  isLast: isLast,
                  isSenior: isSenior,
                  fontMult: fontMult,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotlightBackdrop(Rect? targetRect) {
    Widget paintFor(Rect? rect) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: CustomPaint(
            painter: _SpotlightPainter(highlightRect: rect),
            child: const SizedBox.expand(),
          ),
        );

    if (targetRect == null) {
      return paintFor(null);
    }

    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(
        begin: _previousRect ?? targetRect,
        end: targetRect,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animatedRect, _) => paintFor(animatedRect),
    );
  }

  Widget _buildTutorialCard({
    required CaregiverTutorialStep step,
    required bool isFirst,
    required bool isLast,
    required bool isSenior,
    required double fontMult,
  }) {
    final double progress = (_stepIndex + 1) / _steps.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar: Tag + step count + always-visible Exit button
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          step.tag,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11.5 * fontMult,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Paso ${_stepIndex + 1} de ${_steps.length}',
                        style: TextStyle(
                          fontSize: 12 * fontMult,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('caregiver_tutorial_exit_button'),
                  onPressed: widget.onExit,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: Text(
                    'Salir',
                    style: TextStyle(
                      fontSize: 13 * fontMult,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.darkSlate,
                    side: const BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size(0, isSenior ? 42 : 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.backgroundNeutral,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            step.icon,
                            color: AppTheme.primary,
                            size: isSenior ? 26 : 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step.title,
                            style: TextStyle(
                              fontSize: 17.5 * fontMult,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.darkSlate,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      step.description,
                      style: TextStyle(
                        fontSize: 14 * fontMult,
                        color: AppTheme.darkSlate,
                        height: 1.45,
                      ),
                    ),
                    if (step.bullets.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...step.bullets.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    fontSize: 13.5 * fontMult,
                                    color: AppTheme.darkSlate,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!isFirst) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('caregiver_tutorial_prev_button'),
                      onPressed: () => _goToStep(_stepIndex - 1),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(
                        'Anterior',
                        style: TextStyle(
                          fontSize: 14 * fontMult,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.darkSlate,
                        minimumSize: Size(0, isSenior ? 50 : 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const Key('caregiver_tutorial_next_button'),
                    onPressed: isLast
                        ? widget.onFinish
                        : () => _goToStep(_stepIndex + 1),
                    icon: Icon(
                      isLast
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_rounded,
                      size: 19,
                    ),
                    label: Text(
                      isLast ? '¡Entendido, empezar!' : 'Siguiente',
                      style: TextStyle(
                        fontSize: 14.5 * fontMult,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size(0, isSenior ? 50 : 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;

  const _SpotlightPainter({required this.highlightRect});

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Offset.zero & size);
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.78);

    if (highlightRect == null) {
      canvas.drawPath(fullScreen, overlayPaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      highlightRect!,
      const Radius.circular(16),
    );
    final cutout = Path()..addRRect(rrect);
    final combined = Path.combine(PathOperation.difference, fullScreen, cutout);

    canvas.drawPath(combined, overlayPaint);

    // Subtle soft glow + crisp bright ring around illuminated element
    final glowPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      highlightRect != oldDelegate.highlightRect;
}
