import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart'; // Needed for CachedTileProvider
import 'package:flutter/gestures.dart'; // ⭐️ Added for kPrimaryButton
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart'; // Needed for CurrentLocationLayer
import 'package:flutter_tts/flutter_tts.dart'; // Import for TTS
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show LatLng; // Using Google's LatLng for convenience
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart'
    as latlong; // Use 'as' to avoid conflicts

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VitNavigationApp());
}

// --- Data Model for a Location ---
class Location {
  final String name;
  final String category;
  final String description;
  final LatLng coordinates; // Using Google's LatLng

  const Location({
    required this.name,
    required this.category,
    required this.description,
    required this.coordinates,
  });
}

// --- Data Model for a Route Step ---
class RouteStep {
  final String instruction; // The text to speak
  final double distance;
  final LatLng location; // Using Google's LatLng
  final String maneuverType;
  final String maneuverModifier;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.location,
    required this.maneuverType,
    required this.maneuverModifier,
  });
}

class VitNavigationApp extends StatelessWidget {
  const VitNavigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VIT Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  Location? _selectedLocation;
  LatLng? _tappedDestination;

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  bool _isFollowingUser = false;

  List<LatLng> _routeCoordinates = [];
  String _selectedProfile = '';
  bool _isRouting = false;

  List<LatLng> _cachedWalkRoute = [];
  List<LatLng> _cachedBikeRoute = [];
  List<RouteStep> _cachedWalkSteps = [];
  List<RouteStep> _cachedBikeSteps = [];

  String _walkDuration = '---';
  String _walkDistance = '---';
  String _bikeDuration = '---';
  String _bikeDistance = '---';

  bool _isModalLoading = false;

  List<RouteStep> _activeSteps = [];
  int _currentStepIndex = 0;

  final FlutterTts _flutterTts = FlutterTts();

  final List<Location> _allLocations = const [
    Location(
      name: 'Technology Tower (TT)',
      category: 'Academic Block',
      description:
          'Houses CSE/IT departments, major labs, and faculty offices.',
      coordinates: LatLng(12.970591, 79.159508),
    ),
    Location(
      name: 'Main Gate',
      category: 'Entrance',
      description: 'The primary entrance and exit of the campus.',
      coordinates: LatLng(12.967885, 79.157833),
    ),
    Location(
      name: 'Central Library',
      category: 'Admin',
      description: 'The main library facility.',
      coordinates: LatLng(12.972300, 79.158700),
    ),
    Location(
      name: 'Food Court Complex (FCC)',
      category: 'Food Courts',
      description: 'Multi-cuisine food court area.',
      coordinates: LatLng(12.969500, 79.158500),
    ),
    Location(
      name: 'Men\'s Hostel Block A',
      category: 'Hostel',
      description: 'One of the largest student hostels.',
      coordinates: LatLng(12.971700, 79.155800),
    ),
  ];

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationServiceEnabled = false;

  LatLng? get _finalDestinationCoordinates {
    return _selectedLocation?.coordinates ?? _tappedDestination;
  }

  String get _finalDestinationName {
    return _selectedLocation?.name ??
        (_tappedDestination != null ? 'Tapped Location' : 'Destination');
  }

  String get _activeRouteDuration {
    return _selectedProfile == 'walk'
        ? _walkDuration
        : (_selectedProfile == 'bike' ? _bikeDuration : '---');
  }

  String get _activeRouteDistance {
    return _selectedProfile == 'walk'
        ? _walkDistance
        : (_selectedProfile == 'bike' ? _bikeDistance : '---');
  }

  latlong.LatLng _toFlutterMapLatLng(LatLng gLatLng) {
    return latlong.LatLng(gLatLng.latitude, gLatLng.longitude);
  }

  LatLng _toGoogleLatLng(latlong.LatLng flLatLng) {
    return LatLng(flLatLng.latitude, flLatLng.longitude);
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkAndStartLocationStream();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> _checkAndStartLocationStream() async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_isLocationServiceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;
    }

    // Check again after requesting
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_isLocationServiceEnabled || !mounted) return; // Added mounted check

    setState(() {}); // Update UI if service became enabled

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionStreamSubscription
        ?.cancel(); // Cancel previous subscription if any
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!mounted) return; // Ensure widget is still mounted

            final previousPosition = _currentPosition;
            setState(() {
              _currentPosition = position;
            });

            if (_isFollowingUser &&
                _isRouting &&
                position.headingAccuracy > 0 &&
                position.heading != -1.0) {
              double headingDifference = 0;
              if (previousPosition != null &&
                  previousPosition.headingAccuracy > 0 &&
                  previousPosition.heading != -1.0) {
                headingDifference = position.heading - previousPosition.heading;
                if (headingDifference > 180.0) headingDifference -= 360.0;
                if (headingDifference < -180.0) headingDifference += 360.0;
              }

              if (previousPosition == null ||
                  previousPosition.heading == -1.0 ||
                  headingDifference.abs() > 2.0) {
                _mapController.rotate(-position.heading);
              }
              _mapController.move(
                _toFlutterMapLatLng(
                  LatLng(position.latitude, position.longitude),
                ),
                _mapController.camera.zoom,
              );
            }

            if (_isRouting && _activeSteps.isNotEmpty) {
              final userLocation = LatLng(
                position.latitude,
                position.longitude,
              );
              if (_currentStepIndex >= _activeSteps.length - 1) {
                final destination = _finalDestinationCoordinates!;
                final distanceToDestination = Geolocator.distanceBetween(
                  userLocation.latitude,
                  userLocation.longitude,
                  destination.latitude,
                  destination.longitude,
                );
                if (distanceToDestination < 20.0) {
                  _speak("You have arrived at your destination.");
                  _resetNavigationState();
                }
              } else {
                final nextStep = _activeSteps[_currentStepIndex + 1];
                final distanceToNextManeuver = Geolocator.distanceBetween(
                  userLocation.latitude,
                  userLocation.longitude,
                  nextStep.location.latitude,
                  nextStep.location.longitude,
                );
                const double maneuverThreshold = 25.0;
                if (distanceToNextManeuver < maneuverThreshold) {
                  setState(() {
                    _currentStepIndex++;
                  });
                  _speak(_activeSteps[_currentStepIndex].instruction);
                }
              }
            } else if (_finalDestinationCoordinates != null &&
                !_isModalLoading) {
              _fetchRouteSummary('walk', fireStateUpdate: true);
              _fetchRouteSummary('bike', fireStateUpdate: true);
            }
          },
          onError: (error) {
            debugPrint("Error getting location stream: $error");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error getting location: $error')),
              );
            }
          },
        );
  }

  Future<bool> _fetchRouteSummary(
    String profile, {
    bool fireStateUpdate = false,
  }) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

    if (fireStateUpdate && !_isModalLoading && mounted) {
      // Added mounted check
      setState(() {
        if (profile == 'walk') {
          _walkDuration = _walkDistance = '---';
        } else if (profile == 'bike') {
          _bikeDuration = _bikeDistance = '---';
        }
      });
    }

    final start = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final end = destination;
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=false&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'];
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final distanceInMeters =
              (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durationInSeconds =
              (route['duration'] as num?)?.toDouble() ?? 0.0;
          if (fireStateUpdate && mounted && !_isModalLoading) {
            // Added mounted check
            setState(() {
              final formattedDistance =
                  '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
              final formattedDuration = _formatDuration(
                durationInSeconds.toInt(),
              );
              if (profile == 'walk') {
                _walkDistance = formattedDistance;
                _walkDuration = formattedDuration;
              } else if (profile == 'bike') {
                _bikeDistance = formattedDistance;
                _bikeDuration = formattedDuration;
              }
            });
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Route summary fetch failed for $profile: $e');
    }
    return false;
  }

  Future<bool> _fetchRouteDetails(String profile) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

    if (mounted) {
      // Added mounted check
      setState(() {
        if (profile == 'walk') {
          _walkDuration = _walkDistance = '---';
          _cachedWalkRoute = [];
          _cachedWalkSteps = [];
        } else if (profile == 'bike') {
          _bikeDuration = _bikeDistance = '---';
          _cachedBikeRoute = [];
          _cachedBikeSteps = [];
        }
      });
    }

    final start = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final end = destination;
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'];
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final distanceInMeters =
              (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durationInSeconds =
              (route['duration'] as num?)?.toDouble() ?? 0.0;
          final geometry = route['geometry'];
          List<LatLng> points = [];
          if (geometry != null && geometry['coordinates'] != null) {
            for (var coord in geometry['coordinates']) {
              points.add(LatLng(coord[1], coord[0]));
            }
          }
          List<RouteStep> parsedSteps = [];
          final legs = route['legs'];
          if (legs != null && legs.isNotEmpty) {
            final steps = legs[0]['steps'];
            if (steps != null) {
              for (var step in steps) {
                final maneuver = step['maneuver'];
                parsedSteps.add(
                  RouteStep(
                    instruction: maneuver['instruction'] ?? '',
                    distance: (step['distance'] as num).toDouble(),
                    location: LatLng(
                      maneuver['location'][1],
                      maneuver['location'][0],
                    ),
                    maneuverType: maneuver['type'] ?? '',
                    maneuverModifier: maneuver['modifier'] ?? '',
                  ),
                );
              }
            }
          }
          if (mounted) {
            // Added mounted check
            setState(() {
              final formattedDistance =
                  '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
              final formattedDuration = _formatDuration(
                durationInSeconds.toInt(),
              );
              if (profile == 'walk') {
                _walkDistance = formattedDistance;
                _walkDuration = formattedDuration;
                _cachedWalkRoute = points;
                _cachedWalkSteps = parsedSteps;
              } else if (profile == 'bike') {
                _bikeDistance = formattedDistance;
                _bikeDuration = formattedDuration;
                _cachedBikeRoute = points;
                _cachedBikeSteps = parsedSteps;
              }
            });
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Route details fetch failed for $profile: $e');
    }
    return false;
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours hr ${remainingMinutes} min';
  }

  void _resetNavigationState() {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedLocation = null;
      _tappedDestination = null;
      _routeCoordinates = [];
      _selectedProfile = '';
      _walkDuration = _bikeDuration = '---';
      _walkDistance = _bikeDistance = '---';
      _isModalLoading = false;
      _cachedWalkRoute = [];
      _cachedBikeRoute = [];
      _cachedWalkSteps = [];
      _cachedBikeSteps = [];
      _isRouting = false;
      _activeSteps = [];
      _currentStepIndex = 0;
      _selectedIndex = 0;
      _isFollowingUser = false; // Stop following
    });
    _flutterTts.stop();

    if (mounted && _mapController.camera.rotation != 0) {
      _mapController.rotate(0); // Instantly set rotation back to 0
    }

    _sheetController.animateTo(
      0.2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _setDestinationFromDirectory(Location location) {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedIndex = 0;
      _selectedLocation = location;
      _tappedDestination = null;
      _routeCoordinates = [];
      _selectedProfile = '';
      _walkDuration = _bikeDuration = _walkDistance = _bikeDistance = '---';
      _isModalLoading = false;
      _cachedWalkRoute = [];
      _cachedBikeRoute = [];
      _cachedWalkSteps = [];
      _cachedBikeSteps = [];
      _isRouting = false;
      _activeSteps = [];
      _currentStepIndex = 0;
    });
    _sheetController.animateTo(
      0.2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _showDirectionsSheet();
  }

  void _onItemTapped(int index) {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _sheetController.animateTo(
        0.2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _sheetController.animateTo(
        0.9,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ⭐️ Corrected _onMapLongPress signature
  void _onMapLongPress(TapPosition tapPosition, latlong.LatLng point) {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedLocation = null;
      _tappedDestination = _toGoogleLatLng(point); // Convert
      _routeCoordinates = [];
      _selectedProfile = '';
      _walkDuration = _bikeDuration = _walkDistance = _bikeDistance = '---';
      _isModalLoading = false;
      _cachedWalkRoute = [];
      _cachedBikeRoute = [];
      _cachedWalkSteps = [];
      _cachedBikeSteps = [];
      _isRouting = false;
      _activeSteps = [];
      _currentStepIndex = 0;
    });
    _sheetController.animateTo(
      0.2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _showDirectionsSheet();
  }

  void _centerMapOnUser() {
    if (!mounted) return; // Added mounted check
    if (_currentPosition != null) {
      final userLocation = _toFlutterMapLatLng(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
      double targetRotation =
          _isFollowingUser &&
              _currentPosition!.headingAccuracy > 0 &&
              _currentPosition!.heading != -1.0
          ? -_currentPosition!.heading
          : _mapController.camera.rotation;
      _mapController.moveAndRotate(userLocation, 18.0, targetRotation);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching your location...')),
      );
      _checkAndStartLocationStream(); // Re-check permissions and stream
    }
  }

  Future<void> _startNavigation({
    required String profile,
    required List<LatLng> route,
    required List<RouteStep> steps,
  }) async {
    if (!mounted) return; // Added mounted check
    // 1. Animate the main sheet down
    await _sheetController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (!mounted) return; // Check again after await

    // 2. Set state for navigation & start following
    setState(() {
      _selectedProfile = profile;
      _routeCoordinates = route;
      _activeSteps = steps;
      _currentStepIndex = 0;
      _isRouting = true;
      _isFollowingUser = true;
    });

    // 3. Move map to user's location and rotate immediately
    if (_currentPosition != null) {
      double initialRotation = 0;
      if (_currentPosition!.headingAccuracy > 0 &&
          _currentPosition!.heading != -1.0) {
        initialRotation = -_currentPosition!.heading;
      }
      _mapController.moveAndRotate(
        _toFlutterMapLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
        18.0,
        initialRotation,
      );
    } else {
      // Fallback if no position yet: Fit route bounds
      final flutterMapPoints = route.map(_toFlutterMapLatLng).toList();
      // ⭐️ Corrected LatLngBounds usage
      if (flutterMapPoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(flutterMapPoints);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
        );
      }
    }

    // 4. Speak
    if (steps.isNotEmpty) {
      _speak(steps[0].instruction);
    }
  }

  void _showDirectionsSheet() {
    if (!mounted) return; // Added mounted check
    if (_finalDestinationCoordinates == null) return;
    final destinationName = _finalDestinationName;

    setState(() {
      _isModalLoading = true;
    });

    final Future fetchWalk = _fetchRouteDetails('walk');
    final Future fetchBike = _fetchRouteDetails('bike');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // Added mounted check inside future
            if (_isModalLoading) {
              Future.wait([fetchWalk, fetchBike]).then((_) {
                if (mounted) {
                  setModalState(() {
                    _isModalLoading = false;
                  });
                  setState(() {});
                }
              });
            }
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.25,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                final startLocationText = _currentPosition != null
                    ? 'Your Current Location'
                    : 'Getting Location...';
                final bool showRouteDetails =
                    _selectedProfile.isNotEmpty && _routeCoordinates.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Directions to $destinationName',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Divider(height: 24),
                      _buildDirectionInput(
                        Icons.my_location,
                        startLocationText,
                      ),
                      const SizedBox(height: 12),
                      _buildDirectionInput(Icons.location_on, destinationName),
                      const SizedBox(height: 24),
                      _isModalLoading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 8),
                                    Text('Calculating shortest routes...'),
                                  ],
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _TransportationOption(
                                  icon: Icons.directions_walk,
                                  label: 'Walk',
                                  duration: _walkDuration,
                                  distance: _walkDistance,
                                  isSelected: _selectedProfile == 'walk',
                                  onTap: () {
                                    if (_cachedWalkRoute.isNotEmpty &&
                                        _cachedWalkSteps.isNotEmpty) {
                                      if (Navigator.canPop(sheetContext))
                                        Navigator.pop(sheetContext);
                                      _startNavigation(
                                        profile: 'walk',
                                        route: _cachedWalkRoute,
                                        steps: _cachedWalkSteps,
                                      );
                                    } else if (_walkDuration != 'Err') {
                                      if (Navigator.canPop(sheetContext))
                                        Navigator.pop(sheetContext);
                                      if (mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Walk route not available or has no steps.',
                                            ),
                                          ),
                                        );
                                    }
                                  },
                                ),
                                _TransportationOption(
                                  icon: Icons.directions_bike,
                                  label: 'Bike',
                                  duration: _bikeDuration,
                                  distance: _bikeDistance,
                                  isSelected: _selectedProfile == 'bike',
                                  onTap: () {
                                    if (_cachedBikeRoute.isNotEmpty &&
                                        _cachedBikeSteps.isNotEmpty) {
                                      if (Navigator.canPop(sheetContext))
                                        Navigator.pop(sheetContext);
                                      _startNavigation(
                                        profile: 'bike',
                                        route: _cachedBikeRoute,
                                        steps: _cachedBikeSteps,
                                      );
                                    } else if (_bikeDuration != 'Err') {
                                      if (Navigator.canPop(sheetContext))
                                        Navigator.pop(sheetContext);
                                      if (mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Bike route not available or has no steps.',
                                            ),
                                          ),
                                        );
                                    }
                                  },
                                ),
                              ],
                            ),
                      const Divider(height: 24),
                      if (showRouteDetails) ...[
                        _buildStep(
                          'Total Distance: ${_activeRouteDistance}',
                          icon: Icons.straighten,
                        ),
                        _buildStep(
                          'Estimated Time: ${_activeRouteDuration}',
                          icon: Icons.timer,
                        ),
                        const Divider(height: 24),
                        _buildStep(
                          'Start from your location and follow the purple line.',
                          icon: Icons.arrow_right_alt,
                        ),
                        _buildStep(
                          'Continue until you reach $destinationName.',
                          icon: Icons.flag,
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Text(
                            'Please select a travel option (Walk or Bike) to view the route details.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDirectionInput(IconData icon, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String instruction, {IconData icon = Icons.arrow_right}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(child: Text(instruction)),
        ],
      ),
    );
  }

  Widget _buildCurrentContent(int index) {
    switch (index) {
      case 0:
        return const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 20.0),
            child: Column(
              children: [
                Text(
                  "Latest News & Quick Filters Go Here",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  "Drag up for more information or select a tab below.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      case 1:
        return DirectoryScreen(
          allLocations: _allLocations,
          onLocationSelected: _setDestinationFromDirectory,
        );
      case 2:
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          children: [
            Text(
              "Upcoming Events",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Divider(),
            _buildEventCard("Hackathon 2025", "TT Auditorium", "25th Oct"),
            _buildEventCard("Tech Expo Day", "Main Lawn", "30th Oct"),
            _buildEventCard("Cultural Fest", "Open Arena", "5th Nov"),
            const SizedBox(height: 50),
          ],
        );
      case 3:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person, size: 80, color: Colors.blueGrey),
              SizedBox(height: 16),
              Text(
                "User Profile Settings",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  "Manage your saved places, settings, and preferences here.",
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEventCard(String title, String location, String date) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 1,
      child: ListTile(
        leading: const Icon(Icons.calendar_month, color: Colors.red),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$location • $date'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 1:
        return 'Campus Directory';
      case 2:
        return 'Events & Activities';
      case 3:
        return 'Your Profile';
      default:
        return 'Latest in the area';
    }
  }

  Widget _getManeuverIcon(RouteStep step) {
    IconData iconData = Icons.straight;
    switch (step.maneuverType) {
      case 'turn':
        switch (step.maneuverModifier) {
          case 'left':
          case 'slight left':
          case 'sharp left':
            iconData = Icons.turn_left;
            break;
          case 'right':
          case 'slight right':
          case 'sharp right':
            iconData = Icons.turn_right;
            break;
          case 'uturn':
            iconData = Icons.u_turn_left;
            break;
        }
        break;
      case 'roundabout':
        iconData = Icons.roundabout_right;
        break;
      case 'arrive':
        iconData = Icons.flag;
        break;
      case 'continue':
        iconData = Icons.straight;
        break;
      default:
        iconData = Icons.arrow_upward;
    }
    return Icon(iconData, size: 40, color: Colors.blue[700]);
  }

  @override
  Widget build(BuildContext context) {
    final campusCenter = latlong.LatLng(12.970856, 79.159515);

    final List<Marker> locationMarkers = [];
    if (_finalDestinationCoordinates != null && !_isRouting) {
      locationMarkers.add(
        Marker(
          point: _toFlutterMapLatLng(_finalDestinationCoordinates!),
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              if (mounted) _showDirectionsSheet();
            },
            child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
          ),
        ),
      );
    }

    final List<Polyline> routePolylines = [];
    if (_routeCoordinates.isNotEmpty) {
      routePolylines.add(
        Polyline(
          points: _routeCoordinates.map(_toFlutterMapLatLng).toList(),
          strokeWidth: 5.0,
          color: Colors.deepPurple,
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: campusCenter,
                initialZoom: 16.0,
                minZoom: 10.0,
                maxZoom: 19.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                  enableMultiFingerGestureRace: true,
                ),
                onLongPress: _onMapLongPress,
                onPointerDown: (details, point) {
                  // ⭐️ Corrected onPointerDown usage
                  if (_isFollowingUser &&
                      _isRouting &&
                      details.buttons == kPrimaryButton) {
                    if (mounted)
                      setState(() {
                        _isFollowingUser = false;
                      });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vit_navigation_app',
                  maxZoom: 19.0,
                  // ⭐️ Removed const from CachedTileProvider
                  tileProvider: CachedTileProvider(),
                ),
                if (_isLocationServiceEnabled)
                  CurrentLocationLayer(
                    // Using CurrentLocationLayer
                    // style: LocationMarkerStyle(...) // Optional: Customize marker appearance
                  ),
                if (routePolylines.isNotEmpty)
                  PolylineLayer(polylines: routePolylines),
                MarkerLayer(markers: locationMarkers),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      icon: Icon(Icons.search, color: Colors.grey),
                      hintText: 'Search for a building, lab, or office...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16.0,
            bottom: 230.0,
            child: FloatingActionButton(
              heroTag: 'gps_btn',
              onPressed: _centerMapOnUser,
              backgroundColor: Colors.blue[600],
              child: const Icon(Icons.gps_fixed, color: Colors.white),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.2,
            minChildSize: 0.0,
            maxChildSize: 0.9,
            expand: true,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedIndex == 0
                                      ? 'Latest in the area'
                                      : _getTabTitle(_selectedIndex),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '24°',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.cloud,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        '● NAQI',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Container(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 100.0,
                          ),
                          child: _buildCurrentContent(_selectedIndex),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        bottom: MediaQuery.of(context).padding.bottom + 20.0,
                        top: 8.0,
                      ),
                      child: CustomNavigationBar(
                        selectedIndex: _selectedIndex,
                        onItemSelected: _onItemTapped,
                        items: const [
                          CustomNavigationBarItem(
                            icon: Icons.explore_outlined,
                            selectedIcon: Icons.explore,
                            label: 'Explore',
                          ),
                          CustomNavigationBarItem(
                            icon: Icons.list_alt_outlined,
                            selectedIcon: Icons.list_alt,
                            label: 'Directory',
                          ),
                          CustomNavigationBarItem(
                            icon: Icons.calendar_today_outlined,
                            selectedIcon: Icons.calendar_today,
                            label: 'Events',
                          ),
                          CustomNavigationBarItem(
                            icon: Icons.person_outline,
                            selectedIcon: Icons.person,
                            label: 'Profile',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: _isRouting ? Offset.zero : const Offset(0, 2),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Card(
                    elevation: 10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isRouting && _activeSteps.isNotEmpty)
                            Row(
                              children: [
                                _getManeuverIcon(
                                  _activeSteps[_currentStepIndex],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    _activeSteps[_currentStepIndex].instruction,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 3,
                                  ),
                                ),
                              ],
                            ),
                          if (_isRouting &&
                              _activeSteps.isNotEmpty &&
                              _currentStepIndex + 1 < _activeSteps.length)
                            Column(
                              children: [
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(left: 56.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Then: ${_activeSteps[_currentStepIndex + 1].instruction}",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Colors.grey[700],
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const Divider(height: 24, thickness: 0.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.safety_check_outlined,
                                size: 18,
                                color: Colors.blueGrey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Safety tip: When crossing a path, look both ways! (We don't do collision detection... yet.)",
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.blueGrey[700],
                                        fontStyle: FontStyle.italic,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.close),
                            label: const Text("Stop Navigation"),
                            onPressed: _resetNavigationState,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[600],
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Custom Widgets ---
class CustomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<CustomNavigationBarItem> items;
  final Color backgroundColor;
  final Color selectedItemColor;
  final Color unselectedItemColor;
  final double itemHeight;
  final double borderRadius;
  const CustomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    this.backgroundColor = Colors.white,
    this.selectedItemColor = Colors.blue,
    this.unselectedItemColor = Colors.grey,
    this.itemHeight = 70.0,
    this.borderRadius = 30.0,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      height: itemHeight,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onItemSelected(index),
              child: Container(
                height: itemHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? selectedItemColor.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(borderRadius - 5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      color: isSelected
                          ? selectedItemColor
                          : unselectedItemColor,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected
                            ? selectedItemColor
                            : unselectedItemColor,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class CustomNavigationBarItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const CustomNavigationBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class DirectoryScreen extends StatelessWidget {
  final List<Location> allLocations;
  final Function(Location) onLocationSelected;
  const DirectoryScreen({
    super.key,
    required this.allLocations,
    required this.onLocationSelected,
  });
  @override
  Widget build(BuildContext context) {
    final groupedLocations = <String, List<Location>>{};
    for (var loc in allLocations) {
      if (!groupedLocations.containsKey(loc.category)) {
        groupedLocations[loc.category] = [];
      }
      groupedLocations[loc.category]!.add(loc);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const TextField(
              decoration: InputDecoration(
                icon: Icon(Icons.search, color: Colors.grey),
                hintText: 'Search within Directory...',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...groupedLocations.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  const Divider(),
                  ...entry.value.map((location) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 1,
                      child: ListTile(
                        leading: const Icon(
                          Icons.location_city,
                          color: Colors.blue,
                        ),
                        title: Text(
                          location.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          location.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          onLocationSelected(location);
                        },
                      ),
                    );
                  }).toList(),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _TransportationOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String duration;
  final String distance;
  final bool isSelected;
  final VoidCallback onTap;
  const _TransportationOption({
    required this.icon,
    required this.label,
    required this.duration,
    required this.distance,
    this.isSelected = false,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue[700]!;
    final cardColor = isSelected ? primaryColor : Colors.white;
    final iconTextColor = isSelected ? Colors.white : primaryColor;
    final dataTextColor = primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? primaryColor
                    : primaryColor.withOpacity(0.5),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.3),
                        blurRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: iconTextColor, size: 30),
          ),
          const SizedBox(height: 4),
          Text(
            duration,
            style: TextStyle(fontWeight: FontWeight.bold, color: dataTextColor),
          ),
          Text(
            distance,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: dataTextColor)),
        ],
      ),
    );
  }
}

// ⭐️ Corrected CachedTileProvider constructor
class CachedTileProvider extends TileProvider {
  // Removed const
  CachedTileProvider();
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(getTileUrl(coordinates, options));
  }
}
