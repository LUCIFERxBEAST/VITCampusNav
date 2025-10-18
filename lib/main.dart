import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart' show Polyline;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  Location? _selectedLocation;
  LatLng? _tappedDestination;

  final MapController _mapController = MapController();
  // Controller for DraggableScrollableSheet
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // ROUTING STATE
  List<LatLng> _routeCoordinates = [];
  String _selectedProfile = '';
  bool _isRouting = false;

  // STATE FOR REAL-TIME CALCULATION
  String _walkDuration = '---';
  String _walkDistance = '---';
  String _bikeDuration = '---';
  String _bikeDistance = '---';

  // Modal Loading State
  bool _isModalLoading = false;

  // List of all Campus Locations
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

  // LOCATION STATE VARIABLES
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationServiceEnabled = false;

  // Getter to determine the final destination coordinates for routing/UI
  LatLng? get _finalDestinationCoordinates {
    return _selectedLocation?.coordinates ?? _tappedDestination;
  }

  // Getter to determine the destination Name for routing/UI
  String get _finalDestinationName {
    return _selectedLocation?.name ??
        (_tappedDestination != null ? 'Tapped Location' : 'Destination');
  }

  // Getter to return the active route duration/distance
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

  @override
  void initState() {
    super.initState();
    _checkAndStartLocationStream();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------
  // LOCATION & ROUTING LOGIC
  // -----------------------------------------------------

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

    setState(() {});

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            setState(() {
              _currentPosition = position;
            });
            if (_finalDestinationCoordinates != null && !_isModalLoading) {
              _fetchRouteData('walk', fireStateUpdate: true);
              _fetchRouteData('bike', fireStateUpdate: true);
            }
          },
        );
  }

  Future<bool> _fetchRouteData(
    String profile, {
    bool fireStateUpdate = false,
  }) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

    if (fireStateUpdate && !_isModalLoading) {
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

          if (fireStateUpdate) {
            if (mounted && !_isModalLoading) {
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
          }

          if (_routeCoordinates.isEmpty &&
              profile == _selectedProfile &&
              _selectedProfile != '') {
            _calculateRoute(profile);
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Route data fetch failed for $profile: $e');
      if (fireStateUpdate && mounted && !_isModalLoading) {
        setState(() {
          if (profile == 'walk') {
            _walkDuration = 'Err';
            _walkDistance = 'Err';
          } else if (profile == 'bike') {
            _bikeDuration = 'Err';
            _bikeDistance = 'Err';
          }
        });
      }
    }
    return false;
  }

  Future<void> _calculateRoute(String profile) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return;

    setState(() {
      _isRouting = true;
      _selectedProfile = profile;
      _routeCoordinates = [];
    });

    final start = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final end = destination;

    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=false',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'];

        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];

          List<LatLng> points = [];
          if (geometry['coordinates'] != null) {
            for (var coord in geometry['coordinates']) {
              points.add(LatLng(coord[1], coord[0]));
            }
          }

          setState(() {
            _routeCoordinates = points;
            _isRouting = false;
          });

          if (points.isNotEmpty) {
            final bounds = LatLngBounds.fromPoints(points);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(50),
              ),
            );
          }
        }
      } else {
        throw Exception('OSRM API returned status ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _routeCoordinates = [];
        _isRouting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route calculation failed: ${e.toString()}')),
      );
    }
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
    setState(() {
      _selectedLocation = null;
      _tappedDestination = null;
      _routeCoordinates = []; // Clears the polyline from the map
      _selectedProfile = '';
      _walkDuration = _bikeDuration = '---';
      _walkDistance = _bikeDistance = '---';
      _isModalLoading = false; // Reset loading state
    });
  }

  void _setDestinationFromDirectory(Location location) {
    setState(() {
      _selectedIndex = 0;
      _selectedLocation = location;
      _tappedDestination = null;
      _routeCoordinates = [];
      _selectedProfile = '';
      _walkDuration = _bikeDuration = _walkDistance = _bikeDistance = '---';
      _isModalLoading = false;
    });
    // Shrink the sheet back to the Explore view
    _sheetController.animateTo(
      0.2, // Minimized size
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _showDirectionsSheet(); // Relaunch directions logic
  }

  // 🌟 Controls the sheet's state and size based on tab selection
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      // Explore: Minimize the sheet
      _sheetController.animateTo(
        0.2, // Minimized size
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _resetNavigationState();
    } else {
      // Directory, Events, Profile: Expand the sheet
      _sheetController.animateTo(
        0.9, // Expanded size (near full screen)
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng latLng) {
    setState(() {
      _selectedLocation = null;
      _tappedDestination = latLng;
      _routeCoordinates = [];
      _selectedProfile = '';
      _walkDuration = _bikeDuration = _walkDistance = _bikeDistance = '---';
      _isModalLoading = false;
    });
    // Shrink the sheet back to the Explore view
    _sheetController.animateTo(
      0.2, // Minimized size
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _showDirectionsSheet();
  }

  void _centerMapOnUser() {
    if (_currentPosition != null) {
      final userLocation = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      _mapController.move(userLocation, 18.0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching your location...')),
      );
      _checkAndStartLocationStream();
    }
  }

  // Simplified version of directions sheet logic
  void _showDirectionsSheet() {
    // In this new architecture, routing details should ideally appear within
    // the main DraggableSheet content, but for now we'll keep the modal logic
    // separate if the user taps a destination marker on the map.

    if (_finalDestinationCoordinates == null) return;
    final destinationName = _finalDestinationName;

    // Set loading state BEFORE showing the sheet
    setState(() {
      _isModalLoading = true;
    });

    // Start fetching data in parallel
    final Future fetchWalk = _fetchRouteData('walk', fireStateUpdate: true);
    final Future fetchBike = _fetchRouteData('bike', fireStateUpdate: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
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

                      // ROUTING OPTIONS SECTION
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
                                // --- Walk Option ---
                                _TransportationOption(
                                  icon: Icons.directions_walk,
                                  label: 'Walk',
                                  duration: _walkDuration,
                                  distance: _walkDistance,
                                  isSelected: _selectedProfile == 'walk',
                                  onTap: () {
                                    setModalState(() {
                                      _selectedProfile = 'walk';
                                    });
                                    _calculateRoute('walk');
                                    Navigator.pop(sheetContext);
                                  },
                                ),
                                // --- Bike Option ---
                                _TransportationOption(
                                  icon: Icons.directions_bike,
                                  label: 'Bike',
                                  duration: _bikeDuration,
                                  distance: _bikeDistance,
                                  isSelected: _selectedProfile == 'bike',
                                  onTap: () {
                                    setModalState(() {
                                      _selectedProfile = 'bike';
                                    });
                                    _calculateRoute('bike');
                                    Navigator.pop(sheetContext);
                                  },
                                ),
                              ],
                            ),
                      const Divider(height: 24),

                      // CONDITIONAL DESCRIPTION AREA
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

  // Helper widget for direction inputs
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

  // Helper widget for direction steps
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

  // -----------------------------------------------------
  // NEW: Tab Content Widgets
  // -----------------------------------------------------

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
                // Quick Filters that were previously in the header can be placed here
                // if the sheet is slightly dragged up, but we'll leave the main
                // search/filters on top for map context.
              ],
            ),
          ),
        );
      case 1:
        // Directory Tab: Fully open to show directory
        return DirectoryScreen(
          allLocations: _allLocations,
          onLocationSelected: _setDestinationFromDirectory,
        );
      case 2:
        return ListView(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(), // Managed by parent SingleChildScrollView
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

  @override
  Widget build(BuildContext context) {
    const campusCenter = LatLng(12.970856249976618, 79.159515644555);

    final List<Marker> locationMarkers = [];
    if (_finalDestinationCoordinates != null) {
      locationMarkers.add(
        Marker(
          point: _finalDestinationCoordinates!,
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              _showDirectionsSheet();
            },
            child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true, // Allow body (map) to go behind the bottom sheet
      body: Stack(
        children: [
          // --- Map View (Full Screen) ---
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: campusCenter,
                initialZoom: 16.0,
                minZoom: 10.0,
                maxZoom: 19.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vit_navigation_app',
                  tileProvider: CachedTileProvider(),
                  maxZoom: 19.0,
                ),
                if (_isLocationServiceEnabled)
                  CurrentLocationLayer(
                    followOnLocationUpdate: FollowOnLocationUpdate.never,
                    alignPositionOnUpdate: AlignOnUpdate.never,
                    style: const LocationMarkerStyle(
                      marker: DefaultLocationMarker(color: Colors.blue),
                      markerSize: Size(40, 40),
                    ),
                  ),
                if (_routeCoordinates.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routeCoordinates,
                        strokeWidth: 5.0,
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                MarkerLayer(markers: locationMarkers),
              ],
            ),
          ),

          // --- Header: Search Bar (Top Overlay) ---
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

          // --- Floating Action Button (Raised) ---
          Positioned(
            right: 16.0,
            bottom: 230.0, // Raised to clear the minimized sheet
            child: FloatingActionButton(
              onPressed: _centerMapOnUser,
              backgroundColor: Colors.blue[600],
              child: const Icon(Icons.gps_fixed, color: Colors.white),
            ),
          ),

          // 🌟 Draggable Scrollable Sheet for Navigation and Content
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.2, // Smallest view
            minChildSize: 0.2,
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
                    // --- Header (Grabber, Title, Weather) ---
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
                                // Title changes based on state
                                Text(
                                  _selectedIndex == 0
                                      ? 'Latest in the area'
                                      : _getTabTitle(_selectedIndex),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                // Weather Info
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

                    // --- Main Content Area ---
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Container(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 100.0,
                          ), // Extra padding for safe area
                          child: _buildCurrentContent(_selectedIndex),
                        ),
                      ),
                    ),

                    // --- Bottom Navigation Bar (Floating Pill) ---
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        bottom:
                            MediaQuery.of(context).padding.bottom +
                            20.0, // Honor safe area
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
        ],
      ),
    );
  }
}

// -----------------------------------------------------
// CLEANED UP: CustomNavigationBar Widget (No Indicator)
// -----------------------------------------------------

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
                  // Use a background color change for selection
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

// Item model for CustomNavigationBar (unchanged)
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

// -----------------------------------------------------
// DIRECTORY SCREEN (Adapted to be part of the DraggableSheet)
// -----------------------------------------------------

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
          // Search bar for the Directory
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
                          // When a location is selected, the Directory is closed
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

// -----------------------------------------------------
// HELPER CLASSES (unchanged)
// -----------------------------------------------------

class CachedTileProvider extends TileProvider {
  CachedTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(getTileUrl(coordinates, options));
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
