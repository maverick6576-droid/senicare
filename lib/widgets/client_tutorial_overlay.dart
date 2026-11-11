import 'package:flutter/material.dart';
import 'package:senicare/widgets/caregiver_tutorial_overlay.dart';
import 'package:senicare/widgets/spotlight_tutorial_overlay.dart';

/// Shared tutorial target keys including both Caregiver and Client anchors
/// provided down the tree via [TutorialScope].
class AppTutorialTargets extends CaregiverTutorialTargets {
  final GlobalKey explorerHeaderKey =
      GlobalKey(debugLabel: 'client_explorer_header');
  final GlobalKey explorerFirstCardKey =
      GlobalKey(debugLabel: 'client_explorer_first_card');
  final GlobalKey clientOffersFabKey =
      GlobalKey(debugLabel: 'client_offers_fab');
  final GlobalKey clientBookingsHeaderKey =
      GlobalKey(debugLabel: 'client_bookings_header');
  final GlobalKey clientFirstBookingKey =
      GlobalKey(debugLabel: 'client_first_booking');
  final GlobalKey clientProfileHeaderKey =
      GlobalKey(debugLabel: 'client_profile_header');

  static AppTutorialTargets? maybeClientOf(BuildContext context) {
    final targets = TutorialScope.maybeOf(context);
    return targets is AppTutorialTargets ? targets : null;
  }
}

/// Interactive step-by-step spotlight tutorial for Client (Family) users.
class ClientTutorialOverlay extends StatelessWidget {
  final AppTutorialTargets targets;
  final int currentTabIndex;
  final ValueChanged<int> onSwitchTab;
  final VoidCallback onExit;
  final VoidCallback onFinish;

  const ClientTutorialOverlay({
    super.key,
    required this.targets,
    required this.currentTabIndex,
    required this.onSwitchTab,
    required this.onExit,
    required this.onFinish,
  });

  List<SpotlightTutorialStep> _buildSteps() => [
        SpotlightTutorialStep(
          tabIndex: 0,
          targetKey: targets.bottomNavKey,
          tag: 'Bienvenida',
          icon: Icons.waving_hand_rounded,
          title: '¡Bienvenido a SeniCare!',
          description:
              'En pocos pasos verás cómo encontrar cuidador de confianza, reservar con pago seguro y seguir cada cuidado.',
          bullets: const [
            'Usa las 5 pestañas inferiores para moverte por la app',
            'Pulsa "Salir" arriba si prefieres explorar por tu cuenta',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 0,
          targetKey: targets.explorerHeaderKey,
          tag: 'Explorar · Filtros',
          icon: Icons.travel_explore_rounded,
          title: 'Busca cuidadores de tu zona',
          description:
              'Busca por nombre, barrio o cuidado, abre el Mapa o filtra rápido por cercanía, precio y disponibilidad.',
          bullets: const [
            '"Filtrar" ajusta especialidad, idioma o tarifa por hora',
            'Pulsa "Mapa" para ver cuidadores cerca de tu domicilio',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 0,
          targetKey: targets.explorerFirstCardKey,
          tag: 'Explorar · Perfiles',
          icon: Icons.verified_user_rounded,
          title: 'Elige con total tranquilidad',
          description:
              'Abre cualquier cuidador para ver su DNI verificado, formación, valoraciones reales o usa el Asistente guiado.',
          bullets: const [
            'Revisa tarifas transparentes antes de enviar solicitud',
            'Puedes escribirle por chat si tienes dudas previas',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 1,
          targetKey: targets.clientOffersFabKey,
          tag: 'Ofertas · Publicar',
          icon: Icons.post_add_rounded,
          title: 'Publica tu oferta y elige candidato',
          description:
              'Si prefieres que los cuidadores te escriban a ti, pulsa "+ Publicar Oferta" con tu horario y presupuesto.',
          bullets: const [
            'Recibirás candidaturas con mensaje y tarifa propuesta',
            'En "Activas" comparas perfiles y aceptas al mejor',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 2,
          targetKey: targets.clientBookingsHeaderKey,
          tag: 'Reservas · Pago Seguro',
          icon: Icons.event_available_rounded,
          title: 'Agenda y pago protegido',
          description:
              'Consulta tus citas activas y pasadas. Tu pago queda protegido en custodia (Escrow) hasta terminar el servicio.',
          bullets: const [
            'Filtra por "Por confirmar", "Hoy / En curso" o "Historial"',
            'Gestiona cambios o incidencias con respaldo seguro',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 2,
          targetKey: targets.clientFirstBookingKey,
          tag: 'Reservas · En directo',
          icon: Icons.qr_code_2_rounded,
          title: 'Código PIN/QR y Diario del Cuidado',
          description:
              'Al llegar el cuidador validáis la entrada con código PIN o QR, sigues su Diario del Cuidado y al acabar lo valoras.',
          bullets: const [
            'Revisa medicación, comidas y notas del turno al instante',
            'Solo al finalizar y confirmar se libera el pago y dejas reseña',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 3,
          targetKey: targets.inboxToolbarKey,
          tag: 'Mensajes · Chat',
          icon: Icons.chat_bubble_rounded,
          title: 'Habla directo como en WhatsApp',
          description:
              'Envía mensajes, fotos, notas rápidas y ubicación al cuidador con aviso de entregado y leído en tiempo real.',
          bullets: const [
            'Busca conversaciones o filtra solo los mensajes no leídos',
            'Pulsa el botón verde de abajo para iniciar un chat nuevo',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 4,
          targetKey: targets.clientProfileHeaderKey,
          tag: 'Mi Perfil · Familia',
          icon: Icons.family_restroom_rounded,
          title: 'Ficha familiar y checklist',
          description:
              'Guarda las necesidades médicas de tu mayor, prepara tu Checklist habitual de tareas y autoriza a otros familiares.',
          bullets: const [
            'Tu Checklist habitual se añade rápido en cada reserva',
            'Los familiares autorizados reciben avisos del cuidado',
          ],
        ),
        SpotlightTutorialStep(
          tabIndex: 4,
          targetKey: targets.topRightActionsKey,
          tag: 'Ajustes · Accesibilidad',
          icon: Icons.tune_rounded,
          title: 'Modo Senior y tutorial arriba',
          description:
              'Arriba a la derecha activas el Modo Senior (letra XL), revisas tu seguro RC y RGPD o repites este tutorial.',
          bullets: const [
            'El icono de engranaje abre Ajustes, Modo Senior y ayuda',
            'El menú de tres puntos guarda acceso rápido al Tutorial',
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return SpotlightTutorialOverlay(
      key: const Key('client_tutorial_overlay'),
      cardKey: const Key('client_tutorial_card'),
      exitButtonKey: const Key('client_tutorial_exit_button'),
      prevButtonKey: const Key('client_tutorial_prev_button'),
      nextButtonKey: const Key('client_tutorial_next_button'),
      steps: _buildSteps(),
      currentTabIndex: currentTabIndex,
      onSwitchTab: onSwitchTab,
      onExit: onExit,
      onFinish: onFinish,
    );
  }
}
