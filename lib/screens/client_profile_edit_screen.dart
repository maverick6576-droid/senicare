import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/address_form_widget.dart';
import 'package:senicare/widgets/widgets.dart';

class ClientProfileEditScreen extends StatefulWidget {
  const ClientProfileEditScreen({super.key});

  @override
  State<ClientProfileEditScreen> createState() =>
      _ClientProfileEditScreenState();
}

class _ClientProfileEditScreenState extends State<ClientProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _patientDetailsCtrl;
  final TextEditingController _newChecklistCtrl = TextEditingController();
  final TextEditingController _newFamilyEmailCtrl = TextEditingController();

  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;
  bool _isQuickSaving = false;
  bool _isResolvingGps = false;
  bool _isEditing = false;

  ClientProfile? _profile;
  String? _loadedUserId;
  List<String> _defaultChecklist = [];
  List<String> _authorizedFamilyEmails = [];
  double? _homeLat;
  double? _homeLon;
  String _initialAddressSnapshot = '';

  static const List<String> _quickChecklistPresets = [
    '💊 Tomar medicación pautada',
    '🍲 Preparar comida e hidratación',
    '🚶 Paseo diario de 30-40 min',
    '🧠 Ejercicios de memoria y charla',
    '🚿 Apoyo en higiene personal',
  ];

  static const List<String> _healthPreferenceChips = [
    '🥗 Dieta baja en sal',
    '🥗 Dieta para diabéticos',
    '🍲 Textura blanda / triturada',
    '🚶 Usa bastón o andador',
    '♿ Silla de ruedas',
    '🩺 Control de tensión arterial',
    '🎵 Le gusta la música y conversar',
    '🌳 Disfruta paseando al aire libre',
  ];

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _patientDetailsCtrl = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _patientDetailsCtrl.dispose();
    _newChecklistCtrl.dispose();
    _newFamilyEmailCtrl.dispose();
    super.dispose();
  }

  void _syncDraftFromProfile(ClientProfile profile) {
    _profile = profile;
    _nameCtrl.text = profile.name == 'Sin nombre' ? '' : profile.name;
    _phoneCtrl.text = profile.phone;
    _addressCtrl.text = profile.homeAddress;
    _initialAddressSnapshot = profile.homeAddress;
    _patientDetailsCtrl.text = profile.patientDetails;
    _defaultChecklist = List<String>.from(profile.defaultCareChecklist);
    _authorizedFamilyEmails = List<String>.from(profile.authorizedFamilyEmails);
    _homeLat = profile.latitude;
    _homeLon = profile.longitude;
  }

  Future<void> _loadProfile({bool invalidateCache = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      _loadedUserId = userId;
      if (userId == null || userId.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = 'No hay una sesión activa.';
          });
        }
        return;
      }

      if (invalidateCache &&
          DependencyInjection.clients is FirestoreClientRepository) {
        (DependencyInjection.clients as FirestoreClientRepository)
            .invalidateCache(userId);
      }

      final fetched = await DependencyInjection.clients.getClient(userId);
      if (!mounted || auth.currentUserId != userId) return;

      final resolved = fetched ?? auth.currentClient;
      if (resolved == null) {
        setState(() {
          _isLoading = false;
          _loadError =
              'No hemos encontrado tu ficha familiar. Pulsa Reintentar para cargarla.';
        });
        return;
      }

      auth.currentClient = resolved;
      setState(() {
        _syncDraftFromProfile(resolved);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading client profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'No se pudo cargar tu perfil. Comprueba tu conexión.';
        });
      }
    }
  }

  List<String> _computeMissingItems(ClientProfile profile) {
    final missing = <String>[];
    final hasDefaultName =
        profile.name.trim().isEmpty || profile.name.trim() == 'Sin nombre';
    if (hasDefaultName) missing.add('Nombre completo');
    if (profile.phone.trim().isEmpty) missing.add('Teléfono de contacto');
    if (profile.homeAddress.trim().isEmpty) {
      missing.add('Domicilio de cuidado');
    }
    if (profile.latitude == null || profile.longitude == null) {
      missing.add('Ubicación en el mapa');
    }
    if (profile.patientDetails.trim().isEmpty) {
      missing.add('Ficha de la persona a cuidar');
    }
    return missing;
  }

  String _extractInitials(String rawName) {
    final cleaned = rawName.trim();
    if (cleaned.isEmpty || cleaned == 'Sin nombre') return 'F';
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _persistQuickUpdate({
    required Map<String, dynamic> fields,
    required ClientProfile optimisticProfile,
    required VoidCallback onRollback,
    String? successMessage,
  }) async {
    if (_isQuickSaving || _profile == null) return;
    final auth = context.read<AuthNotifier>();
    final userId = auth.currentUserId;
    if (userId == null || userId.trim().isEmpty) {
      onRollback();
      CustomSnackBar.show(
        context,
        message: 'No hay una sesión activa para guardar los cambios.',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() {
      _isQuickSaving = true;
      _profile = optimisticProfile;
    });

    try {
      await DependencyInjection.clients.updateClient(userId, fields);
      final fresh =
          await DependencyInjection.clients.getClient(userId) ?? optimisticProfile;
      if (!mounted) return;
      auth.currentClient = fresh;
      auth.forceRefresh();
      setState(() => _syncDraftFromProfile(fresh));
      if (successMessage != null) {
        CustomSnackBar.show(
          context,
          message: successMessage,
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      debugPrint('Error saving client quick update: $e');
      if (!mounted) return;
      setState(onRollback);
      CustomSnackBar.show(
        context,
        message: 'No se pudo guardar el cambio. Comprueba tu conexión.',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _isQuickSaving = false);
    }
  }

  Future<void> _togglePreferenceChip(String chip, bool selected) async {
    if (_profile == null) return;
    final previousProfile = _profile!;
    final tokens = previousProfile.patientDetails
        .split('•')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (selected) {
      if (!tokens.contains(chip)) tokens.add(chip);
    } else {
      tokens.removeWhere((t) => t == chip);
    }

    final nextDetails = tokens.join(' • ');
    final optimistic = previousProfile.copyWith(patientDetails: nextDetails);
    _patientDetailsCtrl.text = nextDetails;

    await _persistQuickUpdate(
      fields: {'patientDetails': nextDetails},
      optimisticProfile: optimistic,
      onRollback: () => _syncDraftFromProfile(previousProfile),
    );
  }

  Future<void> _addChecklistTask([String? preset]) async {
    if (_profile == null) return;
    final val = (preset ?? _newChecklistCtrl.text).trim();
    if (val.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Escribe una tarea antes de añadirla.',
        type: SnackBarType.warning,
      );
      return;
    }

    final exists =
        _defaultChecklist.any((t) => t.toLowerCase() == val.toLowerCase());
    if (exists) {
      CustomSnackBar.show(
        context,
        message: 'Esta tarea ya está en tu checklist habitual.',
        type: SnackBarType.info,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final previousProfile = _profile!;
    final previousList = List<String>.from(_defaultChecklist);
    final nextList = [..._defaultChecklist, val];
    setState(() {
      _defaultChecklist = nextList;
      if (preset == null) _newChecklistCtrl.clear();
    });

    await _persistQuickUpdate(
      fields: {'defaultCareChecklist': nextList},
      optimisticProfile: previousProfile.copyWith(defaultCareChecklist: nextList),
      onRollback: () {
        _defaultChecklist = previousList;
        _profile = previousProfile;
      },
    );
  }

  Future<void> _removeChecklistTask(String task) async {
    if (_profile == null) return;
    HapticFeedback.selectionClick();
    final previousProfile = _profile!;
    final previousList = List<String>.from(_defaultChecklist);
    final nextList = _defaultChecklist.where((t) => t != task).toList();
    setState(() => _defaultChecklist = nextList);

    await _persistQuickUpdate(
      fields: {'defaultCareChecklist': nextList},
      optimisticProfile: previousProfile.copyWith(defaultCareChecklist: nextList),
      onRollback: () {
        _defaultChecklist = previousList;
        _profile = previousProfile;
      },
    );
  }

  Future<void> _inviteFamilyEmail() async {
    if (_profile == null) return;
    final email = _newFamilyEmailCtrl.text.trim().toLowerCase();
    if (!_emailRegex.hasMatch(email)) {
      CustomSnackBar.show(
        context,
        message: 'Introduce un correo electrónico válido (ej. maria@email.com).',
        type: SnackBarType.warning,
      );
      return;
    }
    if (_authorizedFamilyEmails.any((e) => e.toLowerCase() == email)) {
      CustomSnackBar.show(
        context,
        message: 'Este familiar ya está autorizado.',
        type: SnackBarType.info,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final previousProfile = _profile!;
    final previousList = List<String>.from(_authorizedFamilyEmails);
    final nextList = [..._authorizedFamilyEmails, email];
    setState(() {
      _authorizedFamilyEmails = nextList;
      _newFamilyEmailCtrl.clear();
    });

    await _persistQuickUpdate(
      fields: {'authorizedFamilyEmails': nextList},
      optimisticProfile:
          previousProfile.copyWith(authorizedFamilyEmails: nextList),
      onRollback: () {
        _authorizedFamilyEmails = previousList;
        _profile = previousProfile;
      },
      successMessage: 'Familiar autorizado correctamente.',
    );
  }

  Future<void> _removeFamilyEmail(String email) async {
    if (_profile == null) return;
    HapticFeedback.selectionClick();
    final previousProfile = _profile!;
    final previousList = List<String>.from(_authorizedFamilyEmails);
    final nextList =
        _authorizedFamilyEmails.where((e) => e != email).toList();
    setState(() => _authorizedFamilyEmails = nextList);

    await _persistQuickUpdate(
      fields: {'authorizedFamilyEmails': nextList},
      optimisticProfile:
          previousProfile.copyWith(authorizedFamilyEmails: nextList),
      onRollback: () {
        _authorizedFamilyEmails = previousList;
        _profile = previousProfile;
      },
    );
  }

  Future<void> _useCurrentGpsLocation() async {
    if (_isResolvingGps) return;
    setState(() => _isResolvingGps = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Activa la ubicación (GPS) del dispositivo.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado.');
      }

      final pos = await Geolocator.getCurrentPosition();
      final readable =
          await NominatimService.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;

      setState(() {
        _homeLat = pos.latitude;
        _homeLon = pos.longitude;
        if (readable != null && readable.trim().isNotEmpty) {
          _addressCtrl.text = readable.trim();
          _initialAddressSnapshot = readable.trim();
        }
      });
      CustomSnackBar.show(
        context,
        message: 'Ubicación GPS guardada correctamente.',
        type: SnackBarType.success,
      );
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo obtener la ubicación: $e',
          type: SnackBarType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isResolvingGps = false);
    }
  }

  Future<void> _geocodeMissingCoordinates() async {
    if (_profile == null || _isResolvingGps) return;
    final addr = _profile!.homeAddress.trim();
    if (addr.isEmpty) {
      setState(() => _isEditing = true);
      return;
    }

    setState(() => _isResolvingGps = true);
    try {
      final coords = await NominatimService.geocodeAddress(addr);
      if (!mounted) return;
      if (coords == null) {
        CustomSnackBar.show(
          context,
          message:
              'No pudimos ubicar esa dirección automáticamente. Edítala o usa el botón GPS.',
          type: SnackBarType.warning,
        );
        return;
      }

      final previousProfile = _profile!;
      await _persistQuickUpdate(
        fields: {'latitude': coords.latitude, 'longitude': coords.longitude},
        optimisticProfile: previousProfile.copyWith(
          latitude: coords.latitude,
          longitude: coords.longitude,
        ),
        onRollback: () => _syncDraftFromProfile(previousProfile),
        successMessage: 'Ubicación en el mapa actualizada correctamente.',
      );
    } finally {
      if (mounted) setState(() => _isResolvingGps = false);
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    final cleanName = _nameCtrl.text.trim();
    if (cleanName.isEmpty || cleanName == 'Sin nombre') {
      CustomSnackBar.show(
        context,
        message: 'Por favor, escribe tu nombre completo.',
        type: SnackBarType.error,
      );
      return;
    }

    final cleanPhone = _phoneCtrl.text.trim();
    if (cleanPhone.replaceAll(RegExp(r'\D'), '').length < 6) {
      CustomSnackBar.show(
        context,
        message: 'Introduce un teléfono de contacto válido.',
        type: SnackBarType.error,
      );
      return;
    }

    final cleanAddress = _addressCtrl.text.trim();
    if (cleanAddress.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Indica la dirección completa o usa el botón GPS.',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      _loadedUserId = userId;
      if (userId == null || userId.trim().isEmpty) {
        throw Exception('No hay una sesión activa.');
      }

      double? lat = _homeLat;
      double? lon = _homeLon;
      final addressUnchanged = cleanAddress == _initialAddressSnapshot;

      if (lat == null || lon == null) {
        if (addressUnchanged &&
            _profile?.latitude != null &&
            _profile?.longitude != null) {
          lat = _profile!.latitude;
          lon = _profile!.longitude;
        } else {
          final coords = await NominatimService.geocodeAddress(cleanAddress);
          if (coords != null) {
            lat = coords.latitude;
            lon = coords.longitude;
          } else if (addressUnchanged &&
              _profile?.latitude != null &&
              _profile?.longitude != null) {
            lat = _profile!.latitude;
            lon = _profile!.longitude;
          }
        }
      }

      final bool coordinatesMissing = lat == null || lon == null;

      final data = <String, dynamic>{
        'name': cleanName,
        'phone': cleanPhone,
        'homeAddress': cleanAddress,
        'patientDetails': _patientDetailsCtrl.text.trim(),
        'latitude': lat,
        'longitude': lon,
        'onboardingComplete': true,
        'defaultCareChecklist': _defaultChecklist,
        'authorizedFamilyEmails': _authorizedFamilyEmails,
      };

      await DependencyInjection.clients.updateClient(userId, data);
      final updatedProfile = await DependencyInjection.clients.getClient(userId) ??
          (_profile ??
                  ClientProfile(
                    id: userId,
                    name: cleanName,
                    phone: cleanPhone,
                    homeAddress: cleanAddress,
                    patientDetails: _patientDetailsCtrl.text.trim(),
                    onboardingComplete: true,
                  ))
              .copyWith(
            name: cleanName,
            phone: cleanPhone,
            homeAddress: cleanAddress,
            latitude: lat,
            longitude: lon,
            clearLocation: coordinatesMissing,
            patientDetails: _patientDetailsCtrl.text.trim(),
            onboardingComplete: true,
            defaultCareChecklist: _defaultChecklist,
            authorizedFamilyEmails: _authorizedFamilyEmails,
          );

      if (!mounted) return;
      auth.currentClient = updatedProfile;
      auth.onboardingComplete = true;
      auth.forceRefresh();

      setState(() {
        _syncDraftFromProfile(updatedProfile);
        _isEditing = false;
      });
      CustomSnackBar.show(
        context,
        message: coordinatesMissing
            ? 'Perfil guardado. Pulsa "Ubicar en el mapa" o usa GPS para ajustar tu ubicación.'
            : 'Perfil y ubicación actualizados correctamente',
        type: coordinatesMissing ? SnackBarType.warning : SnackBarType.success,
      );
    } catch (e) {
      debugPrint('Error saving client profile: $e');
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al guardar el perfil: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await CustomDialog.showConfirmation(
      context,
      title: 'Cerrar sesión',
      message: '¿Seguro que quieres salir de tu cuenta familiar?',
      confirmText: 'Cerrar sesión',
      cancelText: 'Cancelar',
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      await DependencyInjection.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    if (auth.currentUserId != _loadedUserId && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && auth.currentUserId != _loadedUserId && !_isLoading) {
          _loadProfile();
        }
      });
    }
    final config = context.watch<ConfigNotifier>();
    final isSenior = config.seniorMode;
    final fontMult = isSenior ? 1.2 : 1.0;
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    if (_isLoading) {
      return Scaffold(
        appBar: canPop ? AppBar(title: const Text('Mi Perfil Familiar')) : null,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'Cargando tu perfil familiar...',
                style: TextStyle(color: AppTheme.slateMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadError != null || _profile == null) {
      return Scaffold(
        appBar: canPop ? AppBar(title: const Text('Mi Perfil Familiar')) : null,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: AppTheme.slateMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'No pudimos cargar tu perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16 * fontMult,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  child: FilledButton.icon(
                    onPressed: () => _loadProfile(invalidateCache: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      'Reintentar',
                      style: TextStyle(fontSize: 15 * fontMult),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _confirmSignOut,
                  child: const Text(
                    'Cerrar sesión',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final missingItems = _computeMissingItems(profile);

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('Mi Perfil Familiar'),
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.darkSlate,
              elevation: 0,
            )
          : null,
      bottomNavigationBar: _isEditing
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, isSenior ? 52 : 46),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _syncDraftFromProfile(profile);
                                  _isEditing = false;
                                });
                              },
                        child: Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 15 * fontMult),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: Size(0, isSenior ? 52 : 46),
                        ),
                        onPressed: _isSaving ? null : _submit,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSaving ? 'Guardando...' : 'Guardar cambios',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15 * fontMult,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadProfile(invalidateCache: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: AppTutorialTargets.maybeClientOf(context)
                    ?.clientProfileHeaderKey,
                child: _buildHeaderCard(profile, missingItems, fontMult, isSenior),
              ),
              const SizedBox(height: 14),
              if (!_isEditing) ...[
                _buildStatusBanner(missingItems, fontMult),
                const SizedBox(height: 14),
                _buildQuickActionsRow(config, fontMult, isSenior),
                const SizedBox(height: 16),
                _buildReadOnlySections(profile, fontMult, isSenior),
              ] else ...[
                _buildEditingForm(profile, fontMult, isSenior),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    ClientProfile profile,
    List<String> missingItems,
    double fontMult,
    bool isSenior,
  ) {
    final displayName =
        profile.name.trim().isEmpty || profile.name.trim() == 'Sin nombre'
            ? 'Tu Familia'
            : profile.name.trim();
    final initials = _extractInitials(profile.name);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.modernCardDecoration(radius: 22),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isSenior ? 38 : 34,
                backgroundColor: AppTheme.primarySurface,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: isSenior ? 26 : 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 20 * fontMult,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (profile.phone.trim().isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 16 * fontMult,
                            color: AppTheme.slateMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              profile.phone.trim(),
                              style: TextStyle(
                                fontSize: 14 * fontMult,
                                color: AppTheme.slateMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Añade un teléfono de contacto',
                        style: TextStyle(
                          fontSize: 13 * fontMult,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Cuenta Familiar',
                            style: TextStyle(
                              fontSize: 12.5 * fontMult,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        if (missingItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Listo ✓',
                              style: TextStyle(
                                fontSize: 12.5 * fontMult,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF047857),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, isSenior ? 52 : 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(
                  'Editar perfil',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15 * fontMult,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBanner(List<String> missingItems, double fontMult) {
    const int totalSteps = 5;
    final int completedSteps = (totalSteps - missingItems.length).clamp(0, totalSteps);
    final double progress = completedSteps / totalSteps;
    final bool isComplete = missingItems.isEmpty;

    final Color bgColor =
        isComplete ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED);
    final Color borderColor =
        isComplete ? const Color(0xFFA7F3D0) : Colors.orange.shade200;
    final Color accentColor =
        isComplete ? const Color(0xFF047857) : Colors.orange.shade900;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.verified_rounded : Icons.checklist_rounded,
                color: accentColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isComplete
                      ? 'Perfil familiar completo ✓'
                      : 'Faltan ${missingItems.length} datos para tus reservas',
                  style: TextStyle(
                    fontSize: 15.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isComplete
                ? 'Los cuidadores ya cuentan con tu dirección y la ficha necesaria para atender a tu familiar con seguridad.'
                : 'Pendiente: ${missingItems.join(' • ')}',
            style: TextStyle(
              fontSize: 13.5 * fontMult,
              color: accentColor,
              height: 1.35,
            ),
          ),
          if (!isComplete) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$completedSteps de $totalSteps datos completados',
              style: TextStyle(
                fontSize: 12 * fontMult,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor),
                  backgroundColor: Colors.white.withValues(alpha: 0.75),
                ),
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(
                  'Completar ahora',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14 * fontMult,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow(
    ConfigNotifier config,
    double fontMult,
    bool isSenior,
  ) {
    final seniorTile = _ClientQuickTile(
      icon: Icons.text_increase_rounded,
      color: isSenior ? AppTheme.primary : AppTheme.darkSlate,
      title: 'Modo Senior',
      subtitle: isSenior ? 'Activado (Letra XL)' : 'Letra normal',
      isHighlighted: isSenior,
      fontMult: fontMult,
      onTap: () {
        HapticFeedback.mediumImpact();
        config.toggleSeniorMode(!isSenior);
      },
    );

    final settingsTile = _ClientQuickTile(
      icon: Icons.shield_outlined,
      color: AppTheme.primary,
      title: 'Seguridad y Ajustes',
      subtitle: 'Seguro RC y RGPD',
      fontMult: fontMult,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 330 && isSenior) {
          return Column(
            children: [
              seniorTile,
              const SizedBox(height: 10),
              settingsTile,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: seniorTile),
              const SizedBox(width: 12),
              Expanded(child: settingsTile),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReadOnlySections(
    ClientProfile profile,
    double fontMult,
    bool isSenior,
  ) {
    final hasAddress = profile.homeAddress.trim().isNotEmpty;
    final hasCoords = profile.latitude != null && profile.longitude != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientSectionCard(
          title: 'Domicilio donde se realiza el cuidado',
          icon: Icons.location_on_rounded,
          fontMult: fontMult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasAddress
                    ? profile.homeAddress.trim()
                    : 'Aún no has indicado la dirección del domicilio.',
                style: TextStyle(
                  fontSize: 15 * fontMult,
                  color: hasAddress ? AppTheme.darkSlate : AppTheme.slateMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    hasCoords
                        ? Icons.check_circle_rounded
                        : Icons.location_searching_rounded,
                    size: 16 * fontMult,
                    color: hasCoords
                        ? AppTheme.secondaryColor
                        : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasCoords
                          ? 'Ubicación en mapa configurada ✓'
                          : 'Falta ubicar la dirección en el mapa',
                      style: TextStyle(
                        fontSize: 13 * fontMult,
                        fontWeight: FontWeight.w600,
                        color: hasCoords
                            ? AppTheme.secondaryColor
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasAddress && !hasCoords) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed:
                      _isResolvingGps ? null : _geocodeMissingCoordinates,
                  icon: _isResolvingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(
                    _isResolvingGps ? 'Ubicando...' : 'Ubicar en el mapa',
                    style: TextStyle(fontSize: 13.5 * fontMult),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ClientSectionCard(
          title: 'Ficha de la Persona a Cuidar',
          icon: Icons.favorite_rounded,
          fontMult: fontMult,
          trailing: TextButton(
            onPressed: () => setState(() => _isEditing = true),
            child: Text(
              'Editar',
              style: TextStyle(fontSize: 13.5 * fontMult),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Text(
                  profile.patientDetails.trim().isEmpty
                      ? 'Sin especificar. Añade edad, movilidad, rutinas o cuidados especiales.'
                      : profile.patientDetails.trim(),
                  style: TextStyle(
                    fontSize: 14.5 * fontMult,
                    color: profile.patientDetails.trim().isEmpty
                        ? AppTheme.slateMuted
                        : AppTheme.darkSlate,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Esta ficha solo es visible para cuidadores con reserva o solicitud para ofrecer una atención más segura.',
                style: TextStyle(
                  fontSize: 12 * fontMult,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSeniorPreferencesQuickCard(fontMult),
        const SizedBox(height: 14),
        _buildFamilyDefaultChecklistCard(fontMult, isSenior),
        const SizedBox(height: 14),
        _buildSharedFamilyAccountCard(fontMult, isSenior),
        const SizedBox(height: 14),
        _buildAccountActionsCard(isSenior, fontMult),
      ],
    );
  }

  Widget _buildSeniorPreferencesQuickCard(double fontMult) {
    final currentTokens = (_profile?.patientDetails ?? _patientDetailsCtrl.text)
        .split('•')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medical_information_rounded,
                color: Colors.amber.shade900,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Etiquetas Rápidas de Salud y Preferencias',
                  style: TextStyle(
                    fontSize: 15 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Toca para añadir o quitar pautas rápidas que verá tu cuidador antes de llegar:',
            style: TextStyle(
              fontSize: 12.5 * fontMult,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _healthPreferenceChips.map((chip) {
              final isPresent = currentTokens.contains(chip);
              return FilterChip(
                label: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 12.5 * fontMult,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: isPresent,
                backgroundColor: Colors.white,
                selectedColor: Colors.amber.shade200,
                checkmarkColor: Colors.amber.shade900,
                onSelected: _isQuickSaving
                    ? null
                    : (selected) {
                        HapticFeedback.selectionClick();
                        _togglePreferenceChip(chip, selected);
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyDefaultChecklistCard(double fontMult, bool isSenior) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.playlist_add_check_circle_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checklist Habitual de Cuidado',
                  style: TextStyle(
                    fontSize: 16.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Define las tareas habituales de tu familiar. Se cargarán automáticamente en cada nueva reserva.',
            style: TextStyle(
              fontSize: 12.5 * fontMult,
              color: AppTheme.slateMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_defaultChecklist.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Aún no has definido tareas habituales. Toca una sugerencia o escribe una abajo:',
                style: TextStyle(
                  fontSize: 12.5 * fontMult,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.slateMuted,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _defaultChecklist.map((task) {
                return Chip(
                  backgroundColor: Colors.white,
                  label: Text(
                    task,
                    style: TextStyle(
                      fontSize: 12.5 * fontMult,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  deleteIcon: const Icon(Icons.close_rounded, size: 17),
                  deleteButtonTooltipMessage: 'Quitar tarea',
                  onDeleted:
                      _isQuickSaving ? null : () => _removeChecklistTask(task),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          _buildResponsiveAddRow(
            controller: _newChecklistCtrl,
            hintText: 'Añadir tarea (ej. Pastilla tensión 12:30)...',
            buttonLabel: 'Añadir',
            keyboardType: TextInputType.text,
            fontMult: fontMult,
            isSenior: isSenior,
            onSubmit: _isQuickSaving ? null : () => _addChecklistTask(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickChecklistPresets
                .where((p) => !_defaultChecklist.contains(p))
                .map(
                  (preset) => ActionChip(
                    backgroundColor: Colors.white,
                    label: Text(
                      '+ $preset',
                      style: TextStyle(fontSize: 12 * fontMult),
                    ),
                    onPressed:
                        _isQuickSaving ? null : () => _addChecklistTask(preset),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedFamilyAccountCard(double fontMult, bool isSenior) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.modernCardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.family_restroom_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cuenta Familiar Compartida',
                  style: TextStyle(
                    fontSize: 16.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Autoriza a otros familiares para que reciban avisos del Diario del Cuidado y vean el calendario de visitas.',
            style: TextStyle(
              fontSize: 12.5 * fontMult,
              color: AppTheme.slateMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_authorizedFamilyEmails.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _authorizedFamilyEmails.map((email) {
                return Chip(
                  avatar: const Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  backgroundColor: AppTheme.backgroundNeutral,
                  label: Text(
                    email,
                    style: TextStyle(
                      fontSize: 12.5 * fontMult,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  deleteIcon: const Icon(Icons.close_rounded, size: 17),
                  deleteButtonTooltipMessage: 'Quitar familiar',
                  onDeleted:
                      _isQuickSaving ? null : () => _removeFamilyEmail(email),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          _buildResponsiveAddRow(
            controller: _newFamilyEmailCtrl,
            hintText: 'Email del familiar (ej. hermano@email.com)',
            buttonLabel: 'Invitar',
            keyboardType: TextInputType.emailAddress,
            fontMult: fontMult,
            isSenior: isSenior,
            onSubmit: _isQuickSaving ? null : _inviteFamilyEmail,
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveAddRow({
    required TextEditingController controller,
    required String hintText,
    required String buttonLabel,
    required TextInputType keyboardType,
    required double fontMult,
    required bool isSenior,
    required VoidCallback? onSubmit,
  }) {
    final input = TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: TextStyle(fontSize: 14 * fontMult),
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final button = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size(isSenior ? 104 : 88, isSenior ? 48 : 42),
      ),
      onPressed: onSubmit,
      child: Text(
        buttonLabel,
        style: TextStyle(
          fontSize: 13.5 * fontMult,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340 && isSenior) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input,
              const SizedBox(height: 8),
              button,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: input),
            const SizedBox(width: 8),
            button,
          ],
        );
      },
    );
  }

  Widget _buildAccountActionsCard(bool isSenior, double fontMult) {
    return _ClientSectionCard(
      title: 'Privacidad y Cuenta',
      icon: Icons.tune_rounded,
      fontMult: fontMult,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.shield_outlined,
              color: AppTheme.primary,
            ),
            title: Text(
              'Ajustes, Seguro RC y Privacidad',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15 * fontMult,
              ),
            ),
            subtitle: Text(
              'Consulta coberturas, RGPD o elimina tu cuenta.',
              style: TextStyle(fontSize: 12.5 * fontMult),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const Divider(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
                fontSize: 15 * fontMult,
              ),
            ),
            onTap: _confirmSignOut,
          ),
        ],
      ),
    );
  }

  Widget _buildEditingForm(
    ClientProfile profile,
    double fontMult,
    bool isSenior,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClientSectionCard(
            title: 'Datos Personales',
            icon: Icons.person_outline_rounded,
            fontMult: fontMult,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(fontSize: 15.5 * fontMult),
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  style: TextStyle(fontSize: 15.5 * fontMult),
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de Contacto',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ClientSectionCard(
            title: 'Ubicación de Residencia',
            icon: Icons.map_outlined,
            fontMult: fontMult,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Los cuidadores cercanos y las distancias en Explorar se calculan desde este domicilio.',
                  style: TextStyle(
                    fontSize: 13 * fontMult,
                    color: AppTheme.slateMuted,
                  ),
                ),
                const SizedBox(height: 14),
                AddressFormWidget(
                  initialAddress: _addressCtrl.text,
                  onAddressChanged: (addr) {
                    _addressCtrl.text = addr;
                    if (addr != _initialAddressSnapshot) {
                      _homeLat = null;
                      _homeLon = null;
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isResolvingGps ? null : _useCurrentGpsLocation,
                    icon: _isResolvingGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(
                      _homeLat != null
                          ? 'Actualizar con mi ubicación GPS actual ✓'
                          : 'Usar mi ubicación GPS actual',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14 * fontMult),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ClientSectionCard(
            title: 'Detalles de la Persona a Cuidar',
            icon: Icons.medical_information_outlined,
            fontMult: fontMult,
            child: TextFormField(
              controller: _patientDetailsCtrl,
              style: TextStyle(fontSize: 15.5 * fontMult),
              decoration: const InputDecoration(
                labelText: 'Información relevante (edad, movilidad, rutinas)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double fontMult;
  final Widget child;
  final Widget? trailing;

  const _ClientSectionCard({
    required this.title,
    required this.icon,
    required this.fontMult,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.modernCardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.5 * fontMult,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ClientQuickTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double fontMult;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _ClientQuickTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.fontMult,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isHighlighted ? AppTheme.primarySurface : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isHighlighted
                  ? AppTheme.primary.withValues(alpha: 0.45)
                  : AppTheme.borderSubtle,
              width: isHighlighted ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5 * fontMult,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkSlate,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12 * fontMult,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
