import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentUserLocation;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final auth = context.read<AuthNotifier>();
    if (auth.currentRole == 'client' && auth.currentClient?.latitude != null && auth.currentClient?.longitude != null) {
      setState(() {
        _currentUserLocation = LatLng(auth.currentClient!.latitude!, auth.currentClient!.longitude!);
      });
      return;
    }

    final location = context.read<LocationNotifier>();
    if (location.latitude != null && location.longitude != null) {
      setState(() {
        _currentUserLocation = LatLng(location.latitude!, location.longitude!);
      });
    } else {
      await location.initLocation();
      if (location.latitude != null && location.longitude != null) {
        setState(() {
          _currentUserLocation = LatLng(location.latitude!, location.longitude!);
        });
      }
    }
  }

  void _onPositionChanged(MapCamera position, bool hasGesture) {
    if (!hasGesture) return;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<CaregiverNotifier>().loadMoreCaregivers(
        mapLat: position.center.latitude,
        mapLng: position.center.longitude,
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentUserLocation ?? const LatLng(40.4168, -3.7038);
    final caregivers = context.watch<CaregiverNotifier>().filteredCaregivers;

    double maxRadius = 5000.0;
    if (_currentUserLocation != null) {
      for (var c in caregivers) {
        if (c.latitude != null && c.longitude != null) {
          double dist = calculateDistance(_currentUserLocation!.latitude, _currentUserLocation!.longitude, c.latitude!, c.longitude!);
          if (dist * 1000 > maxRadius) maxRadius = dist * 1000;
        }
      }
      maxRadius = maxRadius * 1.1; 
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuidadores Cercanos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.borderSubtle),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.0,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.senicare.app',
              ),
              if (_currentUserLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentUserLocation!,
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      borderColor: AppTheme.primary,
                      borderStrokeWidth: 2,
                      useRadiusInMeter: true,
                      radius: maxRadius,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_currentUserLocation != null)
                    Marker(
                      point: _currentUserLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ...caregivers.where((c) => c.latitude != null && c.longitude != null).map((c) {
                    return Marker(
                      point: LatLng(c.latitude!, c.longitude!),
                      width: 86,
                      height: 54,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaregiverDetailScreen(caregiver: c),
                            ),
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: c.isSuperCaregiver ? Colors.amber.shade600 : AppTheme.primary,
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipOval(
                                    child: c.imageUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: c.imageUrl,
                                            width: 20,
                                            height: 20,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, _, _) => Container(
                                              width: 20,
                                              height: 20,
                                              color: AppTheme.primarySurface,
                                              child: const Icon(Icons.person, size: 14, color: AppTheme.primary),
                                            ),
                                          )
                                        : Container(
                                            width: 20,
                                            height: 20,
                                            color: AppTheme.primarySurface,
                                            child: const Icon(Icons.person, size: 14, color: AppTheme.primary),
                                          ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${c.pricePerHour.toInt()}€',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.darkSlate,
                                    ),
                                  ),
                                  if (c.isSuperCaregiver)
                                    const Text('🏆', style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primary, size: 18),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          if (context.watch<CaregiverNotifier>().isFetchingCaregivers)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Buscando en esta zona...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.my_location, color: Colors.white),
        onPressed: () {
          if (_currentUserLocation != null) {
            _mapController.move(_currentUserLocation!, 14.0);
          }
        },
      ),
    );
  }
}