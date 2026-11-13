import 'package:flutter/widgets.dart';

/// Soporte de internacionalización (l10n) para SeniCare (`es`, `ca`, `en`).
class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  static const List<Locale> supportedLocales = [
    Locale('es', 'ES'),
    Locale('ca', 'ES'),
    Locale('en', 'US'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('es', 'ES'));
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'es': {
      'appTitle': 'SeniCare',
      'offlineBanner': 'Sin conexión a Internet',
      'tabExplore': 'Explorar',
      'tabBookings': 'Reservas',
      'tabOffers': 'Ofertas',
      'tabInbox': 'Mensajes',
      'tabSettings': 'Mi Perfil',
      'tabHome': 'Inicio',
      'tabAgenda': 'Agenda',
      'settingsTitle': 'Ajustes y Preferencias',
      'languageSectionTitle': '🌐 Idioma de la Aplicación',
      'languageSectionSubtitle':
          'Cambia el idioma de los menús y avisos principales. Se guarda en tu dispositivo.',
      'languageSavedToast': 'Idioma actualizado',
      'seniorSectionTitle': '👓 Modo Senior & Accesibilidad Visual',
      'seniorToggleTitle': 'Activar Modo Senior (Letra Grande)',
      'seniorToggleSubtitle':
          'Aumenta el tamaño tipográfico (+30%) y el área de toque en toda la aplicación.',
      'seniorSavedToast': 'Modo Senior guardado en tus preferencias',
      'ok': 'OK',
      'close': 'Cerrar',
    },
    'ca': {
      'appTitle': 'SeniCare',
      'offlineBanner': 'Sense connexió a Internet',
      'tabExplore': 'Explorar',
      'tabBookings': 'Reserves',
      'tabOffers': 'Ofertes',
      'tabInbox': 'Missatges',
      'tabSettings': 'El meu perfil',
      'tabHome': 'Inici',
      'tabAgenda': 'Agenda',
      'settingsTitle': 'Ajustos i Preferències',
      'languageSectionTitle': '🌐 Idioma de l\'Aplicació',
      'languageSectionSubtitle':
          'Canvia l\'idioma dels menús i avisos principals. Es desa al dispositiu.',
      'languageSavedToast': 'Idioma actualitzat',
      'seniorSectionTitle': '👓 Mode Sènior i Accessibilitat Visual',
      'seniorToggleTitle': 'Activar Mode Sènior (Lletra Gran)',
      'seniorToggleSubtitle':
          'Augmenta la mida de la lletra (+30%) i l\'àrea tàctil a tota l\'aplicació.',
      'seniorSavedToast': 'Mode Sènior desat a les teves preferències',
      'ok': 'D\'acord',
      'close': 'Tancar',
    },
    'en': {
      'appTitle': 'SeniCare',
      'offlineBanner': 'No Internet connection',
      'tabExplore': 'Explore',
      'tabBookings': 'Bookings',
      'tabOffers': 'Job Offers',
      'tabInbox': 'Messages',
      'tabSettings': 'Profile',
      'tabHome': 'Home',
      'tabAgenda': 'Schedule',
      'settingsTitle': 'Settings & Preferences',
      'languageSectionTitle': '🌐 App Language',
      'languageSectionSubtitle':
          'Switch navigation and key notices language. Saved on your device.',
      'languageSavedToast': 'Language updated',
      'seniorSectionTitle': '👓 Senior Mode & Visual Accessibility',
      'seniorToggleTitle': 'Enable Senior Mode (Large Text)',
      'seniorToggleSubtitle':
          'Increases typography size (+30%) and touch targets across the entire app.',
      'seniorSavedToast': 'Senior Mode preference saved',
      'ok': 'OK',
      'close': 'Close',
    },
  };

  String _lookup(String key) {
    final lang = locale.languageCode.toLowerCase();
    return _localizedValues[lang]?[key] ??
        _localizedValues['es']![key] ??
        key;
  }

  String get appTitle => _lookup('appTitle');
  String get offlineBanner => _lookup('offlineBanner');
  String get tabExplore => _lookup('tabExplore');
  String get tabBookings => _lookup('tabBookings');
  String get tabOffers => _lookup('tabOffers');
  String get tabInbox => _lookup('tabInbox');
  String get tabSettings => _lookup('tabSettings');
  String get tabHome => _lookup('tabHome');
  String get tabAgenda => _lookup('tabAgenda');
  String get settingsTitle => _lookup('settingsTitle');
  String get languageSectionTitle => _lookup('languageSectionTitle');
  String get languageSectionSubtitle => _lookup('languageSectionSubtitle');
  String get languageSavedToast => _lookup('languageSavedToast');
  String get seniorSectionTitle => _lookup('seniorSectionTitle');
  String get seniorToggleTitle => _lookup('seniorToggleTitle');
  String get seniorToggleSubtitle => _lookup('seniorToggleSubtitle');
  String get seniorSavedToast => _lookup('seniorSavedToast');
  String get ok => _lookup('ok');
  String get close => _lookup('close');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['es', 'ca', 'en'].contains(locale.languageCode.toLowerCase());

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
