import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure you run 'flutter run' on a device/emulator, as the map relies on real GPS.
  runApp(const VitNavigationApp());
}

// --- Data Model for a Location ---
class Location {
  final String name;
  final String category;
  final String description;
  final LatLng coordinates;

  const Location({
    required this.name,
    required this.category,
    required this.description,
    required this.coordinates,
  });
}

// --- Data Model for a Route Step ---
class RouteStep {
  final String instruction;
  final double distance;
  final LatLng location;
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

  double _sheetPosition = 0.2; // Default initial size

  late final AnimationController _rotationAnimationController;

  bool _isFollowingUser = false;

  List<LatLng> _fullRouteCoordinates = [];
  List<LatLng> _remainingRouteCoordinates = [];

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

  // Search controller and results
  final TextEditingController _searchController = TextEditingController();
  List<Location> _searchResults = [];
  bool _isSearchActive = false;

  // --- Night Mode State ---
  bool _isNightMode = false;

  // --- OSRM Configuration Constants ---
  // Use 127.0.0.1 for local Docker access
  static const String _osrmHost = '127.0.0.1';
  // Port 6000 used for walk profile due to conflict on 5000
  static const int _walkPort = 6000;
  // Port 5001 assumed for bike profile
  static const int _bikePort = 5001;

  final List<Location> _allLocations = const [
    // --- Original Locations (Retained) ---
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
    // ------------------------------------

    // --- New Locations from Image ---
    Location(
      name: 'B block',
      category: 'Academic Block',
      description: 'Academic/Department Block B.',
      coordinates: LatLng(12.9744807, 79.1575831),
    ),
    Location(
      name: 'B Annexe',
      category: 'Academic Block',
      description: 'Academic/Department Block B Annexe.',
      coordinates: LatLng(12.9749303, 79.1573685),
    ),
    Location(
      name: 'F block',
      category: 'Academic Block',
      description: 'Academic/Department Block F.',
      coordinates: LatLng(12.9739789, 79.1583341),
    ),
    Location(
      name: 'A block',
      category: 'Academic Block',
      description: 'Academic/Department Block A.',
      coordinates: LatLng(12.9730641, 79.1573417),
    ),
    Location(
      name: 'C block',
      category: 'Academic Block',
      description: 'Academic/Department Block C.',
      coordinates: LatLng(12.9730589, 79.158141),
    ),
    Location(
      name: 'D annexe',
      category: 'Academic Block',
      description: 'Academic/Department Block D Annexe.',
      coordinates: LatLng(12.9733359, 79.1588652),
    ),
    Location(
      name: 'D block',
      category: 'Academic Block',
      description: 'Academic/Department Block D.',
      coordinates: LatLng(12.97297, 79.1588277),
    ),
    Location(
      name: 'G block',
      category: 'Academic Block',
      description: 'Academic/Department Block G.',
      coordinates: LatLng(12.9734143, 79.1597182),
    ),
    Location(
      name: 'E block',
      category: 'Academic Block',
      description: 'Academic/Department Block E.',
      coordinates: LatLng(12.9729595, 79.1597611),
    ),
    Location(
      name: 'Sanjay shop benzo',
      category: 'Shop/Café',
      description: 'A popular campus shop.',
      coordinates: LatLng(12.972787, 79.1592514),
    ),
    Location(
      name: 'Enzo',
      category: 'Shop/Café',
      description: 'Campus eating spot/café.',
      coordinates: LatLng(12.9722442, 79.1588545),
    ),
    Location(
      name: 'H block',
      category: 'Academic Block',
      description: 'Academic/Department Block H.',
      coordinates: LatLng(12.9723793, 79.1575026),
    ),
    Location(
      name: 'J block',
      category: 'Academic Block',
      description: 'Academic/Department Block J.',
      coordinates: LatLng(12.9723688, 79.1582215),
    ),
    Location(
      name: 'Chota dhobi',
      category: 'Hostel Services',
      description: 'Small laundry service near men\'s hostels.',
      coordinates: LatLng(12.9721702, 79.1587794),
    ),
    Location(
      name: 'Men\'s Hostel Indoor Complex (Sports)',
      category: 'Sports',
      description: 'Indoor sports facilities within men\'s hostel area.',
      coordinates: LatLng(12.9721336, 79.1591495),
    ),
    Location(
      name: 'Bright power laundry',
      category: 'Hostel Services',
      description: 'Laundry service facility.',
      coordinates: LatLng(12.9723688, 79.1593802),
    ),
    Location(
      name: 'Waste Water Treatment Plant (West)',
      category: 'Utilities',
      description: 'West side waste water treatment facility.',
      coordinates: LatLng(12.9721075, 79.1599542),
    ),
    Location(
      name: 'Waste Water Treatment Plant (East)',
      category: 'Utilities',
      description: 'East side waste water treatment facility.',
      coordinates: LatLng(12.9721231, 79.1605952),
    ),
    Location(
      name: 'MH swimming pool',
      category: 'Hostel Sports',
      description: 'Men\'s Hostel swimming pool.',
      coordinates: LatLng(12.9744546, 79.1608179),
    ),
    Location(
      name: 'Park (Thiruvalluvar Statue)',
      category: 'Landmark',
      description: 'Park area featuring the Thiruvalluvar statue.',
      coordinates: LatLng(12.9718408, 79.156816),
    ),
    Location(
      name: 'MH volleyball court',
      category: 'Hostel Sports',
      description: 'Men\'s Hostel volleyball court.',
      coordinates: LatLng(12.9717938, 79.1571406),
    ),
    Location(
      name: 'MH basketball court',
      category: 'Hostel Sports',
      description: 'Men\'s Hostel basketball court.',
      coordinates: LatLng(12.9717598, 79.1574034),
    ),
    Location(
      name: 'MH TENNIS COURT',
      category: 'Hostel Sports',
      description: 'Men\'s Hostel tennis court.',
      coordinates: LatLng(12.971718, 79.1577843),
    ),
    Location(
      name: 'K BLOCK',
      category: 'Academic Block',
      description: 'Academic/Department Block K.',
      coordinates: LatLng(12.9723296, 79.1615045),
    ),
    Location(
      name: 'FOOD PARK (FOOD MALL + FOODCY)',
      category: 'Food Courts',
      description: 'Food park, mall, and Foodcy outlet.',
      coordinates: LatLng(12.9723845, 79.1620812),
    ),
    Location(
      name: 'MH NESCAFE',
      category: 'Shop/Café',
      description: 'Nescafe stall in the men\'s hostel area.',
      coordinates: LatLng(12.9726851, 79.1620409),
    ),
    Location(
      name: 'L BLOCK',
      category: 'Academic Block',
      description: 'Academic/Department Block L.',
      coordinates: LatLng(12.9725047, 79.1627812),
    ),
    Location(
      name: 'SJT (S.J.T. Block)',
      category: 'Academic Block',
      description: 'S.J.T. Academic Block.',
      coordinates: LatLng(12.9709496, 79.1640177),
    ),
    Location(
      name: 'TT (Technology Tower) East Side',
      category: 'Academic Block',
      description: 'Technology Tower entrance/east side.',
      coordinates: LatLng(12.9706072, 79.1595545),
    ),
  ];

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationServiceEnabled = false;

  // --- Rerouting State ---
  bool _isRerouting = false;
  static const double _rerouteThreshold = 30.0; // 30 meters

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

    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Listen to search controller
    _searchController.addListener(_onSearchChanged);

    // Listen to sheet controller
    _sheetController.addListener(_onSheetMoved);
  }

  // Corrected listener
  void _onSheetMoved() {
    // The 'mounted' check is all we need here.
    if (mounted) {
      setState(() {
        _sheetPosition = _sheetController.size;
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _flutterTts.stop();
    _rotationAnimationController.dispose();

    // Dispose search controller
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    // Dispose sheet controller listener
    _sheetController.removeListener(_onSheetMoved);

    super.dispose();
  }

  // Search logic
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (_isSearchActive) {
        setState(() {
          _isSearchActive = false;
          _searchResults = [];
        });
      }
    } else {
      final results = _allLocations.where((loc) {
        return loc.name.toLowerCase().contains(query) ||
            loc.description.toLowerCase().contains(query) ||
            loc.category.toLowerCase().contains(query);
      }).toList();

      setState(() {
        _isSearchActive = true;
        _searchResults = results;
      });
    }
  }

  // Clear search
  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus(); // Hide keyboard
    setState(() {
      _isSearchActive = false;
      _searchResults = [];
    });
  }

  // Handle tapping a search result
  void _onSearchResultTapped(Location location) {
    _clearSearch(); // Clears text, sets _isSearchActive=false, attempts unfocus

    // Add direct unfocus attempt
    FocusManager.instance.primaryFocus?.unfocus();

    _setDestinationFromDirectory(location); // Use existing method
  }

  // --- Toggle Night Mode ---
  void _toggleNightMode() {
    if (!mounted) return;
    setState(() {
      _isNightMode = !_isNightMode;
    });
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

  // Helper method for smooth rotation
  void _animateRotationTo(double targetRotation) {
    final currentRotation = _mapController.camera.rotation;
    // Normalize rotations to be between -180 and 180 to find shortest path
    double normalize(double angle) {
      while (angle <= -180) angle += 360;
      while (angle > 180) angle -= 360;
      return angle;
    }

    final currentNormalized = normalize(currentRotation);
    final targetNormalized = normalize(targetRotation);

    // Calculate the difference, ensuring it takes the shortest path
    double diff = targetNormalized - currentNormalized;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    final finalRotation =
        currentRotation + diff; // Target rotation via shortest path

    final tween = Tween<double>(begin: currentRotation, end: finalRotation);

    final animation = tween.animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _rotationAnimationController.stop();
    // Remove potential old listener before adding new one
    animation.removeListener(() {}); // No-op remove just in case
    animation.addListener(() {
      if (mounted) {
        _mapController.rotate(animation.value);
      }
    });

    // Clean up listener when animation completes or is dismissed
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeListener(() {}); // Clean up listener
      }
    });

    _rotationAnimationController.reset();
    _rotationAnimationController.forward();
  }

  Future<void> _checkAndStartLocationStream() async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_isLocationServiceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) {
      setState(() {}); // Update UI if service became enabled
    }

    if (!_isLocationServiceEnabled) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // Keep at 0 for frequent updates
    );

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        // --- MODIFIED: Made the listener async ---
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            if (!mounted) return;

            setState(() {
              _currentPosition = position;
            });

            debugPrint(
              "New Position: ${position.latitude}, ${position.longitude}, Heading: ${position.heading}",
            );

            // --- MODIFIED: Reworked all navigation logic ---
            if (_isRouting && _activeSteps.isNotEmpty) {
              final userLocation = LatLng(
                position.latitude,
                position.longitude,
              );

              // --- NEW REROUTING & PATH SNAPPING LOGIC ---

              // 1. Find closest point on the *original* full route
              int closestPointIndex = -1;
              double minDistance = double.infinity;

              if (_fullRouteCoordinates.isEmpty) return; // No route to check

              for (int i = 0; i < _fullRouteCoordinates.length; i++) {
                final point = _fullRouteCoordinates[i];
                final distance = Geolocator.distanceBetween(
                  userLocation.latitude,
                  userLocation.longitude,
                  point.latitude,
                  point.longitude,
                );

                if (distance < minDistance) {
                  minDistance = distance;
                  closestPointIndex = i;
                }
              }

              if (closestPointIndex == -1) return; // Should not happen

              // 2. Check for deviation (Rerouting)
              if (minDistance > _rerouteThreshold && !_isRerouting) {
                // --- USER IS OFF-ROUTE ---
                if (mounted) {
                  setState(() {
                    _isRerouting = true; // Set flag to prevent spam
                    // Hide the old bad line while we recalculate
                    _remainingRouteCoordinates = [];
                  });
                }

                // Fetch a new route from the user's current (off-route) position
                final bool routeFound = await _fetchRouteDetails(
                  _selectedProfile,
                );

                if (routeFound && mounted) {
                  setState(() {
                    // Get the newly cached route
                    final newRoute = _selectedProfile == 'walk'
                        ? _cachedWalkRoute
                        : _cachedBikeRoute;
                    final newSteps = _selectedProfile == 'walk'
                        ? _cachedWalkSteps
                        : _cachedBikeSteps;

                    _fullRouteCoordinates = newRoute;
                    _remainingRouteCoordinates = List.from(
                      newRoute,
                    ); // Use full new route
                    _activeSteps = newSteps;
                    _currentStepIndex =
                        0; // Reset to the start of the new route
                    _isRerouting = false; // Rerouting complete
                  });
                  // Announce the new first step
                  _speak(
                    "Rerouting. ${_activeSteps.isNotEmpty ? _activeSteps[0].instruction : ''}",
                  );
                } else if (mounted) {
                  // Failed to find a new route, just reset reroute flag
                  setState(() {
                    _isRerouting = false;
                  });
                }
              } else if (!_isRerouting) {
                // --- USER IS ON-ROUTE (CONTINUOUS PATH SHORTENING) ---

                // The remaining route is just the sub-list from the closest point.
                final List<LatLng> newRemainingPoints = _fullRouteCoordinates
                    .sublist(closestPointIndex);

                if (mounted) {
                  setState(() {
                    _remainingRouteCoordinates = newRemainingPoints;
                  });
                }

                // --- Original step-checking logic (can now run) ---
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
              }
              // --- END NEW LOGIC ---
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

  // --- MODIFIED: Route Summary Fetch to use Custom OSRM Server ---
  Future<bool> _fetchRouteSummary(
    String profile, {
    bool fireStateUpdate = false,
  }) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

    if (fireStateUpdate && !_isModalLoading && mounted) {
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

    // Use the custom OSRM configuration
    final int port = profile == 'walk' ? _walkPort : _bikePort;

    final url = Uri.parse(
      'http://$_osrmHost:$port/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=false&geometries=geojson',
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

  // --- MODIFIED: Route Details Fetch to use Custom OSRM Server ---
  Future<bool> _fetchRouteDetails(String profile) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

    // Don't reset state if we are rerouting (it's handled in the listener)
    if (mounted && !_isRerouting) {
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

    // Use the custom OSRM configuration
    final int port = profile == 'walk' ? _walkPort : _bikePort;

    final url = Uri.parse(
      'http://$_osrmHost:$port/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true',
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

          // We must have at least a start and end point to be valid
          if (points.length < 2) {
            debugPrint(
              'Route details fetch failed for $profile: Too few points',
            );
            return false;
          }

          if (mounted) {
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
    return '$hours hr $remainingMinutes min';
  }

  void _resetNavigationState() {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedLocation = null;
      _tappedDestination = null;
      _fullRouteCoordinates = [];
      _remainingRouteCoordinates = [];
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
      _isRerouting = false; // --- NEW: Reset reroute flag
    });
    _flutterTts.stop();

    if (mounted && _mapController.camera.rotation != 0) {
      _animateRotationTo(0); // Use smooth animation
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
      _fullRouteCoordinates = [];
      _remainingRouteCoordinates = [];
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
        0.95,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onMapLongPress(TapPosition tapPosition, latlong.LatLng point) {
    if (!mounted) return; // Added mounted check
    setState(() {
      _selectedLocation = null;
      _tappedDestination = _toGoogleLatLng(point); // Convert
      _fullRouteCoordinates = [];
      _remainingRouteCoordinates = [];
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
    if (!mounted) return;

    if (_isFollowingUser) {
      // --- IS CURRENTLY FOLLOWING ---
      // Turn OFF following mode and rotate to North.
      setState(() {
        _isFollowingUser = false;
      });

      _animateRotationTo(0); // Use smooth animation
    } else {
      // --- IS NOT CURRENTLY FOLLOWING ---
      // Turn ON following mode and move to the user's location.
      // The CurrentLocationLayer will handle the rotation to the user's heading.
      setState(() {
        _isFollowingUser = true;
      });

      if (_currentPosition != null) {
        _mapController.move(
          _toFlutterMapLatLng(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          ),
          18.0, // Zoom in a bit
        );
      } else {
        // If we don't have a position, just show a message.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fetching your location...')),
        );
        _checkAndStartLocationStream();
      }
    }
  }

  Future<void> _startNavigation({
    required String profile,
    required List<LatLng> route,
    required List<RouteStep> steps,
  }) async {
    if (!mounted) return; // Added mounted check

    _clearSearch(); // Clear search/dismiss keyboard

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
      _fullRouteCoordinates = route;
      _remainingRouteCoordinates = List.from(route); // Start with a full copy
      _activeSteps = steps;
      _currentStepIndex = 0;
      _isRouting = true; // This will hide the search bar AND hide the bottom UI
      _isFollowingUser = true; // This now controls the map
      _isRerouting = false; // --- NEW: Reset reroute flag ---
    });

    // 3. Move map to user's location
    // The CurrentLocationLayer will handle the rotation automatically
    if (_currentPosition != null) {
      _mapController.move(
        _toFlutterMapLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
        18.0,
      );
    } else {
      // Fallback if no position yet: Fit route bounds
      final flutterMapPoints = route.map(_toFlutterMapLatLng).toList();
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
              minChildSize: 0,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                final startLocationText = _currentPosition != null
                    ? 'Your Current Location'
                    : 'Getting Location...';
                // Check the *cached* route, not the active one
                final bool showRouteDetails =
                    _selectedProfile.isNotEmpty &&
                    (_selectedProfile == 'walk'
                        ? _cachedWalkRoute.isNotEmpty
                        : _cachedBikeRoute.isNotEmpty);
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
                                      if (Navigator.canPop(sheetContext)) {
                                        Navigator.pop(sheetContext);
                                      }
                                      _startNavigation(
                                        profile: 'walk',
                                        route: _cachedWalkRoute,
                                        steps: _cachedWalkSteps,
                                      );
                                    } else if (_walkDuration != 'Err') {
                                      if (Navigator.canPop(sheetContext)) {
                                        Navigator.pop(sheetContext);
                                      }
                                      if (mounted) {
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
                                      if (Navigator.canPop(sheetContext)) {
                                        Navigator.pop(sheetContext);
                                      }
                                      _startNavigation(
                                        profile: 'bike',
                                        route: _cachedBikeRoute,
                                        steps: _cachedBikeSteps,
                                      );
                                    } else if (_bikeDuration != 'Err') {
                                      if (Navigator.canPop(sheetContext)) {
                                        Navigator.pop(sheetContext);
                                      }
                                      if (mounted) {
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
                                    }
                                  },
                                ),
                              ],
                            ),
                      const Divider(height: 24),
                      if (showRouteDetails) ...[
                        _buildStep(
                          'Total Distance: $_activeRouteDistance',
                          icon: Icons.straighten,
                        ),
                        _buildStep(
                          'Estimated Time: $_activeRouteDuration',
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
            _buildEventCard("Cultural Fest 125", "Open Arena", "5th Nov"),
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
    // --- START: NEW DYNAMIC LOGIC ---
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomPadding = mediaQuery.padding.bottom;

    // 1. Define the search bar's total height (including status bar)
    final double searchBarHeight =
        mediaQuery.padding.top + 80.0; // Approx height

    // 2. Define the animation trigger ranges
    const double sheetStartMove = 0.2; // Sheet pos when animation starts
    const double sheetEndMove = 0.4; // Sheet pos when animation is complete

    // 3. Calculate the progress of the sheet's drag
    // This calculates how far (0.0 to 1.0) the user has dragged
    // within our defined range (0.2 to 0.4).
    double dragProgress =
        (_sheetPosition - sheetStartMove) / (sheetEndMove - sheetStartMove);

    // 4. Clamp progress between 0.0 (not started) and 1.0 (fully finished)
    dragProgress = dragProgress.clamp(0.0, 1.0);

    // 5. Calculate the search bar's vertical offset
    final double searchBarTopOffset = -searchBarHeight * dragProgress;

    // 6. Calculate the search bar's opacity
    final double searchBarOpacity = _isRouting ? 0.0 : (1.0 - dragProgress);

    // GPS Button logic (remains the same)
    final bool isSheetLow = _sheetPosition < 0.25;
    final double gpsButtonOpacity = (_isRouting || !isSheetLow) ? 0.0 : 1.0;

    // 7. Calculate the height of the navigation card (approximation)
    // The navigation card is roughly 200 units tall + bottom padding.
    // The AnimatedSlide has a padding of 12.0 on all sides.
    final double navCardHeight = 200.0 + bottomPadding;

    // 8. Calculate the dynamic bottom position for the Re-centre button
    // The Re-centre button should sit just above the navigation card when it's visible.
    final double recentreButtonBottomOffset =
        navCardHeight + 16.0; // Card height + spacing
    // --- END: NEW DYNAMIC LOGIC ---

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
    if (_remainingRouteCoordinates.isNotEmpty) {
      routePolylines.add(
        Polyline(
          points: _remainingRouteCoordinates.map(_toFlutterMapLatLng).toList(),
          strokeWidth: 5.0,
          color: Colors.deepPurple,
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevents resize when keyboard appears
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
                  // Manually panning will stop the "follow" mode
                  if (_isFollowingUser && details.buttons == kPrimaryButton) {
                    if (mounted) {
                      setState(() {
                        _isFollowingUser = false;
                      });
                    }
                  }
                },
              ),
              children: [
                TileLayer(
                  // --- FIX: Using public CartoDB Dark Tileset (no 401 error) ---
                  urlTemplate: _isNightMode
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vit_navigation_app',
                  maxZoom: 19.0,
                  tileProvider: CachedTileProvider(),
                  // --- FIX: Explicitly handle {r} placeholder to clear warning ---
                  retinaMode: true,
                ),
                if (_isLocationServiceEnabled)
                  CurrentLocationLayer(
                    followOnLocationUpdate: _isFollowingUser
                        ? FollowOnLocationUpdate.always
                        : FollowOnLocationUpdate.never,
                    turnOnHeadingUpdate: _isFollowingUser
                        ? TurnOnHeadingUpdate.always
                        : TurnOnHeadingUpdate.never,
                    turnAnimationCurve: Curves.easeOut,
                    turnAnimationDuration: const Duration(milliseconds: 400),
                    style: LocationMarkerStyle(
                      marker: DefaultLocationMarker(
                        color: Colors.blue.shade700,
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      markerSize: const Size(40, 40),
                      showHeadingSector: false,
                    ),
                  ),
                if (routePolylines.isNotEmpty)
                  PolylineLayer(polylines: routePolylines),
                MarkerLayer(markers: locationMarkers),
              ],
            ),
          ),

          // --- MODIFIED: SEARCH BAR WRAPPER ---
          Transform.translate(
            offset: Offset(0, searchBarTopOffset), // Use the new dynamic offset
            child: AnimatedOpacity(
              opacity: searchBarOpacity, // Use the new dynamic opacity
              duration: const Duration(milliseconds: 100), // Quick fade
              child: IgnorePointer(
                // Ignore taps if routing OR if it's sliding off-screen
                ignoring: _isRouting || dragProgress > 0.0,
                child: Stack(
                  // Use Stack to keep original positioning logic
                  children: [
                    // --- Search Bar ---
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
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                icon: const Icon(
                                  Icons.search,
                                  color: Colors.grey,
                                ),
                                hintText:
                                    'Search for a building, lab, or office...',
                                border: InputBorder.none,
                                suffixIcon: _isSearchActive
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.grey,
                                        ),
                                        onPressed: _clearSearch,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // --- Search Results List ---
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 80.0,
                      left: 16.0,
                      right: 16.0,
                      child: Visibility(
                        visible: _isSearchActive && _searchResults.isNotEmpty,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final location = _searchResults[index];
                                  return ListTile(
                                    title: Text(location.name),
                                    subtitle: Text(location.category),
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: Colors.blue,
                                    ),
                                    onTap: () =>
                                        _onSearchResultTapped(location),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // --- END OF SEARCH BAR MODIFICATION ---

          // --- NEW: NIGHT MODE BUTTON (Top Right, Fades with Search/Sheet) ---
          Positioned(
            top: mediaQuery.padding.top + 80.0, // Under search bar (approx)
            right: 16.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: gpsButtonOpacity, // Same logic as GPS button
              child: IgnorePointer(
                ignoring: gpsButtonOpacity == 0.0,
                child: FloatingActionButton(
                  heroTag: 'night_mode_btn',
                  onPressed: _toggleNightMode,
                  backgroundColor: _isNightMode ? Colors.white : Colors.black,
                  foregroundColor: _isNightMode ? Colors.black : Colors.white,
                  mini: true, // Make it smaller to fit
                  child: Icon(_isNightMode ? Icons.wb_sunny : Icons.dark_mode),
                ),
              ),
            ),
          ),
          // --- END NEW NIGHT MODE BUTTON ---

          // --- MODIFIED: RE-CENTRE BUTTON (FOR NAVIGATION MODE) ---
          if (_isRouting && !_isFollowingUser)
            Positioned(
              // Kept on the right, above the nav card
              bottom: recentreButtonBottomOffset + 10,
              right: 16.0,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                color: Colors.blueAccent, // Dark background
                child: InkWell(
                  onTap: _centerMapOnUser, // Re-uses existing logic
                  borderRadius: BorderRadius.circular(30),
                  child: const Padding(
                    // Increased vertical padding for height
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 16.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.navigation_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Re-centre',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // --- END NEW RE-CENTRE BUTTON ---

          // --- GPS Button (Existing, only visible when sheet is low and not routing) ---
          Positioned(
            right: 16.0,
            bottom: (screenHeight * _sheetPosition) + 20.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: gpsButtonOpacity,
              child: IgnorePointer(
                ignoring: gpsButtonOpacity == 0.0,
                child: FloatingActionButton(
                  heroTag: 'gps_btn',
                  onPressed: _centerMapOnUser,
                  backgroundColor: _isFollowingUser
                      ? Colors.white
                      : Colors.blue[600],
                  foregroundColor: _isFollowingUser
                      ? Colors.blue[600]
                      : Colors.white,
                  child: Icon(
                    _isFollowingUser ? Icons.navigation : Icons.gps_fixed,
                  ),
                ),
              ),
            ),
          ),

          // =========================================================================
          // === DRAGGABLE SCROLLABLE SHEET WRAPPED IN ANIMATED SLIDE ===
          // =========================================================================
          AnimatedSlide(
            // Slide down by 100% of the screen height (vertical offset of 1.0)
            offset: _isRouting ? const Offset(0, 1) : const Offset(0, 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.2,
              minChildSize: 0.2,
              maxChildSize: 0.95,
              expand: true,
              builder: (BuildContext context, ScrollController scrollController) {
                // IgnorePointer when sliding off-screen to prevent interaction
                return IgnorePointer(
                  ignoring: _isRouting,
                  child: Container(
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
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            child: Column(
                              children: [
                                // --- HEADER ---
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 10.0,
                                    bottom: 8.0,
                                  ),
                                  child: Column(
                                    children: [
                                      Center(
                                        child: Container(
                                          width: 40,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _selectedIndex == 0
                                                  ? 'Latest in the area'
                                                  : _getTabTitle(
                                                      _selectedIndex,
                                                    ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                              ),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    '24°',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                // --- DIVIDER ---
                                const Divider(height: 1),
                                // --- MAIN CONTENT ---
                                Container(
                                  padding: const EdgeInsets.only(
                                    top: 16.0,
                                    // Removed bottom padding because the navigation bar is moved
                                    bottom: 0.0,
                                  ),
                                  child: _buildCurrentContent(_selectedIndex),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // --- REMOVED NAVIGATION BAR FROM HERE ---
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // =========================================================================
          // === NAVIGATION BAR WRAPPED IN ANIMATED SLIDE AND REPOSITIONED ===
          // =========================================================================
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              // Slide down by 100% of its height (Offset(0, 2) is a safe value for this)
              offset: _isRouting ? const Offset(0, 2) : const Offset(0, 0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: _isRouting, // Disable interaction when hidden
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom:
                          bottomPadding +
                          20.0, // Ensures margin from screen edge
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
                ),
              ),
            ),
          ),
          // --- END OF NAVIGATION BAR MODIFICATION ---

          // --- START OF NAVIGATION CARD (ROUTE INSTRUCTIONS) ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              // The instructions card appears when _isRouting is true
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
                                _isRerouting
                                    ? Icons.sync
                                    : Icons.safety_check_outlined,
                                size: 18,
                                color: Colors.blueGrey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isRerouting
                                      ? "Finding a new route..."
                                      : "Safety tip: When crossing a path, look both ways!",
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
          // --- END OF NAVIGATION CARD ---
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
                  }),
                ],
              ),
            );
          }),
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
    // Corrected BuildContext
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

// Corrected CachedTileProvider constructor
class CachedTileProvider extends TileProvider {
  CachedTileProvider(); // Removed const
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(getTileUrl(coordinates, options));
  }
}
