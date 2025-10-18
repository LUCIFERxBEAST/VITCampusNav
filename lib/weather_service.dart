import 'package:geolocator/geolocator.dart';
import 'package:open_meteo/open_meteo.dart';
import 'package:geocoding/geocoding.dart';
import 'weather_data.dart'; // Ensure this file exists with the WeatherDisplayData class

class WeatherService {
  // Initialize the API client once
  final WeatherApi _weatherApi = WeatherApi(
    userAgent: 'Custom-Flutter-Weather-App',
    temperatureUnit: TemperatureUnit.celsius,
  );

  // --- Location Logic ---
  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied. Please enable in settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );
  }

  // --- Geocoding Logic ---
  Future<String> _getCityName(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final placemark = placemarks.first;

      String cityName =
          placemark.locality ??
          placemark.subAdministrativeArea ??
          placemark.administrativeArea ??
          'Unknown Location';

      return cityName;
    } catch (e) {
      print('Geocoding error: $e');
      return 'Unknown Location';
    }
  }

  // --- Weather Fetching ---
  Future<WeatherDisplayData> fetchWeatherByLocation() async {
    try {
      final position = await _getCurrentLocation();
      final cityName = await _getCityName(position);

      final apiResponse = await _weatherApi.request(
        current: {WeatherCurrent.temperature_2m, WeatherCurrent.weather_code},
        locations: {
          OpenMeteoLocation(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        },
      );

      // Inspect at runtime to discover the actual shape
      print('apiResponse runtimeType: ${apiResponse.runtimeType}');
      print('apiResponse: $apiResponse');

      // Use dynamic to avoid compile-time getter errors while probing
      final dynamic resp = apiResponse;

      // Try common candidate fields — adjust after you inspect the printed output
      final dynamic currentData =
          resp.current ??
          resp.currentWeather ??
          resp.current_weather ??
          resp.data?.current ??
          resp.data?.current_weather ??
          resp.value?.current ??
          resp.value?.current_weather ??
          (resp is Map ? resp['current'] ?? resp['current_weather'] : null);

      if (currentData == null) {
        throw Exception('API returned no current weather data.');
      }

      final currentTemp = currentData[WeatherCurrent.temperature_2m] as double?;
      final weatherCode = currentData[WeatherCurrent.weather_code] as int?;

      if (currentTemp == null || weatherCode == null) {
        throw Exception('Missing temperature or weather code in API response.');
      }

      return WeatherDisplayData(
        temperature: currentTemp,
        weatherCode: weatherCode,
        cityName: cityName,
      );
    } catch (e) {
      throw Exception('Error fetching weather or location: ${e.toString()}');
    }
  }
}
