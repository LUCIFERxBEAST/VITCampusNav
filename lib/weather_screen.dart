import 'package:flutter/material.dart';
// Import your service and data model
import 'weather_service.dart';
import 'weather_data.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final WeatherService _weatherService = WeatherService();

  WeatherDisplayData? _weatherData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  // --- Main Method to Call the Service ---
  void _fetchWeather() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Call your robust weather service
      final data = await _weatherService.fetchWeatherByLocation();
      setState(() {
        _weatherData = data;
        _isLoading = false;
      });
    } catch (e) {
      // Handle any exception thrown by the service (permissions, geocoding, API error)
      setState(() {
        _error = e.toString().replaceAll(
          'Exception: ',
          '',
        ); // Clean up error message
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Weather'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchWeather, // Allows manual refresh
          ),
        ],
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Getting location and weather...'),
        ],
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Failed to load weather:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchWeather,
              icon: const Icon(Icons.cached),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    // Display the weather data
    if (_weatherData != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _weatherData!.cityName,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            '${_weatherData!.temperature.toStringAsFixed(1)}°C',
            style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(_weatherData!.weatherIcon, style: const TextStyle(fontSize: 60)),
          const SizedBox(height: 10),
          Text(
            _weatherData!.weatherDescription,
            style: const TextStyle(fontSize: 24, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    // Should theoretically not be reached
    return const Text('No weather data available.');
  }
}
