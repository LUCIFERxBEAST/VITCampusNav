import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
// *** FIX: Removed google_maps_flutter and use latlong2 directly ***
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VitNavigationApp());
}

// --- Data Model for a Location ---
class Location {
  final String name;
  final String category;
  final String description;
  final LatLng coordinates; // <-- This is now from latlong2
  final String? buildingGroup;

  const Location({
    required this.name,
    required this.category,
    required this.description,
    required this.coordinates,
    this.buildingGroup,
  });
}

// --- Data Model for a Route Step ---
class RouteStep {
  final String instruction;
  final double distance;
  final LatLng location; // <-- This is now from latlong2
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
  LatLng? _tappedDestination; // <-- This is now from latlong2

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  double _sheetPosition = 0.2;

  late final AnimationController _rotationAnimationController;

  bool _isFollowingUser = false;

  List<LatLng> _fullRouteCoordinates = []; // <-- This is now from latlong2
  List<LatLng> _remainingRouteCoordinates = []; // <-- This is now from latlong2

  String _selectedProfile = '';
  bool _isRouting = false;

  List<LatLng> _cachedWalkRoute = []; // <-- This is now from latlong2
  List<LatLng> _cachedBikeRoute = []; // <-- This is now from latlong2
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

  final TextEditingController _searchController = TextEditingController();
  List<Location> _searchResults = [];
  bool _isSearchActive = false;

  // --- PERFORMANCE FIX: TileProvider created once ---
  final CachedTileProvider _tileProvider = CachedTileProvider();

  // // --- NETWORKING: OSRM Configuration Constants ---
  // static const String _osrmWalkBaseUrl =
  //     'https://walk-osrm-nav.trycloudflare.com';
  // static const String _osrmBikeBaseUrl =
  //     'https://bike-osrm-nav.trycloudflare.com';

  // // --- NETWORKING: Use the computer's local IP on the phone's hotspot network ---
  // static const String _osrmWalkBaseUrl = 'http://10.62.20.12:8999';
  // static const String _osrmBikeBaseUrl = 'http://10.62.20.12:5001';

  // --- OSRM Configuration Constants ---
  // Use the Tailscale Private IP
  static const String _osrmWalkBaseUrl = 'http://100.81.0.57:8999';
  static const String _osrmBikeBaseUrl = 'http://100.81.0.57:5001';

  // =========================================================================
  // === ALL CAMPUS LOCATIONS ===
  // =========================================================================
  final List<Location> _allLocations = const [
    // --- GATES & ENTRANCES ---
    Location(
      name: 'Main Gate',
      category: 'Entrance',
      description: 'The primary entrance...',
      coordinates: LatLng(12.9682391, 79.1558826),
    ),
    Location(
      name: 'Gate no 03',
      category: 'Entrance',
      description: 'Campus Entrance/Exit Gate 3.',
      coordinates: LatLng(12.9675699, 79.1586292),
    ),
    Location(
      name: 'Gate no 02',
      category: 'Entrance',
      description: 'Campus Entrance/Exit Gate 2.',
      coordinates: LatLng(12.9704451, 79.154048),
    ),
    Location(
      name: 'Main Gate Fountain',
      category: 'Landmark',
      description: 'Fountain near the Main Gate.',
      coordinates: LatLng(12.9686651, 79.1558826),
    ),
    // --- MEN'S HOSTEL (MH) ---
    Location(
      name: 'B Annexe (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'B Annexe, Men\'s Hostel',
      coordinates: LatLng(12.974865, 79.1574544),
      buildingGroup: 'MH-B-Annexe',
    ),
    Location(
      name: 'B Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'B Block, Men\'s Hostel',
      coordinates: LatLng(12.9744651, 79.1574866),
      buildingGroup: 'MH-B',
    ),
    Location(
      name: 'F Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'F Block, Men\'s Hostel',
      coordinates: LatLng(12.9737489, 79.1581356),
      buildingGroup: 'MH-F',
    ),
    Location(
      name: 'A Hostel (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'A Hostel, Men\'s Hostel',
      coordinates: LatLng(12.9729125, 79.1572076),
      buildingGroup: 'MH-A',
    ),
    Location(
      name: 'C Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'C Block, Men\'s Hostel',
      coordinates: LatLng(12.9728864, 79.1581142),
      buildingGroup: 'MH-C',
    ),
    Location(
      name: 'D Annexe (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'D Annexe, Men\'s Hostel',
      coordinates: LatLng(12.9732471, 79.158715),
      buildingGroup: 'MH-D-Annexe',
    ),
    Location(
      name: 'D Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'D Block, Men\'s Hostel',
      coordinates: LatLng(12.9728341, 79.1588384),
      buildingGroup: 'MH-D',
    ),
    Location(
      name: 'E Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'E Block, Men\'s Hostel',
      coordinates: LatLng(12.972787, 79.1597557),
      buildingGroup: 'MH-E',
    ),
    Location(
      name: 'G Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'G Block, Men\'s Hostel',
      coordinates: LatLng(12.9733908, 79.1602117),
      buildingGroup: 'MH-G',
    ),
    Location(
      name: 'H Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'H Block, Men\'s Hostel',
      coordinates: LatLng(12.9722094, 79.1574597),
      buildingGroup: 'MH-H',
    ),
    Location(
      name: 'J Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'J Block, Men\'s Hostel',
      coordinates: LatLng(12.9721885, 79.1581786),
      buildingGroup: 'MH-J',
    ),
    Location(
      name: 'K Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'K Block, Men\'s Hostel',
      coordinates: LatLng(12.9725204, 79.1614214),
      buildingGroup: 'MH-K',
    ),
    Location(
      name: 'L Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'L Block, Men\'s Hostel',
      coordinates: LatLng(12.9726955, 79.16269),
      buildingGroup: 'MH-L',
    ),
    Location(
      name: 'R Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'R Block, Men\'s Hostel',
      coordinates: LatLng(12.9731869, 79.1635108),
      buildingGroup: 'MH-R',
    ),
    Location(
      name: 'M Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'M Block, Men\'s Hostel',
      coordinates: LatLng(12.9727243, 79.16383),
      buildingGroup: 'MH-M',
    ),
    Location(
      name: 'Q Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'Q Block, Men\'s Hostel',
      coordinates: LatLng(12.9738456, 79.1639855),
      buildingGroup: 'MH-Q',
    ),
    Location(
      name: 'P Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'P Block, Men\'s Hostel',
      coordinates: LatLng(12.9738168, 79.1641894),
      buildingGroup: 'MH-P',
    ),
    Location(
      name: 'N Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'N Block, Men\'s Hostel',
      coordinates: LatLng(12.9751002, 79.1638058),
      buildingGroup: 'MH-N',
    ),
    Location(
      name: 'T Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'T Block, Men\'s Hostel',
      coordinates: LatLng(12.9747656, 79.1654634),
      buildingGroup: 'MH-T',
    ),
    Location(
      name: 'S Block (Men\'s Hostel)',
      category: 'Men\'s Hostel',
      description: 'S Block, Men\'s Hostel',
      coordinates: LatLng(12.974154, 79.1653722),
      buildingGroup: 'MH-S',
    ),
    // --- (MH Amenities) ---
    Location(
      name: 'Enzo Shop (Men\'s Hostel)',
      category: 'Shop/Café',
      description: 'Enzo Shop, Men\'s Hostel Area',
      coordinates: LatLng(12.9725074, 79.1589296),
    ),
    Location(
      name: 'Main Chota Dhobi (Men\'s Hostel)',
      category: 'Hostel Services',
      description: 'Main laundry service, Men\'s Hostel',
      coordinates: LatLng(12.9722878, 79.1588089),
    ),
    Location(
      name: 'Men\'s Hostel Indoor Stadium',
      category: 'Sports',
      description: 'Indoor sports stadium in MH area.',
      coordinates: LatLng(12.9722852, 79.1591173),
    ),
    Location(
      name: 'Bright Power Laundry (Men\'s Hostel)',
      category: 'Hostel Services',
      description: 'Bright Power Laundry, Men\'s Hostel',
      coordinates: LatLng(12.9724185, 79.1593426),
    ),
    Location(
      name: 'Waste Water Plant (Men\'s Hostel - West)',
      category: 'Utilities',
      description: 'Waste Water Treatment Plant, Men\'s Hostel',
      coordinates: LatLng(12.9723087, 79.1600588),
      buildingGroup: 'MH-WWP',
    ),
    Location(
      name: 'Waste Water Plant (Men\'s Hostel - East)',
      category: 'Utilities',
      description: 'Waste Water Treatment Plant, Men\'s Hostel',
      coordinates: LatLng(12.9723061, 79.1606033),
      buildingGroup: 'MH-WWP',
    ),
    Location(
      name: 'Food Park (Food Mall + Foodcy) (MH)',
      category: 'Food Courts',
      description: 'Food park, mall, and Foodcy outlet in MH area.',
      coordinates: LatLng(12.9725988, 79.1620383),
    ),
    Location(
      name: 'Nescafe (Near Foodpark, MH)',
      category: 'Shop/Café',
      description: 'Nescafe stall near the MH Foodpark.',
      coordinates: LatLng(12.9726929, 79.1620356),
    ),
    Location(
      name: 'Indian Bank (Men\'s Hostel)',
      category: 'Services',
      description: 'Indian Bank branch in MH area.',
      coordinates: LatLng(12.9732392, 79.1642135),
    ),
    Location(
      name: 'Chillout Plaza (Men\'s Hostel)',
      category: 'Food Courts',
      description: 'Chillout Plaza food area, Men\'s Hostel.',
      coordinates: LatLng(12.9733699, 79.1645327),
    ),
    Location(
      name: 'Helipad (Men\'s Hostel)',
      category: 'Landmark',
      description: 'Helipad near Men\'s Hostel.',
      coordinates: LatLng(12.975751, 79.1608393),
    ),
    Location(
      name: 'Outdoor Stadium (Men\'s Hostel)',
      category: 'Sports',
      description: 'Outdoor sports stadium, Men\'s Hostel.',
      coordinates: LatLng(12.9759653, 79.1601688),
    ),
    Location(
      name: 'Running Track (Men\'s Hostel)',
      category: 'Sports',
      description: 'Running track, Men\'s Hostel.',
      coordinates: LatLng(12.9759392, 79.1607535),
    ),
    Location(
      name: 'Swimming Pool (Men\'s Hostel)',
      category: 'Sports',
      description: 'Men\'s Hostel swimming pool.',
      coordinates: LatLng(12.9739998, 79.1607267),
    ),
    Location(
      name: 'Tiruvallur Statue',
      category: 'Landmark',
      description: 'Tiruvallur Statue Park',
      coordinates: LatLng(12.9718409, 79.156875),
    ),
    Location(
      name: 'Volleyball Court (Men\'s Hostel)',
      category: 'Sports',
      description: 'Men\'s Hostel volleyball court.',
      coordinates: LatLng(12.9719611, 79.1571647),
    ),
    Location(
      name: 'Basketball Court (Men\'s Hostel)',
      category: 'Sports',
      description: 'Men\'s Hostel basketball court.',
      coordinates: LatLng(12.9718984, 79.1574168),
    ),
    Location(
      name: 'Tennis Court (Men\'s Hostel)',
      category: 'Sports',
      description: 'Men\'s Hostel tennis court.',
      coordinates: LatLng(12.9718774, 79.1577923),
    ),
    // --- WOMEN'S HOSTEL (WH) ---
    Location(
      name: 'M Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'M Block, Women\'s Hostel',
      coordinates: LatLng(12.9684273, 79.1584575),
      buildingGroup: 'WH-M',
    ),
    Location(
      name: 'N Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'N Block, Women\'s Hostel',
      coordinates: LatLng(12.9679829, 79.1584629),
      buildingGroup: 'WH-N',
    ),
    Location(
      name: 'G Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'G Block, Women\'s Hostel',
      coordinates: LatLng(12.9684063, 79.1598871),
      buildingGroup: 'WH-G',
    ),
    Location(
      name: 'J Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'J Block, Women\'s Hostel',
      coordinates: LatLng(12.9680535, 79.1596162),
      buildingGroup: 'WH-J',
    ),
    Location(
      name: 'Mother Teresa Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'Mother Teresa Block, Women\'s Hostel',
      coordinates: LatLng(12.9710776, 79.1606569),
    ),
    Location(
      name: 'Jhasi Rani Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'Jhasi Rani Block, Women\'s Hostel',
      coordinates: LatLng(12.9712554, 79.1613275),
    ),
    Location(
      name: 'Ida Scudder Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'Ida Scudder Block, Women\'s Hostel',
      coordinates: LatLng(12.9711822, 79.1620409),
    ),
    Location(
      name: 'Suu Kyi Block (Women\'s Hostel)',
      category: 'Women\'s Hostel',
      description: 'Suu Kyi Block, Women\'s Hostel',
      coordinates: LatLng(12.971339, 79.1628027),
    ),
    // --- (WH Amenities) ---
    Location(
      name: 'VIT Women\'s Indoor Sports Room',
      category: 'Sports',
      description: 'Indoor sports room for Women\'s Hostel.',
      coordinates: LatLng(12.9707169, 79.1606677),
    ),
    Location(
      name: 'Swimming Pool (Women\'s Hostel)',
      category: 'Sports',
      description: 'Women\'s Hostel swimming pool.',
      coordinates: LatLng(12.9706803, 79.1614079),
    ),
    // --- ACADEMIC & ADMIN BUILDINGS ---
    Location(
      name: 'Technology Tower (TT) - Main Gate',
      category: 'Academic Block',
      description: 'Main entrance of Technology Tower.',
      coordinates: LatLng(12.9708685, 79.159466),
      buildingGroup: 'TT',
    ),
    Location(
      name: 'Technology Tower (TT) - West Gate',
      category: 'Academic Block',
      description: 'West entrance of Technology Tower.',
      coordinates: LatLng(12.9705235, 79.1589081),
      buildingGroup: 'TT',
    ),
    Location(
      name: 'Technology Tower (TT) - East Gate',
      category: 'Academic Block',
      description: 'East entrance of Technology Tower.',
      coordinates: LatLng(12.970696, 79.161098),
      buildingGroup: 'TT',
    ),
    Location(
      name: 'TT Fountain',
      category: 'Landmark',
      description: 'Fountain in front of Technology Tower.',
      coordinates: LatLng(12.9708999, 79.1594392),
    ),
    Location(
      name: 'SJT (Silver Jubilee Tower) - Front Gate',
      category: 'Academic Block',
      description: 'Silver Jubilee Tower (SJT) - Front Gate',
      coordinates: LatLng(12.9713076, 79.1636234),
      buildingGroup: 'SJT',
    ),
    Location(
      name: 'SJT (Silver Jubilee Tower) - Back Gate',
      category: 'Academic Block',
      description: 'Silver Jubilee Tower (SJT) - Back Gate',
      coordinates: LatLng(12.9705967, 79.1642404),
      buildingGroup: 'SJT',
    ),
    Location(
      name: 'Pearl Research Park - Front Gate',
      category: 'Academic Block',
      description: 'Pearl Research Park - Front Gate',
      coordinates: LatLng(12.9712658, 79.1663217),
      buildingGroup: 'PRP',
    ),
    Location(
      name: 'Pearl Research Park - Back Gate',
      category: 'Academic Block',
      description: 'Pearl Research Park - Back Gate',
      coordinates: LatLng(12.970696, 79.1661501),
      buildingGroup: 'PRP',
    ),
    Location(
      name: 'MGB (Mahatma Gandhi Block) - Gate',
      category: 'Academic Block',
      description: 'Mahatma Gandhi Block (MGB) Entrance',
      coordinates: LatLng(12.9720656, 79.1683871),
      buildingGroup: 'MGB',
    ),
    Location(
      name: 'Anna Auditorium',
      category: 'Auditorium',
      description: 'Anna Auditorium',
      coordinates: LatLng(12.9699563, 79.1554615),
    ),
    Location(
      name: 'VIT University Estates Office & CTS',
      category: 'Admin',
      description: 'Estates Office and CTS.',
      coordinates: LatLng(12.9702099, 79.1560784),
    ),
    Location(
      name: 'GD Naidu Block',
      category: 'Academic Block',
      description: 'GD Naidu Block',
      coordinates: LatLng(12.9696139, 79.154638),
    ),
    Location(
      name: 'CDMM Building',
      category: 'Academic Block',
      description: 'CDMM Building',
      coordinates: LatLng(12.9691225, 79.1552228),
    ),
    Location(
      name: 'Main Building (MGR) - North Gate',
      category: 'Admin',
      description: 'Main Administrative Building (MGR Block)',
      coordinates: LatLng(12.9695564, 79.1559309),
      buildingGroup: 'MGR',
    ),
    Location(
      name: 'Main Building (MGR) - South Gate',
      category: 'Admin',
      description: 'Main Administrative Building (MGR Block)',
      coordinates: LatLng(12.9688951, 79.1559228),
      buildingGroup: 'MGR',
    ),
    Location(
      name: 'EV Periyar Library',
      category: 'Admin',
      description: 'Main Central Library',
      coordinates: LatLng(12.9691251, 79.1568562),
    ),
    Location(
      name: 'SMV Block - North Gate',
      category: 'Academic Block',
      description: 'SMV Block',
      coordinates: LatLng(12.9696296, 79.157728),
      buildingGroup: 'SMV',
    ),
    Location(
      name: 'SMV Block - South Gate',
      category: 'Academic Block',
      description: 'SMV Block',
      coordinates: LatLng(12.9688585, 79.1577253),
      buildingGroup: 'SMV',
    ),
    Location(
      name: 'Centre for Biomechanical Research',
      category: 'Academic Block',
      description: 'Centre for Biomechanical Research',
      coordinates: LatLng(12.9683384, 79.1602036),
    ),
    // --- (Food & Shops - Academic Area) ---
    Location(
      name: 'Canteen (Near Gate 2)',
      category: 'Food Courts',
      description: 'Canteen near Gate 2.',
      coordinates: LatLng(12.9704712, 79.1544503),
    ),
    Location(
      name: 'Souvenir Shop',
      category: 'Shop/Café',
      description: 'VIT Souvenir Shop.',
      coordinates: LatLng(12.9704268, 79.1553274),
    ),
    Location(
      name: 'Woody\'s',
      category: 'Food Courts',
      description: 'Woody\'s Restaurant near SMV.',
      coordinates: LatLng(12.9698256, 79.1576689),
    ),
    Location(
      name: 'Amul Shop',
      category: 'Shop/Café',
      description: 'Amul Parlour.',
      coordinates: LatLng(12.9695486, 79.1580364),
    ),
    Location(
      name: 'Greenos',
      category: 'Food Courts',
      description: 'Greenos Restaurant.',
      coordinates: LatLng(12.9696401, 79.1582778),
    ),
    Location(
      name: 'Samsung Shop',
      category: 'Shop/Café',
      description: 'Samsung Store.',
      coordinates: LatLng(12.9693369, 79.1581437),
    ),
    Location(
      name: 'Foodys',
      category: 'Food Courts',
      description: 'Foodys Restaurant.',
      coordinates: LatLng(12.9690467, 79.1582215),
    ),
    Location(
      name: 'Lassi House (Near SJT)',
      category: 'Shop/Café',
      description: 'Lassi House near SJT.',
      coordinates: LatLng(12.9716683, 79.1644174),
    ),
    // --- (Services & Utilities) ---
    Location(
      name: 'Atm (near SJT)',
      category: 'Services',
      description: 'ATM located near SJT building.',
      coordinates: LatLng(12.9716161, 79.1631567),
    ),
    Location(
      name: 'Central Store',
      category: 'Services',
      description: 'Central Store.',
      coordinates: LatLng(12.9704451, 79.155027),
    ),
    Location(
      name: 'Health Centre',
      category: 'Services',
      description: 'Main Health Centre.',
      coordinates: LatLng(12.9695799, 79.1546434),
    ),
    Location(
      name: 'HDFC Bank',
      category: 'Services',
      description: 'HDFC Bank Branch.',
      coordinates: LatLng(12.9697472, 79.1552094),
    ),
    Location(
      name: 'Car Parking',
      category: 'Parking',
      description: 'Main car parking area.',
      coordinates: LatLng(12.9687226, 79.1552281),
    ),
    Location(
      name: 'VIT Guest House',
      category: 'Admin',
      description: 'VIT Guest House',
      coordinates: LatLng(12.9676274, 79.1587311),
    ),
    Location(
      name: 'Waste Water Plant (Academic Area)',
      category: 'Utilities',
      description: 'Waste Water Treatment Plant',
      coordinates: LatLng(12.9704869, 79.1620141),
    ),
    Location(
      name: 'Motorcycle Parking (Near SJT)',
      category: 'Parking',
      description: 'Motorcycle parking near SJT.',
      coordinates: LatLng(12.9712188, 79.1647875),
    ),
    // --- (Sports & Recreation - Academic Area) ---
    Location(
      name: 'Anna Auditorium Volleyball Court',
      category: 'Sports',
      description: 'Volleyball court near Anna Auditorium.',
      coordinates: LatLng(12.9702961, 79.1555715),
    ),
    Location(
      name: 'Anna Auditorium Basketball Court',
      category: 'Sports',
      description: 'Basketball court near Anna Auditorium.',
      coordinates: LatLng(12.970304, 79.1559389),
    ),
    Location(
      name: 'Anna Auditorium Tennis Court',
      category: 'Sports',
      description: 'Tennis court near Anna Auditorium.',
      coordinates: LatLng(12.9703066, 79.1561535),
    ),
    Location(
      name: 'Basketball Court (Near MGR)',
      category: 'Sports',
      description: 'Basketball court near Main Building.',
      coordinates: LatLng(12.9698779, 79.1561267),
    ),
    Location(
      name: 'Kalpana Chawla Ground',
      category: 'Sports',
      description: 'Kalpana Chawla Ground.',
      coordinates: LatLng(12.9684874, 79.1563681),
    ),
    Location(
      name: 'TT Basketball & Volleyball Court',
      category: 'Sports',
      description: 'Courts near Technology Tower.',
      coordinates: LatLng(12.9702203, 79.1585702),
    ),
    Location(
      name: 'VIT Lake',
      category: 'Landmark',
      description: 'Lake near the hostels.',
      coordinates: LatLng(12.9699642, 79.162116),
    ),
    Location(
      name: 'SJT Ground',
      category: 'Sports',
      description: 'Ground in front of SJT.',
      coordinates: LatLng(12.9704085, 79.1632372),
    ),
  ];

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationServiceEnabled = false;

  bool _isRerouting = false;
  static const double _rerouteThreshold = 30.0;

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

  // --- *** REMOVED: All LatLng conversion functions *** ---

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkAndStartLocationStream();

    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _searchController.addListener(_onSearchChanged);
    _sheetController.addListener(_onSheetMoved);
  }

  void _onSheetMoved() {
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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _sheetController.removeListener(_onSheetMoved);
    super.dispose();
  }

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

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearchActive = false;
      _searchResults = [];
    });
  }

  void _onSearchResultTapped(Location location) {
    _clearSearch();
    FocusManager.instance.primaryFocus?.unfocus();
    _setDestinationFromDirectory(location);
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

  void _animateRotationTo(double targetRotation) {
    final currentRotation = _mapController.camera.rotation;
    double normalize(double angle) {
      while (angle <= -180) angle += 360;
      while (angle > 180) angle -= 360;
      return angle;
    }

    final currentNormalized = normalize(currentRotation);
    final targetNormalized = normalize(targetRotation);
    double diff = targetNormalized - currentNormalized;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    final finalRotation = currentRotation + diff;
    final tween = Tween<double>(begin: currentRotation, end: finalRotation);
    final animation = tween.animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _rotationAnimationController.stop();
    animation.removeListener(() {});
    animation.addListener(() {
      if (mounted) {
        _mapController.rotate(animation.value);
      }
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeListener(() {});
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
      setState(() {});
    }
    if (!_isLocationServiceEnabled) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            if (!mounted) return;

            setState(() {
              _currentPosition = position;
            });

            debugPrint(
              "New Position: ${position.latitude}, ${position.longitude}, Heading: ${position.heading}",
            );

            if (_isRouting && _activeSteps.isNotEmpty) {
              // --- *** REFACTORED: Use latlong.LatLng directly *** ---
              final userLocation = LatLng(
                position.latitude,
                position.longitude,
              );

              int closestPointIndex = -1;
              double minDistance = double.infinity;
              if (_fullRouteCoordinates.isEmpty) return;

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
              if (closestPointIndex == -1) return;

              if (minDistance > _rerouteThreshold && !_isRerouting) {
                if (mounted) {
                  setState(() {
                    _isRerouting = true;
                    _remainingRouteCoordinates = [];
                  });
                }
                final bool routeFound = await _fetchRouteDetails(
                  _selectedProfile,
                );
                if (routeFound && mounted) {
                  setState(() {
                    final newRoute = _selectedProfile == 'walk'
                        ? _cachedWalkRoute
                        : _cachedBikeRoute;
                    final newSteps = _selectedProfile == 'walk'
                        ? _cachedWalkSteps
                        : _cachedBikeSteps;
                    _fullRouteCoordinates = newRoute;
                    _remainingRouteCoordinates = List.from(newRoute);
                    _activeSteps = newSteps;
                    _currentStepIndex = 0;
                    _isRerouting = false;
                  });
                  _speak(
                    "Rerouting. ${_activeSteps.isNotEmpty ? _activeSteps[0].instruction : ''}",
                  );
                } else if (mounted) {
                  setState(() {
                    _isRerouting = false;
                  });
                }
              } else if (!_isRerouting) {
                final List<LatLng> newRemainingPoints = _fullRouteCoordinates
                    .sublist(closestPointIndex);
                if (mounted) {
                  setState(() {
                    _remainingRouteCoordinates = newRemainingPoints;
                  });
                }

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

  // --- *** NETWORKING FIX: Route Summary Fetch *** ---
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

    // --- *** REFACTORED: Use latlong.LatLng directly *** ---
    final start = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final end = destination;

    // Select the correct base URL based on profile
    final String baseUrl = profile == 'walk'
        ? _osrmWalkBaseUrl
        : _osrmBikeBaseUrl;

    // Construct the full URL
    final url = Uri.parse(
      '$baseUrl/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=false&geometries=geojson',
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
      } else {
        debugPrint(
          'Route summary fetch failed for $profile with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Route summary fetch failed for $profile: $e');
    }
    return false;
  }

  // --- *** NETWORKING FIX: Route Details Fetch *** ---
  Future<bool> _fetchRouteDetails(String profile) async {
    final destination = _finalDestinationCoordinates;
    if (_currentPosition == null || destination == null) return false;

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

    // --- *** REFACTORED: Use latlong.LatLng directly *** ---
    final start = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final end = destination;

    // Select the correct base URL based on profile
    final String baseUrl = profile == 'walk'
        ? _osrmWalkBaseUrl
        : _osrmBikeBaseUrl;

    // Construct the full URL
    final url = Uri.parse(
      '$baseUrl/route/v1/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true',
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
              // --- *** REFACTORED: Use latlong.LatLng directly *** ---
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
                    // --- *** REFACTORED: Use latlong.LatLng directly *** ---
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
      } else {
        debugPrint(
          'Route details fetch failed for $profile with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Route details fetch failed for $profile: $e');
    }
    return false;
  }
  // --- *** END NETWORKING FIX *** ---

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours hr $remainingMinutes min';
  }

  void _resetNavigationState() {
    if (!mounted) return;
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
      _isFollowingUser = false;
      _isRerouting = false;
    });
    _flutterTts.stop();
    if (mounted && _mapController.camera.rotation != 0) {
      _animateRotationTo(0);
    }
    _sheetController.animateTo(
      0.2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _setDestinationFromDirectory(Location location) {
    if (!mounted) return;

    Location finalDestination = location;

    if (location.buildingGroup != null && _currentPosition != null) {
      final String groupName = location.buildingGroup!;
      // --- *** REFACTORED: Use latlong.LatLng directly *** ---
      final userLocation = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      final List<Location> groupLocations = _allLocations
          .where((loc) => loc.buildingGroup == groupName)
          .toList();

      if (groupLocations.isNotEmpty) {
        Location closestLocation = groupLocations[0];
        double minDistance = double.infinity;

        for (final loc in groupLocations) {
          final distance = Geolocator.distanceBetween(
            userLocation.latitude,
            userLocation.longitude,
            loc.coordinates.latitude,
            loc.coordinates.longitude,
          );
          if (distance < minDistance) {
            minDistance = distance;
            closestLocation = loc;
          }
        }
        debugPrint(
          "Found closest entry for group $groupName: ${closestLocation.name}",
        );
        finalDestination = closestLocation;
      }
    }

    setState(() {
      _selectedIndex = 0;
      _selectedLocation = finalDestination;
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
    if (!mounted) return;
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

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    // <-- This is now from latlong2
    if (!mounted) return;
    setState(() {
      _selectedLocation = null;
      // --- *** REFACTORED: Use latlong.LatLng directly *** ---
      _tappedDestination = point;
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
      setState(() {
        _isFollowingUser = false;
      });
      _animateRotationTo(0);
    } else {
      setState(() {
        _isFollowingUser = true;
      });
      if (_currentPosition != null) {
        // --- *** REFACTORED: Use latlong.LatLng directly *** ---
        _mapController.move(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          18.0,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fetching your location...')),
        );
        _checkAndStartLocationStream();
      }
    }
  }

  Future<void> _startNavigation({
    required String profile,
    required List<LatLng> route, // This is now List<latlong.LatLng>
    required List<RouteStep> steps,
  }) async {
    if (!mounted) return;
    _clearSearch();
    await _sheetController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (!mounted) return;

    setState(() {
      _selectedProfile = profile;
      _fullRouteCoordinates = route;
      _remainingRouteCoordinates = List.from(route);
      _activeSteps = steps;
      _currentStepIndex = 0;
      _isRouting = true;
      _isFollowingUser = true;
      _isRerouting = false;
    });

    if (_currentPosition != null) {
      // --- *** REFACTORED: Use latlong.LatLng directly *** ---
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        18.0,
      );
    } else {
      // --- *** REFACTORED: No conversion needed *** ---
      final flutterMapPoints = route;
      if (flutterMapPoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(flutterMapPoints);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
        );
      }
    }
    if (steps.isNotEmpty) {
      _speak(steps[0].instruction);
    }
  }

  void _showDirectionsSheet() {
    if (!mounted) return;
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomPadding = mediaQuery.padding.bottom;
    final double searchBarHeight = mediaQuery.padding.top + 80.0;
    const double sheetStartMove = 0.2;
    const double sheetEndMove = 0.4;
    double dragProgress =
        (_sheetPosition - sheetStartMove) / (sheetEndMove - sheetStartMove);
    dragProgress = dragProgress.clamp(0.0, 1.0);
    final double searchBarTopOffset = -searchBarHeight * dragProgress;
    final double searchBarOpacity = _isRouting ? 0.0 : (1.0 - dragProgress);
    final bool isSheetLow = _sheetPosition < 0.25;
    final double gpsButtonOpacity = (_isRouting || !isSheetLow) ? 0.0 : 1.0;
    final double navCardHeight = 200.0 + bottomPadding;
    final double recentreButtonBottomOffset = navCardHeight + 16.0;

    // --- *** REFACTORED: Use latlong.LatLng directly *** ---
    final campusCenter = LatLng(12.970856, 79.159515);

    final List<Marker> locationMarkers = [];
    if (_finalDestinationCoordinates != null && !_isRouting) {
      // --- *** REFACTORED: Use latlong.LatLng directly *** ---
      locationMarkers.add(
        Marker(
          point: _finalDestinationCoordinates!,
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
      // --- *** REFACTORED: Use latlong.LatLng directly *** ---
      routePolylines.add(
        Polyline(
          points: _remainingRouteCoordinates,
          strokeWidth: 5.0,
          color: Colors.deepPurple,
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
                maxZoom: 19.0, // Set back to 19
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                  enableMultiFingerGestureRace: true,
                ),
                // --- *** REFACTORED: Use latlong.LatLng directly *** ---
                onLongPress: (tapPosition, point) =>
                    _onMapLongPress(tapPosition, point),
                onPointerDown: (details, point) {
                  if (_isFollowingUser && details.buttons == kPrimaryButton) {
                    if (mounted) setState(() => _isFollowingUser = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  // --- *** NIGHT MODE REMOVED *** ---
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vit_navigation_app',
                  maxZoom: 19.0,
                  // --- *** PERFORMANCE FIX: Use _tileProvider variable *** ---
                  tileProvider: _tileProvider,
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
          Transform.translate(
            offset: Offset(0, searchBarTopOffset),
            child: AnimatedOpacity(
              opacity: searchBarOpacity,
              duration: const Duration(milliseconds: 100),
              child: IgnorePointer(
                ignoring: _isRouting || dragProgress > 0.0,
                child: Stack(
                  children: [
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

          // --- *** NIGHT MODE REMOVED *** ---
          if (_isRouting && !_isFollowingUser)
            Positioned(
              bottom: recentreButtonBottomOffset + 10,
              right: 16.0,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                color: Colors.blueAccent,
                child: InkWell(
                  onTap: _centerMapOnUser,
                  borderRadius: BorderRadius.circular(30),
                  child: const Padding(
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
          AnimatedSlide(
            offset: _isRouting ? const Offset(0, 1) : const Offset(0, 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.2,
              minChildSize: 0.2,
              maxChildSize: 0.95,
              expand: true,
              builder:
                  (BuildContext context, ScrollController scrollController) {
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
                                                borderRadius:
                                                    BorderRadius.circular(10),
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
                                                  MainAxisAlignment
                                                      .spaceBetween,
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
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        '24°',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[700],
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
                                    const Divider(height: 1),
                                    Container(
                                      padding: const EdgeInsets.only(
                                        top: 16.0,
                                        bottom: 0.0,
                                      ),
                                      child: _buildCurrentContent(
                                        _selectedIndex,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _isRouting ? const Offset(0, 2) : const Offset(0, 0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: _isRouting,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: bottomPadding + 20.0,
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
      if (!groupedLocations.containsKey(loc.category))
        groupedLocations[loc.category] = [];
      groupedLocations[loc.category]!.add(loc);
    }

    final sortedKeys = groupedLocations.keys.toList()
      ..sort((a, b) {
        if (a.contains('Hostel') && !b.contains('Hostel')) return -1;
        if (!a.contains('Hostel') && b.contains('Hostel')) return 1;
        if (a.contains('Academic') && !b.contains('Academic')) return -1;
        if (!a.contains('Academic') && b.contains('Academic')) return 1;
        return a.compareTo(b);
      });

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
          ...sortedKeys.map((key) {
            final entry = groupedLocations[key]!;
            entry.sort((a, b) => a.name.compareTo(b.name));
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  const Divider(),
                  ...entry.map((location) {
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
  CachedTileProvider();
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(getTileUrl(coordinates, options));
  }
}
