class WeatherDisplayData {
  final double temperature;
  final int weatherCode;
  final String cityName;

  WeatherDisplayData({
    required this.temperature,
    required this.weatherCode,
    required this.cityName,
  });

  // Helper method to convert the OpenMeteo weather code into a readable description.
  String get weatherDescription {
    switch (weatherCode) {
      case 0:
        return 'Clear Sky';
      case 1:
      case 2:
      case 3:
        return 'Mainly Clear to Overcast';
      case 45:
      case 48:
        return 'Fog and Rime Fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 71:
      case 73:
      case 75:
        return 'Snow Fall';
      case 80:
      case 81:
      case 82:
        return 'Rain Showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Weather Code $weatherCode';
    }
  }

  // Helper method to get an appropriate icon (using Unicode emojis for simplicity)
  String get weatherIcon {
    // Only includes basic codes for demonstration
    if (weatherCode >= 0 && weatherCode <= 3) return '☀️'; // Clear to Overcast
    if (weatherCode >= 45 && weatherCode <= 48) return '🌫️'; // Fog
    if (weatherCode >= 51 && weatherCode <= 65) return '🌧️'; // Drizzle/Rain
    if (weatherCode >= 71 && weatherCode <= 75) return '❄️'; // Snow
    if (weatherCode >= 80 && weatherCode <= 82) return ' showers'; // Showers
    if (weatherCode >= 95) return '⛈️'; // Thunderstorm
    return '❓';
  }
}
