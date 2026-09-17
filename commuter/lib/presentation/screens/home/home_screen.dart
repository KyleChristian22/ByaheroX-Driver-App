import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/terminal_constants.dart';
import '../../../data/services/active_route_service.dart';
import '../../../data/services/ride_feedback_service.dart';
import '../../../domain/entities/jeepney.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/pickup_location_provider.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/map/jeepney_marker.dart';
import '../../widgets/ride_feedback_sheet.dart';

/// Home screen with map view showing jeepneys - Guest Mode optimized
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _MapBubbleTailPainter extends CustomPainter {
  const _MapBubbleTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MapBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final MapController _mapController;

  LatLng? _userLocation;
  bool _isLoadingLocation = false;
  StreamSubscription<Position>? _locationSubscription;
  DateTime? _lastLocationRetryAt;

  List<DriverRouteInfo> _activeRoutes = [];
  StreamSubscription<List<DriverRouteInfo>>? _routeSubscription;

  Jeepney? _selectedMapJeepney;
  String? _selectedTerminalLabel;
  double _mapRotation = 0;

  static const LatLng _defaultCenter = LatLng(14.14, 121.53);
  static const double _defaultZoom = 13.0;

  static const LatLng _terminalA = LatLng(
    14.1149875,
    121.551859375,
  ); // Lucban Public Market

  static const LatLng _terminalB = LatLng(
    14.2659625,
    121.425578125,
  ); // Sta. Cruz Terminal
  static final LatLngBounds _terminalBounds = LatLngBounds.fromPoints([
    _terminalA,
    _terminalB,
  ]);
  CameraFit _terminalCameraFitForContext(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return CameraFit.bounds(
      bounds: _terminalBounds,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 72 : 48,
        isCompact ? 270 : 230,
        isCompact ? 124 : 64,
        isCompact ? 210 : 130,
      ),
      minZoom: isCompact ? 9.2 : 10,
      maxZoom: isCompact ? 12.4 : 14,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authViewModel = context.read<AuthViewModel>();

      // Do NOT automatically sign in as guest here. Guest Mode should
      // only be activated when the user explicitly taps "Continue as
      // Guest" on the welcome screen. Auto-sign-in creates an anonymous
      // Firebase session that persists across app restarts, making it
      // feel like the app is forcing guest mode.

      if (!mounted) return;

      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;

      if (authViewModel.isGuest) {
        debugPrint('HomeScreen: Guest Mode entered home screen.');
      }

      debugPrint(
        'HomeScreen: FirebaseAuth currentUser '
        'uid=${firebaseUser?.uid ?? 'null'}, '
        'isAnonymous=${firebaseUser?.isAnonymous ?? false}',
      );

      context.read<JeepneyViewModel>().initialize();

      _startLocationTracking();
      _startWatchingActiveRoutes();

      if (authViewModel.isLoggedIn) {
        context.read<PickupLocationProvider>().startWatching(
          authViewModel.currentUser.id,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _routeSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_userLocation != null) return;
    if (_isLoadingLocation) return;

    final now = DateTime.now();
    if (_lastLocationRetryAt != null &&
        now.difference(_lastLocationRetryAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastLocationRetryAt = now;
    _startLocationTracking();
  }

  void _startWatchingActiveRoutes() {
    _routeSubscription?.cancel();

    _routeSubscription = DriverRouteService.watchActiveRoutes().listen(
      (routes) {
        if (!mounted) return;
        setState(() {
          _activeRoutes = routes;
        });
        debugPrint('Active routes stream update: ${routes.length} routes');
      },
      onError: (error) {
        debugPrint('Active routes stream error: $error');
      },
    );
  }

  Future<void> _refreshActiveRoutes() async {
    try {
      final routes = await DriverRouteService.getActiveRoutes();
      if (!mounted) return;
      setState(() {
        _activeRoutes = routes;
      });
    } catch (e) {
      debugPrint('Error refreshing active routes: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    if (_isLoadingLocation || _locationSubscription != null) return;

    await _getUserLocation();

    if (!mounted) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _locationSubscription?.cancel();

    try {
      _locationSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (Position position) {
              if (!mounted) return;

              final newLocation = LatLng(position.latitude, position.longitude);

              setState(() {
                _userLocation = newLocation;
              });

              context.read<JeepneyViewModel>().updateUserLocation(
                position.latitude,
                position.longitude,
              );

              debugPrint(
                'User location updated: ${position.latitude}, ${position.longitude}',
              );
            },
            onError: (error) {
              debugPrint('Location stream error: $error');
            },
          );
    } catch (e) {
      debugPrint('Failed to start location stream: $e');
    }
  }

  Future<void> _getUserLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!mounted) return;

      if (!serviceEnabled) {
        setState(() {
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location not available. Please enable GPS.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.warning,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (!mounted) return;

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (!mounted) return;

        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission denied. Please enable it in app settings.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.warning,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      final newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _userLocation = newLocation;
        _isLoadingLocation = false;
      });

      context.read<JeepneyViewModel>().updateUserLocation(
        position.latitude,
        position.longitude,
      );

      debugPrint(
        'User location obtained: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('Get user location error: $e');

      if (!mounted) return;

      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _recenterToUserLocation({
    JeepneyViewModel? jeepneyViewModel,
    PickupLocationProvider? pickupProvider,
  }) {
    try {
      if (jeepneyViewModel != null &&
          pickupProvider != null &&
          _isOnboardMapMode(pickupProvider)) {
        final onboardJeepney = _findJeepneyById(
          jeepneyViewModel,
          pickupProvider.jeepneyId,
        );

        if (onboardJeepney != null &&
            _hasValidJeepneyLocation(onboardJeepney)) {
          _mapController.move(
            _displayLocationForJeepney(
              onboardJeepney,
              routes: _routesForMap(
                _safeVisibleActiveRoutes(jeepneyViewModel),
                pickupProvider,
              ),
            ),
            _defaultZoom,
          );
          return;
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to recenter to onboard jeepney: $e');
      debugPrint('StackTrace: $stackTrace');
    }

    if (_userLocation != null) {
      _mapController.move(_userLocation!, _defaultZoom);
      return;
    }

    _getUserLocation();
  }

  Color _getCrowdColor(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.maliwag:
        return AppColors.crowdMaliwag;
      case CrowdLevel.sakto:
        return AppColors.crowdSakto;
      case CrowdLevel.puno:
        return AppColors.crowdPuno;
    }
  }

  String _normalizeKey(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
  }

  /// Converts different terminal names/codes into one safe comparable value.
  ///
  /// Examples:
  /// Sta.Cruz Terminal -> sta_cruz
  /// Sta. Cruz Terminal -> sta_cruz
  /// Santa Cruz Terminal -> sta_cruz
  /// sta_cruz -> sta_cruz
  /// Terminal A -> lucban
  /// terminalA -> lucban
  /// Terminal B -> sta_cruz
  /// terminalB -> sta_cruz
  /// Lucban Public Market Terminal -> lucban
  /// lucban -> lucban
  String _canonicalTerminal(String? value) {
    final key = _normalizeKey(value);

    if (key.isEmpty) return '';

    if (key == 'terminala' || key.contains('lucban')) {
      return 'lucban';
    }

    if (key == 'terminalb' ||
        key.contains('stacruz') ||
        key.contains('santacruz')) {
      return 'sta_cruz';
    }

    return key;
  }

  bool _hasValidJeepneyLocation(Jeepney jeepney) {
    final lat = jeepney.latitude;
    final lng = jeepney.longitude;

    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180 &&
        !(lat == 0 && lng == 0);
  }

  bool _isOnboardMapMode(PickupLocationProvider pickupProvider) {
    return pickupProvider.isOnboard &&
        (pickupProvider.jeepneyId?.trim().isNotEmpty ?? false);
  }

  DriverRouteInfo? _routeForJeepney(
    List<DriverRouteInfo> routes,
    String? jeepneyId,
  ) {
    final targetId = _normalizeKey(jeepneyId);
    if (targetId.isEmpty) return null;

    for (final route in routes) {
      if (route.hasValidRoute && _normalizeKey(route.jeepneyId) == targetId) {
        return route;
      }
    }

    return null;
  }

  LatLng _displayLocationForJeepney(
    Jeepney jeepney, {
    List<DriverRouteInfo> routes = const [],
  }) {
    final baseLocation = LatLng(jeepney.latitude, jeepney.longitude);
    final route = _routeForJeepney(routes, jeepney.id);
    if (route == null || route.points.length < 2) return baseLocation;

    final elapsed = DateTime.now().difference(jeepney.lastUpdated);
    if (elapsed <= Duration.zero || elapsed > const Duration(seconds: 12)) {
      return baseLocation;
    }

    final speedMps = jeepney.speed / 3.6;
    if (!speedMps.isFinite || speedMps < 1.0) return baseLocation;

    final projectedMeters = (speedMps * elapsed.inMilliseconds / 1000)
        .clamp(0.0, 80.0)
        .toDouble();

    return _RouteProgressSegments.advanceAlongRoute(
          routePoints: route.points,
          currentLocation: baseLocation,
          distanceMeters: projectedMeters,
        ) ??
        baseLocation;
  }

  LatLng? _onboardDisplayLocation(
    JeepneyViewModel jeepneyViewModel,
    PickupLocationProvider pickupProvider,
    List<DriverRouteInfo> routes,
  ) {
    if (!_isOnboardMapMode(pickupProvider)) return null;

    final onboardJeepney = _findJeepneyById(
      jeepneyViewModel,
      pickupProvider.jeepneyId,
    );
    if (onboardJeepney == null || !_hasValidJeepneyLocation(onboardJeepney)) {
      return null;
    }

    return _displayLocationForJeepney(onboardJeepney, routes: routes);
  }

  bool _matchesSelectedRouteOrDestination(
    Jeepney jeepney,
    JeepneyViewModel viewModel,
  ) {
    if (!viewModel.hasRouteFilter) return true;

    return _destinationMatchesSelectedFilter(jeepney, viewModel);
  }

  bool _destinationMatchesSelectedFilter(
    Jeepney jeepney,
    JeepneyViewModel viewModel,
  ) {
    if (!viewModel.hasRouteFilter) return true;
    final routeFilter = viewModel.routeFilter!;

    final selectedDestinationCode = _canonicalTerminal(
      routeFilter.destinationTerminal,
    );

    final selectedDestinationLabel = _canonicalTerminal(
      TerminalConstants.fromCode(routeFilter.destinationTerminal),
    );

    final jeepneyDestination = _canonicalTerminal(jeepney.destinationTerminal);

    if (jeepneyDestination.isNotEmpty) {
      return jeepneyDestination == selectedDestinationCode ||
          jeepneyDestination == selectedDestinationLabel;
    }

    return false;
  }

  List<Jeepney> _filterActiveJeepneysBySelectedDestination(
    JeepneyViewModel viewModel,
  ) {
    if (!viewModel.hasRouteFilter) {
      debugPrint(
        'No selected route/destination filter. Returning all active/on-trip jeepneys: '
        '${viewModel.activeDriverLocations.length}',
      );
      return _sortJeepneysByDistance(
        viewModel.activeDriverLocations,
        viewModel,
      );
    }

    final routeFilter = viewModel.routeFilter!;

    debugPrint('=== FILTER ACTIVE JEEPNEYS ===');
    debugPrint('Selected routeId: ${routeFilter.routeId}');
    debugPrint('Selected destination raw: ${routeFilter.destinationTerminal}');
    debugPrint(
      'Selected destination label: ${TerminalConstants.fromCode(routeFilter.destinationTerminal)}',
    );
    debugPrint(
      'Selected destination canonical: ${_canonicalTerminal(routeFilter.destinationTerminal)}',
    );
    debugPrint(
      'Total activeDriverLocations: ${viewModel.activeDriverLocations.length}',
    );

    final filtered = viewModel.activeDriverLocations.where((jeepney) {
      final hasValidLocation = _hasValidJeepneyLocation(jeepney);
      final destinationMatches = _destinationMatchesSelectedFilter(
        jeepney,
        viewModel,
      );
      final matchesRouteOrDestination = _matchesSelectedRouteOrDestination(
        jeepney,
        viewModel,
      );

      debugPrint(
        'Jeepney check => '
        'id: ${jeepney.id}, '
        'plate: ${jeepney.plateNumber}, '
        'routeId: ${jeepney.routeId}, '
        'destinationTerminal: ${jeepney.destinationTerminal}, '
        'canonicalDestination: ${_canonicalTerminal(jeepney.destinationTerminal)}, '
        'isActive: ${jeepney.isActive}, '
        'lat: ${jeepney.latitude}, '
        'lng: ${jeepney.longitude}, '
        'validLocation: $hasValidLocation, '
        'destinationMatches: $destinationMatches, '
        'matches: $matchesRouteOrDestination',
      );

      if (!hasValidLocation) {
        debugPrint(
          'Skipped ${jeepney.id}: invalid coordinates '
          'lat=${jeepney.latitude}, lng=${jeepney.longitude}',
        );
        return false;
      }

      if (!jeepney.isActive) {
        debugPrint(
          'Skipped ${jeepney.id}: not active/onTrip according to repository data.',
        );
        return false;
      }

      if (!matchesRouteOrDestination) {
        debugPrint(
          'Skipped ${jeepney.id}: destination mismatch. '
          'selectedDestination=${routeFilter.destinationTerminal}, '
          'jeepneyDestination=${jeepney.destinationTerminal}',
        );
        return false;
      }

      return hasValidLocation && matchesRouteOrDestination;
    }).toList();

    debugPrint('Filtered active jeepneys: ${filtered.length}');

    return _sortJeepneysByDistance(filtered, viewModel);
  }

  List<Marker> _buildJeepneyMarkers(
    JeepneyViewModel viewModel, {
    PickupLocationProvider? pickupProvider,
    List<DriverRouteInfo> routes = const [],
  }) {
    final List<Jeepney> activeJeepneys;

    try {
      if (pickupProvider != null && _isOnboardMapMode(pickupProvider)) {
        final onboardJeepney = _findJeepneyById(
          viewModel,
          pickupProvider.jeepneyId,
        );

        if (onboardJeepney == null ||
            !_hasValidJeepneyLocation(onboardJeepney)) {
          debugPrint(
            'Onboard map mode: current jeepney location is unavailable. '
            'jeepneyId=${pickupProvider.jeepneyId}',
          );
          return const [];
        }

        activeJeepneys = [onboardJeepney];
      } else {
        activeJeepneys = viewModel.hasRouteFilter
            ? _filterActiveJeepneysBySelectedDestination(viewModel)
            : _sortJeepneysByDistance(
                viewModel.activeDriverLocations,
                viewModel,
              );
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to build jeepney markers safely: $e');
      debugPrint('StackTrace: $stackTrace');
      return const [];
    }

    if (!viewModel.hasRouteFilter) {
      debugPrint(
        'No route filter selected. Showing all active jeepney markers.',
      );
    }

    debugPrint('=== BUILD JEEPNEY MARKERS ===');
    debugPrint('Markers to display: ${activeJeepneys.length}');

    final markers = activeJeepneys.map((jeepney) {
      final markerPoint = _displayLocationForJeepney(jeepney, routes: routes);
      debugPrint(
        'Adding marker => ${jeepney.id} at ${markerPoint.latitude}, ${markerPoint.longitude}',
      );

      return Marker(
        point: markerPoint,
        width: AppDimensions.markerSizeMd,
        height: AppDimensions.markerSizeMd,
        child: JeepneyMarker(
          jeepney: jeepney,
          onTap: () => _showJeepneyBubble(jeepney),
        ),
      );
    }).toList();

    Jeepney? selected = _selectedMapJeepney;
    if (selected != null) {
      Jeepney? latestSelected;
      for (final jeepney in activeJeepneys) {
        if (jeepney.id == selected.id) {
          latestSelected = jeepney;
          break;
        }
      }
      selected = latestSelected;
      _selectedMapJeepney = latestSelected;
    }
    if (selected != null && _hasValidJeepneyLocation(selected)) {
      markers.add(
        _buildJeepneyMapBubble(
          selected,
          point: _displayLocationForJeepney(selected, routes: routes),
        ),
      );
    }

    return markers;
  }

  void _showJeepneyBubble(Jeepney jeepney) {
    setState(() {
      _selectedMapJeepney = _selectedMapJeepney?.id == jeepney.id
          ? null
          : jeepney;
    });
  }

  Marker _buildJeepneyMapBubble(Jeepney jeepney, {LatLng? point}) {
    final destination = jeepney.destinationTerminal?.trim().isNotEmpty == true
        ? jeepney.destinationTerminal!.trim()
        : 'N/A';
    final crowdLabel = jeepney.crowdLevelDisplayName;
    final passengerCountText = jeepney.maxCapacity > 0
        ? '${jeepney.passengerCount} / ${jeepney.maxCapacity}'
        : jeepney.passengerCount > 99
        ? '99+'
        : jeepney.passengerCount.toString();
    final passengers = '$passengerCountText - $crowdLabel';
    final jeepneyLabel = _jeepneyDisplayName(jeepney);

    final crowdColor = _getCrowdColor(jeepney.crowdLevel);

    return Marker(
      point: point ?? LatLng(jeepney.latitude, jeepney.longitude),
      width: 190,
      height: 210,
      rotate: true,
      child: Transform.translate(
        offset: const Offset(0, -148),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 174,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: crowdColor.withValues(alpha: 0.5)),
                boxShadow: AppDimensions.shadowMd,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMapBubbleLine(
                    Icons.directions_car_rounded,
                    'Plate No.',
                    jeepneyLabel,
                  ),
                  const SizedBox(height: 6),
                  _buildMapBubbleLine(
                    Icons.flag_rounded,
                    'Destination',
                    destination,
                  ),
                  const SizedBox(height: 6),
                  _buildMapBubbleLine(
                    Icons.groups_rounded,
                    'Passengers',
                    passengers,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: crowdColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: crowdColor.withValues(alpha: 0.4),
                              blurRadius: 3,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        crowdLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: crowdColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CustomPaint(
              size: const Size(18, 9),
              painter: _MapBubbleTailPainter(color: AppColors.surface),
            ),
          ],
        ),
      ),
    );
  }

  String _jeepneyDisplayName(Jeepney jeepney) {
    final plateNumber = jeepney.plateNumber.trim();
    if (plateNumber.isNotEmpty && plateNumber != jeepney.id.trim()) {
      return plateNumber;
    }

    return 'Jeepney';
  }

  Widget _buildMapBubbleLine(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendPickupNotification(Jeepney jeepney) async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      _showGuestRestrictionSnackBar('Please sign in to notify a driver');
      return;
    }

    final pickupProvider = context.read<PickupLocationProvider>();
    final jeepneyViewModel = context.read<JeepneyViewModel>();
    final userLocation = jeepneyViewModel.userLocation ?? _userLocation;

    if (pickupProvider.isBookedOnAnotherJeepney(jeepney.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You are already booked with another driver. Finish or cancel that booking first.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isJeepFull(jeepney)) {
      _showJeepFullSnackBar();
      return;
    }

    if (userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available. Please enable GPS.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final success = await pickupProvider.setPickupLocationFromGps(
      commuterId: authViewModel.currentUser.id,
      location: userLocation,
      routeId: jeepney.routeId,
      jeepneyId: jeepney.id,
      waitingCount: 1,
      destinationTerminal: jeepney.destinationTerminal,
    );

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location na ipinapakita sa driver.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } else if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pickupProvider.errorMessage ??
                'Could not notify driver. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  bool _isJeepFull(Jeepney jeepney) {
    return jeepney.maxCapacity > 0 &&
        jeepney.passengerCount >= jeepney.maxCapacity;
  }

  void _showJeepFullSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Jeep is full. Please choose another jeep or wait for available seats.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _goToLoginFromGuest() async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      await authViewModel.logout();
    }

    if (!mounted) return;
    context.go('/login');
  }

  void _showGuestRestrictionSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.warning,
        action: SnackBarAction(
          label: 'Sign In',
          textColor: Colors.white,
          onPressed: () => _goToLoginFromGuest(),
        ),
      ),
    );
  }

  void _showGuestSignInPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Sign in to notify drivers and book rides'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        action: SnackBarAction(
          label: 'Sign In',
          textColor: Colors.white,
          onPressed: () => _goToLoginFromGuest(),
        ),
      ),
    );
  }

  Future<void> _cancelPickupNotification() async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      _showGuestRestrictionSnackBar('Please sign in to cancel a booking');
      return;
    }

    final pickupProvider = context.read<PickupLocationProvider>();

    final success = await pickupProvider.cancelPickupLocation(
      authViewModel.currentUser.id,
    );

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _offboardPickupNotification() async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      _showGuestRestrictionSnackBar('Please sign in to drop off');
      return;
    }

    final pickupProvider = context.read<PickupLocationProvider>();
    final result = await pickupProvider.offboardPickupLocation(
      authViewModel.currentUser.id,
      dropOffCount: 1,
    );

    if (result != null && context.mounted) {
      final message = result.fullyOffboard
          ? 'Drop off recorded.'
          : '${result.dropOffCount} dropped off. ${result.remainingPassengerCount} still on board.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
      if (!result.fullyOffboard) return;

      final completedTrip =
          await RideFeedbackService.getLatestUnratedCompletedTrip(
            authViewModel.currentUser.id,
          );
      if (!context.mounted || completedTrip == null) return;
      await showPostRideFeedbackPrompt(context, trip: completedTrip);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pickupProvider.errorMessage ??
                'Could not record drop off. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _destinationDisplayLabel(String destinationCode) {
    final canonical = _canonicalTerminal(destinationCode);

    if (canonical == 'lucban') {
      return 'Lucban';
    }

    if (canonical == 'sta_cruz') {
      return 'Sta. Cruz';
    }

    return TerminalConstants.fromCode(destinationCode);
  }

  bool _showRouteSelectionWarningIfInvalid(JeepneyViewModel viewModel) {
    final validationMessage = viewModel.routeSelectionValidationMessage;

    if (validationMessage == null) {
      return false;
    }

    _showRouteSelectionWarning(validationMessage);
    return true;
  }

  void _showRouteSelectionWarning(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.warning,
      ),
    );
  }

  List<Marker> _buildTerminalMarkers() {
    return [
      ..._buildTerminalMarkerGroup(
        point: _terminalA,
        color: AppColors.success,
        label: 'Lucban',
      ),
      ..._buildTerminalMarkerGroup(
        point: _terminalB,
        color: Colors.orange,
        label: 'Sta. Cruz',
      ),
    ];
  }

  List<Marker> _buildTerminalMarkerGroup({
    required LatLng point,
    required Color color,
    required String label,
  }) {
    final isSelected = _selectedTerminalLabel == label;

    return [
      Marker(
        point: point,
        width: 50,
        height: 50,
        alignment: Alignment.center,
        rotate: true,
        child: _buildTerminalIconMarker(
          color: color,
          label: label,
          isSelected: isSelected,
        ),
      ),
      if (isSelected)
        Marker(
          point: point,
          width: 112,
          height: 32,
          alignment: const Alignment(0, 2.9),
          rotate: true,
          child: _buildTerminalLabel(color: color, label: label),
        ),
    ];
  }

  Widget _buildTerminalIconMarker({
    required Color color,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _selectedTerminalLabel = isSelected ? null : label;
          _selectedMapJeepney = null;
        });
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.location_city_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalLabel({required Color color, required String label}) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: AppDimensions.borderRadiusFull,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<DriverRouteInfo> _filterActiveRoutesByDestination(
    JeepneyViewModel viewModel,
  ) {
    if (!viewModel.hasRouteFilter) return _activeRoutes;

    final selectedDestinationCode = _canonicalTerminal(
      viewModel.routeFilter!.destinationTerminal,
    );

    final selectedDestinationLabel = _canonicalTerminal(
      TerminalConstants.fromCode(viewModel.routeFilter!.destinationTerminal),
    );

    return _activeRoutes.where((route) {
      final routeDestination = _canonicalTerminal(route.destination);
      final destinationMatches =
          routeDestination.isNotEmpty &&
          (routeDestination == selectedDestinationCode ||
              routeDestination == selectedDestinationLabel);

      if (!destinationMatches) {
        debugPrint(
          'Skipped active route ${route.id}: destination mismatch. '
          'selectedDestination=${viewModel.routeFilter!.destinationTerminal}, '
          'routeDestination=${route.destination}',
        );
      }

      return destinationMatches;
    }).toList();
  }

  List<DriverRouteInfo> _filterActiveRoutesForVisibleJeepneys(
    JeepneyViewModel viewModel,
  ) {
    if (!viewModel.hasRouteFilter) return const [];

    final visibleJeepneyIds =
        _filterActiveJeepneysBySelectedDestination(
          viewModel,
        ).map((jeepney) => _normalizeKey(jeepney.id)).where((id) {
          return id.isNotEmpty;
        }).toSet();

    if (visibleJeepneyIds.isEmpty) return const [];

    return _filterActiveRoutesByDestination(viewModel).where((route) {
      final routeJeepneyId = _normalizeKey(route.jeepneyId);
      return route.hasValidRoute && visibleJeepneyIds.contains(routeJeepneyId);
    }).toList();
  }

  List<DriverRouteInfo> _safeVisibleActiveRoutes(JeepneyViewModel viewModel) {
    try {
      return _filterActiveRoutesForVisibleJeepneys(viewModel);
    } catch (e, stackTrace) {
      debugPrint('Failed to filter visible active routes safely: $e');
      debugPrint('StackTrace: $stackTrace');
      return const [];
    }
  }

  List<DriverRouteInfo> _routesForMap(
    List<DriverRouteInfo> visibleActiveRoutes,
    PickupLocationProvider pickupProvider,
  ) {
    if (!_isOnboardMapMode(pickupProvider)) return visibleActiveRoutes;

    try {
      final onboardJeepneyId = _normalizeKey(pickupProvider.jeepneyId);
      if (onboardJeepneyId.isEmpty) return const [];

      return _activeRoutes.where((route) {
        return route.hasValidRoute &&
            route.isActive &&
            _normalizeKey(route.jeepneyId) == onboardJeepneyId;
      }).toList();
    } catch (e, stackTrace) {
      debugPrint('Failed to resolve onboard route safely: $e');
      debugPrint('StackTrace: $stackTrace');
      return const [];
    }
  }

  List<Polyline> _buildActiveRoutePolylines(
    List<DriverRouteInfo> routes,
    JeepneyViewModel viewModel, {
    LatLng? progressLocation,
  }) {
    try {
      final jeepneysById = {
        for (final jeepney in viewModel.activeDriverLocations)
          _normalizeKey(jeepney.id): jeepney,
      };
      final polylines = <Polyline>[];

      for (final route in routes) {
        if (!route.hasValidRoute) continue;

        final jeepney = jeepneysById[_normalizeKey(route.jeepneyId)];
        final hasJeepney = jeepney != null && _hasValidJeepneyLocation(jeepney);

        final locationForProgress =
            progressLocation ??
            (hasJeepney ? LatLng(jeepney.latitude, jeepney.longitude) : null);

        final progress = locationForProgress != null
            ? _RouteProgressSegments.fromRoute(
                routePoints: route.points,
                currentLocation: locationForProgress,
              )
            : null;

        polylines.add(
          Polyline(
            points: route.points,
            strokeWidth: 7.0,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        );

        if (progress != null) {
          if (progress.consumed.isNotEmpty) {
            polylines.add(
              Polyline(
                points: progress.consumed,
                strokeWidth: 4.2,
                color: AppColors.textSecondary.withValues(alpha: 0.48),
              ),
            );
          }
          if (progress.remaining.isNotEmpty) {
            polylines.add(
              Polyline(
                points: progress.remaining,
                strokeWidth: 4.2,
                color: AppColors.primary.withValues(alpha: 0.82),
              ),
            );
          }
        } else {
          polylines.add(
            Polyline(
              points: route.points,
              strokeWidth: 4.2,
              color: AppColors.primary.withValues(alpha: 0.55),
            ),
          );
        }
      }

      return polylines;
    } catch (e, stackTrace) {
      debugPrint('Failed to build route polylines safely: $e');
      debugPrint('StackTrace: $stackTrace');
      return const [];
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;

    if (currentZoom < 18.0) {
      _mapController.move(_mapController.camera.center, currentZoom + 1);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;

    if (currentZoom > 10.0) {
      _mapController.move(_mapController.camera.center, currentZoom - 1);
    }
  }

  void _refocusTerminalSpan() {
    _mapController.fitCamera(_terminalCameraFitForContext(context));
  }

  void _resetMapNorth() {
    _mapController.rotate(0);
    setState(() => _mapRotation = 0);
  }

  Future<void> _refreshMapAndRefocus(
    JeepneyViewModel viewModel, {
    PickupLocationProvider? pickupProvider,
  }) async {
    await Future.wait([viewModel.refresh(), _refreshActiveRoutes()]);

    if (!mounted) return;

    if (pickupProvider != null && _isOnboardMapMode(pickupProvider)) {
      _recenterToUserLocation(
        jeepneyViewModel: viewModel,
        pickupProvider: pickupProvider,
      );
      return;
    }

    _refocusTerminalSpan();
  }

  // ignore: unused_element
  Future<void> _showShareLocationDialog(BuildContext context) async {
    final authViewModel = context.read<AuthViewModel>();
    final pickupProvider = context.read<PickupLocationProvider>();
    final jeepneyViewModel = context.read<JeepneyViewModel>();
    final userLocation = jeepneyViewModel.userLocation ?? _userLocation;
    final routeFilter = jeepneyViewModel.routeFilter;

    if (userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available. Please enable GPS.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final hasOnTripDriver = _filterActiveJeepneysBySelectedDestination(
      jeepneyViewModel,
    ).any((jeepney) => jeepney.isActive);

    if (!hasOnTripDriver) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.cannotShareNoDriverOnTrip),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final validRouteFilter = routeFilter!;

    final success = await pickupProvider.setPickupLocationFromGps(
      commuterId: authViewModel.currentUser.id,
      location: userLocation,
      routeId: validRouteFilter.routeId,
      waitingCount: 1,
      destinationTerminal: validRouteFilter.destinationTerminal,
    );

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location na ipinapakita sa driver.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } else if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pickupProvider.errorMessage ??
                'Could not notify driver. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  List<Jeepney> _sortJeepneysByDistance(
    List<Jeepney> jeepneys,
    JeepneyViewModel viewModel,
  ) {
    final origin = viewModel.userLocation ?? _userLocation;
    if (origin == null) return List<Jeepney>.from(jeepneys);

    final sorted = List<Jeepney>.from(jeepneys);
    const distance = Distance();
    sorted.sort((a, b) {
      final aHasLocation = _hasValidJeepneyLocation(a);
      final bHasLocation = _hasValidJeepneyLocation(b);
      if (aHasLocation != bHasLocation) return aHasLocation ? -1 : 1;
      if (!aHasLocation && !bHasLocation) return 0;

      final aDistance = distance.as(
        LengthUnit.Meter,
        origin,
        LatLng(a.latitude, a.longitude),
      );
      final bDistance = distance.as(
        LengthUnit.Meter,
        origin,
        LatLng(b.latitude, b.longitude),
      );
      return aDistance.compareTo(bDistance);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final pickupProvider = context.watch<PickupLocationProvider>();

    return Scaffold(
      body: Consumer<JeepneyViewModel>(
        builder: (context, jeepneyViewModel, _) {
          final visibleActiveRoutes = _safeVisibleActiveRoutes(
            jeepneyViewModel,
          );
          final visibleMapRoutes = _routesForMap(
            visibleActiveRoutes,
            pickupProvider,
          );
          final selectedMapJeepney =
              _selectedMapJeepney != null &&
                  _hasValidJeepneyLocation(_selectedMapJeepney!)
              ? _selectedMapJeepney
              : null;
          final isOnboardMapMode = _isOnboardMapMode(pickupProvider);
          final onboardProgressLocation = _onboardDisplayLocation(
            jeepneyViewModel,
            pickupProvider,
            visibleMapRoutes,
          );
          final showOnboardActionBar =
              authViewModel.isLoggedIn &&
              !authViewModel.isGuest &&
              isOnboardMapMode;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _defaultCenter,
                  initialZoom: _defaultZoom,
                  initialCameraFit: _terminalCameraFitForContext(context),
                  minZoom: 10.0,
                  maxZoom: 18.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onTap: (_, __) {
                    if (_selectedMapJeepney != null ||
                        _selectedTerminalLabel != null) {
                      setState(() {
                        _selectedMapJeepney = null;
                        _selectedTerminalLabel = null;
                      });
                    }
                  },
                  onMapEvent: (event) {
                    final rotation = event.camera.rotation;
                    if ((_mapRotation - rotation).abs() > 0.1) {
                      setState(() => _mapRotation = rotation);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.byaherox.commuter',
                    maxZoom: 19,
                  ),
                  if (visibleMapRoutes.isNotEmpty)
                    PolylineLayer(
                      polylines: _buildActiveRoutePolylines(
                        visibleMapRoutes,
                        jeepneyViewModel,
                        progressLocation: onboardProgressLocation,
                      ),
                    ),
                  MarkerLayer(
                    markers: _buildJeepneyMarkers(
                      jeepneyViewModel,
                      pickupProvider: pickupProvider,
                      routes: visibleMapRoutes,
                    ),
                  ),
                  MarkerLayer(markers: _buildTerminalMarkers()),
                  if (_userLocation != null && !isOnboardMapMode)
                    Consumer<PickupLocationProvider>(
                      builder: (context, pickupProvider, _) {
                        final isSharing =
                            authViewModel.isLoggedIn &&
                            !authViewModel.isGuest &&
                            pickupProvider.isSharing;
                        final markerSize = isSharing
                            ? 50.0
                            : AppDimensions.markerSizeMd;

                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: _userLocation!,
                              width: markerSize,
                              height: markerSize,
                              child: _buildUserLocationMarker(
                                isSharing: isSharing,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  Consumer<PickupLocationProvider>(
                    builder: (context, pickupProvider, _) {
                      final canShowOwnPickupLocation =
                          authViewModel.isLoggedIn &&
                          !authViewModel.isGuest &&
                          pickupProvider.hasLocation &&
                          pickupProvider.isSharing &&
                          !_isOnboardMapMode(pickupProvider);

                      if (canShowOwnPickupLocation) {
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: pickupProvider.pickupLocation!,
                              width: 50,
                              height: 50,
                              child: _buildPickupLocationMarker(),
                            ),
                          ],
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppDimensions.sm,
                    left: AppDimensions.md,
                    right: AppDimensions.md,
                    bottom: AppDimensions.sm,
                  ),
                  child: _buildFloatingHeader(
                    context,
                    jeepneyViewModel,
                    isGuest: authViewModel.isGuest,
                  ),
                ),
              ),
              Positioned(
                bottom:
                    AppDimensions.bottomNavHeight +
                    (selectedMapJeepney == null && !showOnboardActionBar
                        ? 10
                        : 70),
                right: 16,
                child: _buildMapControlsPanel(
                  context,
                  jeepneyViewModel,
                  pickupProvider,
                ),
              ),
              if (showOnboardActionBar)
                Positioned(
                  left: AppDimensions.md,
                  right: AppDimensions.md,
                  bottom: AppDimensions.bottomNavHeight + 4,
                  child: SafeArea(
                    top: false,
                    child: _buildOnboardActionBar(
                      jeepneyViewModel,
                      pickupProvider,
                    ),
                  ),
                )
              else if (selectedMapJeepney != null)
                Positioned(
                  left: AppDimensions.md,
                  right: AppDimensions.md,
                  bottom: AppDimensions.bottomNavHeight + 4,
                  child: SafeArea(
                    top: false,
                    child: _buildSelectedJeepneyActionBar(selectedMapJeepney),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFloatingHeader(
    BuildContext context,
    JeepneyViewModel viewModel, {
    required bool isGuest,
  }) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      backgroundColor: AppColors.surface.withValues(alpha: 0.38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildBackButton(context),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildCompactDestinationSelector(context, viewModel),
                ),
                const SizedBox(width: 8),
                if (isGuest)
                  _buildGuestLoginButton(context)
                else
                  _buildLiveBadgeCompact(context, viewModel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestLoginButton(BuildContext context) {
    return Tooltip(
      message: 'Log in to your account',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _goToLoginFromGuest(),
          borderRadius: AppDimensions.borderRadiusFull,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.sm,
              vertical: AppDimensions.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: AppDimensions.borderRadiusFull,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.login, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Log In',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedJeepneyActionBar(Jeepney jeepney) {
    return Consumer<PickupLocationProvider>(
      builder: (context, pickupProvider, _) {
        final authViewModel = context.read<AuthViewModel>();
        final isLoggedIn = authViewModel.isLoggedIn && !authViewModel.isGuest;
        final isSharingForThis =
            pickupProvider.isSharing && pickupProvider.jeepneyId == jeepney.id;
        final isOnboardForThis = pickupProvider.canDropOffForJeepney(
          jeepney.id,
        );
        final isBookedOnAnotherJeepney = pickupProvider
            .isBookedOnAnotherJeepney(jeepney.id);
        final isFull = _isJeepFull(jeepney);

        final String label;
        final IconData icon;
        final VoidCallback? onPressed;
        final Color backgroundColor;

        if (!isLoggedIn) {
          label = 'Sign In';
          icon = Icons.login_outlined;
          onPressed = _showGuestSignInPrompt;
          backgroundColor = AppColors.primary;
        } else if (isOnboardForThis) {
          label = 'Drop Off';
          icon = Icons.logout_outlined;
          onPressed = _offboardPickupNotification;
          backgroundColor = AppColors.secondary;
        } else if (isSharingForThis) {
          label = 'Cancel Booking';
          icon = Icons.cancel_outlined;
          onPressed = _cancelPickupNotification;
          backgroundColor = AppColors.error;
        } else if (isBookedOnAnotherJeepney) {
          label = 'Already Booked';
          icon = Icons.lock_outline;
          onPressed = null;
          backgroundColor = AppColors.textSecondary;
        } else if (isFull) {
          label = 'Jeep is full';
          icon = Icons.event_busy_outlined;
          onPressed = null;
          backgroundColor = AppColors.textSecondary;
        } else {
          label = 'Notify Driver';
          icon = Icons.notifications_outlined;
          onPressed = () => _sendPickupNotification(jeepney);
          backgroundColor = AppColors.primary;
        }

        final jeepneyPlate = jeepney.plateNumber.trim();

        return GlassSurface(
          padding: EdgeInsets.zero,
          borderRadius: AppDimensions.borderRadiusMd,
          backgroundColor: AppColors.surface.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    jeepneyPlate.isNotEmpty ? jeepneyPlate : 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                  style: FilledButton.styleFrom(
                    backgroundColor: backgroundColor,
                    foregroundColor: AppColors.textOnPrimary,
                    disabledBackgroundColor: AppColors.surfaceVariant,
                    disabledForegroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOnboardActionBar(
    JeepneyViewModel jeepneyViewModel,
    PickupLocationProvider pickupProvider,
  ) {
    final onboardJeepney = _findJeepneyById(
      jeepneyViewModel,
      pickupProvider.jeepneyId,
    );
    final jeepneyPlate =
        onboardJeepney?.plateNumber.trim() ??
        pickupProvider.jeepneyId?.trim() ??
        'Current jeep';

    return GlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: AppDimensions.borderRadiusMd,
      backgroundColor: AppColors.surface.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                jeepneyPlate.isNotEmpty ? jeepneyPlate : 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _offboardPickupNotification,
              icon: const Icon(Icons.logout_outlined, size: 18),
              label: const Text('Drop Off'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Jeepney? _findJeepneyById(JeepneyViewModel jeepneyViewModel, String? id) {
    final targetId = _normalizeKey(id);
    if (targetId.isEmpty) return null;

    for (final jeepney in jeepneyViewModel.activeDriverLocations) {
      if (_normalizeKey(jeepney.id) == targetId) return jeepney;
    }

    for (final jeepney in jeepneyViewModel.allActiveJeepneys) {
      if (_normalizeKey(jeepney.id) == targetId) return jeepney;
    }

    return null;
  }

  Widget _buildMapControlsPanel(
    BuildContext context,
    JeepneyViewModel jeepneyViewModel,
    PickupLocationProvider pickupProvider,
  ) {
    final buttons = <Widget>[
      _buildCompassButton(rotation: _mapRotation, onTap: _resetMapNorth),
      _buildMapControlButton(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh and recenter map',
        onTap: () => _refreshMapAndRefocus(
          jeepneyViewModel,
          pickupProvider: pickupProvider,
        ),
      ),
      _buildMapControlButton(
        icon: Icons.add_rounded,
        tooltip: 'Zoom in',
        onTap: _zoomIn,
      ),
      _buildMapControlButton(
        icon: Icons.remove_rounded,
        tooltip: 'Zoom out',
        onTap: _zoomOut,
      ),
      _buildMapControlButton(
        icon: Icons.my_location_rounded,
        tooltip: 'Center on my location',
        onTap: () => _recenterToUserLocation(
          jeepneyViewModel: jeepneyViewModel,
          pickupProvider: pickupProvider,
        ),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          buttons[index],
          if (index < buttons.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildCompassButton({
    required double rotation,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: 'Point map north',
      child: GlassSurface(
        padding: EdgeInsets.zero,
        borderRadius: AppDimensions.borderRadiusFull,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Transform.rotate(
                  angle: -rotation * math.pi / 180,
                  child: const Icon(
                    Icons.navigation_rounded,
                    size: 25,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final foregroundColor = isPrimary ? Colors.white : AppColors.primaryDark;

    return Tooltip(
      message: tooltip,
      child: GlassSurface(
        padding: EdgeInsets.zero,
        borderRadius: AppDimensions.borderRadiusFull,
        backgroundColor: isPrimary
            ? AppColors.primary.withValues(alpha: 0.82)
            : AppColors.surface.withValues(alpha: 0.34),
        borderColor: isPrimary
            ? AppColors.primaryLight.withValues(alpha: 0.42)
            : AppColors.surface.withValues(alpha: 0.46),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Icon(icon, size: 23, color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDestinationSelector(
    BuildContext context,
    JeepneyViewModel viewModel,
  ) {
    final hasFilter = viewModel.hasRouteFilter;

    final destLabel = hasFilter
        ? _destinationDisplayLabel(viewModel.routeFilter!.destinationTerminal)
        : 'Both';

    return GestureDetector(
      onTap: () => _showDestinationPicker(context, viewModel),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        borderRadius: BorderRadius.circular(8),
        backgroundColor: AppColors.primarySurface.withValues(alpha: 0.34),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter ? Icons.location_on : Icons.route_outlined,
              color: AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                destLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }

  void _showDestinationPicker(
    BuildContext context,
    JeepneyViewModel viewModel,
  ) {
    final currentDest = viewModel.hasRouteFilter
        ? _canonicalTerminal(viewModel.routeFilter!.destinationTerminal)
        : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.86,
          ),
          child: GlassSurface(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pumili ng Destinasyon',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Piliin ang biyahe. Ipapakita ang mga jeepney mula pinakamalapit hanggang pinakamalayo.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DestinationOptionTile(
                    icon: Icons.route_outlined,
                    title: 'Both routes',
                    subtitle: 'Show all available active jeepneys',
                    selected: currentDest == null,
                    onTap: () {
                      setState(() {
                        _selectedMapJeepney = null;
                        _selectedTerminalLabel = null;
                      });
                      viewModel.clearRouteFilter();
                      Navigator.pop(bottomSheetContext);
                      viewModel.refresh(showLoading: false);
                    },
                  ),
                  const SizedBox(height: 8),
                  _DestinationOptionTile(
                    icon: Icons.location_on,
                    title: 'Sta. Cruz',
                    subtitle: 'Lucban Terminal to Sta. Cruz Terminal',
                    selected: currentDest == 'sta_cruz',
                    onTap: () {
                      if (viewModel.setDestinationFilter('sta_cruz')) {
                        setState(() {
                          _selectedMapJeepney = null;
                          _selectedTerminalLabel = null;
                        });
                        Navigator.pop(bottomSheetContext);
                        viewModel.refresh(showLoading: false);
                        return;
                      }

                      Navigator.pop(bottomSheetContext);
                      _showRouteSelectionWarningIfInvalid(viewModel);
                    },
                  ),
                  const SizedBox(height: 8),
                  _DestinationOptionTile(
                    icon: Icons.location_on,
                    title: 'Lucban',
                    subtitle: 'Sta. Cruz Terminal to Lucban Terminal',
                    selected: currentDest == 'lucban',
                    onTap: () {
                      if (viewModel.setDestinationFilter('lucban')) {
                        setState(() {
                          _selectedMapJeepney = null;
                          _selectedTerminalLabel = null;
                        });
                        Navigator.pop(bottomSheetContext);
                        viewModel.refresh(showLoading: false);
                        return;
                      }

                      Navigator.pop(bottomSheetContext);
                      _showRouteSelectionWarningIfInvalid(viewModel);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppDimensions.borderRadiusMd,
      child: InkWell(
        onTap: () {
          final authViewModel = context.read<AuthViewModel>();

          if (authViewModel.isLoggedIn) {
            context.go('/dashboard');
          } else {
            context.go('/welcome');
          }
        },
        borderRadius: AppDimensions.borderRadiusMd,
        child: GlassSurface(
          padding: const EdgeInsets.all(AppDimensions.sm),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primary,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBadgeCompact(
    BuildContext context,
    JeepneyViewModel viewModel,
  ) {
    final driverCount = _filterActiveJeepneysBySelectedDestination(
      viewModel,
    ).length;

    final hasDrivers = driverCount > 0;

    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: BorderRadius.circular(12),
      backgroundColor: hasDrivers
          ? AppColors.successLight.withValues(alpha: 0.38)
          : AppColors.surface.withValues(alpha: 0.46),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: hasDrivers ? AppColors.success : AppColors.textSecondary,
              shape: BoxShape.circle,
              boxShadow: hasDrivers
                  ? [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE${hasDrivers ? ' $driverCount' : ''}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: hasDrivers
                  ? AppColors.secondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserLocationMarker({required bool isSharing}) {
    if (isSharing) {
      return _buildSharedLocationMarker(icon: Icons.person_pin, iconSize: 18);
    }

    return _buildFlatUserLocationMarker();
  }

  Widget _buildFlatUserLocationMarker() {
    return Transform.translate(
      offset: const Offset(0, -15),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupLocationMarker() {
    return _buildSharedLocationMarker(icon: Icons.location_on, iconSize: 16);
  }

  Widget _buildSharedLocationMarker({
    required IconData icon,
    required double iconSize,
  }) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ],
      ),
    );
  }
}

class _RouteProgressSegments {
  const _RouteProgressSegments({
    required this.consumed,
    required this.remaining,
  });

  final List<LatLng> consumed;
  final List<LatLng> remaining;

  factory _RouteProgressSegments.fromRoute({
    required List<LatLng> routePoints,
    required LatLng currentLocation,
  }) {
    if (routePoints.length < 2) {
      return const _RouteProgressSegments(consumed: [], remaining: []);
    }

    var nearestSegmentIndex = 0;
    var nearestPoint = routePoints.first;
    var nearestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projected = _closestPointOnSegment(
        routePoints[i],
        routePoints[i + 1],
        currentLocation,
      );
      final distance = _distanceMeters(currentLocation, projected);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = projected;
        nearestSegmentIndex = i;
      }
    }

    final consumed = <LatLng>[...routePoints.take(nearestSegmentIndex + 1)];
    if (!_samePoint(consumed.last, nearestPoint)) {
      consumed.add(nearestPoint);
    }

    final remaining = <LatLng>[nearestPoint];
    for (final point in routePoints.skip(nearestSegmentIndex + 1)) {
      if (!_samePoint(remaining.last, point)) {
        remaining.add(point);
      }
    }

    return _RouteProgressSegments(
      consumed: consumed.length >= 2 ? consumed : const [],
      remaining: remaining.length >= 2 ? remaining : const [],
    );
  }

  static LatLng? advanceAlongRoute({
    required List<LatLng> routePoints,
    required LatLng currentLocation,
    required double distanceMeters,
  }) {
    if (routePoints.length < 2 || distanceMeters <= 0) return null;

    var nearestSegmentIndex = 0;
    var nearestPoint = routePoints.first;
    var nearestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projected = _closestPointOnSegment(
        routePoints[i],
        routePoints[i + 1],
        currentLocation,
      );
      final distance = _distanceMeters(currentLocation, projected);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = projected;
        nearestSegmentIndex = i;
      }
    }

    if (nearestDistance > 250) return null;

    var remainingDistance = distanceMeters;
    var segmentStart = nearestPoint;

    for (var i = nearestSegmentIndex; i < routePoints.length - 1; i++) {
      final segmentEnd = routePoints[i + 1];
      final segmentDistance = _distanceMeters(segmentStart, segmentEnd);
      if (segmentDistance <= 0) {
        segmentStart = segmentEnd;
        continue;
      }

      if (remainingDistance <= segmentDistance) {
        return _interpolate(
          segmentStart,
          segmentEnd,
          remainingDistance / segmentDistance,
        );
      }

      remainingDistance -= segmentDistance;
      segmentStart = segmentEnd;
    }

    return routePoints.last;
  }

  static LatLng _interpolate(LatLng start, LatLng end, double t) {
    final clampedT = t.clamp(0.0, 1.0).toDouble();
    return LatLng(
      start.latitude + (end.latitude - start.latitude) * clampedT,
      start.longitude + (end.longitude - start.longitude) * clampedT,
    );
  }

  static LatLng _closestPointOnSegment(LatLng start, LatLng end, LatLng point) {
    final refLat = _toRadians((start.latitude + end.latitude) / 2.0);
    final startXY = _RouteXY.fromLatLng(start, refLat);
    final endXY = _RouteXY.fromLatLng(end, refLat);
    final pointXY = _RouteXY.fromLatLng(point, refLat);

    final dx = endXY.x - startXY.x;
    final dy = endXY.y - startXY.y;
    final segmentLengthSquared = dx * dx + dy * dy;
    if (segmentLengthSquared == 0) return start;

    final t =
        ((pointXY.x - startXY.x) * dx + (pointXY.y - startXY.y) * dy) /
        segmentLengthSquared;
    final clampedT = t.clamp(0.0, 1.0).toDouble();

    return _RouteXY(
      startXY.x + clampedT * dx,
      startXY.y + clampedT * dy,
    ).toLatLng(refLat);
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final value =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(a.latitude)) *
            math.cos(_toRadians(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
    return earthRadius * c;
  }

  static bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}

class _RouteXY {
  const _RouteXY(this.x, this.y);

  final double x;
  final double y;

  factory _RouteXY.fromLatLng(LatLng point, double refLatRadians) {
    const earthRadius = 6371000.0;
    return _RouteXY(
      _RouteProgressSegments._toRadians(point.longitude) *
          earthRadius *
          math.cos(refLatRadians),
      _RouteProgressSegments._toRadians(point.latitude) * earthRadius,
    );
  }

  LatLng toLatLng(double refLatRadians) {
    const earthRadius = 6371000.0;
    final lat = (y / earthRadius) * 180 / math.pi;
    final lng = (x / (earthRadius * math.cos(refLatRadians))) * 180 / math.pi;
    return LatLng(lat, lng);
  }
}

class _DestinationOptionTile extends StatelessWidget {
  const _DestinationOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: GlassSurface(
          padding: const EdgeInsets.all(12),
          borderRadius: BorderRadius.circular(14),
          backgroundColor: selected
              ? AppColors.primarySurface.withValues(alpha: 0.38)
              : AppColors.surface.withValues(alpha: 0.42),
          borderColor: selected
              ? AppColors.primary.withValues(alpha: 0.28)
              : AppColors.surface.withValues(alpha: 0.76),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.surface.withValues(alpha: 0.46),
                  ),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
