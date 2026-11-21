import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class DailyBriefWeatherException implements Exception {
  const DailyBriefWeatherException(this.code);

  final String code;
}

class DailyBriefWeather {
  const DailyBriefWeather({
    required this.temperatureC,
    required this.maxTemperatureC,
    required this.feelsLikeC,
    required this.precipitationChance,
    required this.weatherCode,
  });

  final double temperatureC;
  final double maxTemperatureC;
  final double feelsLikeC;
  final int? precipitationChance;
  final int weatherCode;

  Map<String, dynamic> toBriefMap() => {
    'temperatureC': temperatureC,
    'maxTemperatureC': maxTemperatureC,
    'feelsLikeC': feelsLikeC,
    'precipitationChance': precipitationChance,
    'weatherCode': weatherCode,
  };

  String conditionLabel(String languageCode) {
    final sw = languageCode == 'sw';
    if (weatherCode == 0) return sw ? 'Jua' : 'Clear';
    if (weatherCode == 1) return sw ? 'Hali ya jua kiasi' : 'Mostly clear';
    if (weatherCode == 2) return sw ? 'Mawingu kiasi' : 'Partly cloudy';
    if (weatherCode == 3) return sw ? 'Kuna mawingu' : 'Overcast';
    if (weatherCode == 45 || weatherCode == 48) {
      return sw ? 'Ukungu' : 'Fog';
    }
    if ((weatherCode >= 51 && weatherCode <= 67) ||
        (weatherCode >= 80 && weatherCode <= 82)) {
      return sw ? 'Mvua' : 'Rain';
    }
    if (weatherCode >= 71 && weatherCode <= 77 ||
        weatherCode == 85 ||
        weatherCode == 86) {
      return sw ? 'Theluji' : 'Snow';
    }
    if (weatherCode >= 95) {
      return sw ? 'Mvua ya radi' : 'Thunderstorm';
    }
    return sw ? 'Hali ya hewa ya leo' : "Today's weather";
  }

  String explanation(String languageCode) {
    final sw = languageCode == 'sw';
    final rainChance = precipitationChance == null
        ? ''
        : sw
        ? ' Uwezekano wa mvua leo ni $precipitationChance%.'
        : " Today's rain chance is $precipitationChance%.";
    if (sw) {
      return 'Hali ya sasa katika eneo lako: ${conditionLabel(languageCode)}. '
          'Joto ni ${temperatureC.round()}°C (linahisiwa ${feelsLikeC.round()}°C) '
          'na linaweza kufika ${maxTemperatureC.round()}°C leo.$rainChance';
    }
    return 'Current local conditions: ${conditionLabel(languageCode)}. '
        'It is ${temperatureC.round()}°C (feels like ${feelsLikeC.round()}°C) '
        'and may reach ${maxTemperatureC.round()}°C today.$rainChance';
  }

  List<String> practicalTips(String languageCode) {
    final tips = <String>[];
    final sw = languageCode == 'sw';
    final rainLikely = (precipitationChance ?? 0) >= 50 ||
        (weatherCode >= 51 && weatherCode <= 67) ||
        (weatherCode >= 80 && weatherCode <= 82);
    if (weatherCode >= 95) {
      tips.add(
        sw
            ? 'Epuka maeneo ya wazi na sitisha shughuli za nje wakati wa radi.'
            : 'Avoid exposed areas and pause outdoor activities during storms.',
      );
    } else if (weatherCode == 45 || weatherCode == 48) {
      tips.add(
        sw
            ? 'Safiri kwa tahadhari na punguza mwendo kwa sababu ya ukungu.'
            : 'Travel carefully and slow down because of fog.',
      );
    } else if ((weatherCode >= 71 && weatherCode <= 77) ||
        weatherCode == 85 ||
        weatherCode == 86) {
      tips.add(
        sw
            ? 'Vaa nguo za joto na uwe mwangalifu kwenye njia zenye utelezi.'
            : 'Wear warm clothing and be careful on slippery routes.',
      );
    } else if (rainLikely) {
      tips.add(
        sw
            ? 'Beba mwamvuli au koti la mvua na panga safari mapema.'
            : 'Carry an umbrella or raincoat and allow extra travel time.',
      );
    } else if ((precipitationChance ?? 0) >= 30) {
      tips.add(
        sw
            ? 'Angalia utabiri tena kabla ya safari; mvua inaweza kunyesha.'
            : 'Check the forecast before travelling; rain is possible.',
      );
    } else {
      tips.add(
        sw
            ? 'Hali ni tulivu kwa sasa; panga shughuli zako na fuatilia mabadiliko.'
            : 'Conditions are calm now; plan your activities and watch for updates.',
      );
    }
    if (maxTemperatureC >= 30) {
      tips.add(
        sw
            ? 'Hakikisha unakunywa maji ya kutosha.'
            : 'Remember to drink enough water.',
      );
    } else if (maxTemperatureC <= 18) {
      tips.add(sw ? 'Vaa nguo za joto.' : 'Wear warm clothing.');
    }
    return tips;
  }
}

class DailyBriefWeatherService {
  DailyBriefWeatherService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<DailyBriefWeather> fetch() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DailyBriefWeatherException('location_services_off');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw DailyBriefWeatherException(
        permission == LocationPermission.deniedForever
            ? 'location_permission_settings'
            : 'location_permission_denied',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final latitude = double.parse(position.latitude.toStringAsFixed(2));
    final longitude = double.parse(position.longitude.toStringAsFixed(2));
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,apparent_temperature,weather_code',
      'daily':
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code',
      'forecast_days': '1',
      'timezone': 'auto',
    });

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (error) {
      throw DailyBriefWeatherException('weather_network_error: $error');
    }
    if (response.statusCode != 200) {
      throw DailyBriefWeatherException(
        'weather_http_error:${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const DailyBriefWeatherException('weather_invalid_response');
    }
    final current = data['current'];
    final daily = data['daily'];
    if (current is! Map || daily is! Map) {
      throw const DailyBriefWeatherException('weather_invalid_response');
    }
    final temperature = current['temperature_2m'];
    final feelsLike = current['apparent_temperature'];
    final weatherCode = current['weather_code'];
    final maxima = daily['temperature_2m_max'];
    final maximum =
        maxima is List && maxima.isNotEmpty ? maxima.first : null;
    final chances = daily['precipitation_probability_max'];
    final chance = chances is List && chances.isNotEmpty ? chances.first : null;
    if (temperature is! num ||
        feelsLike is! num ||
        weatherCode is! num ||
        maximum is! num ||
        (chance != null && chance is! num)) {
      throw const DailyBriefWeatherException('weather_invalid_response');
    }
    return DailyBriefWeather(
      temperatureC: temperature.toDouble(),
      maxTemperatureC: maximum.toDouble(),
      feelsLikeC: feelsLike.toDouble(),
      precipitationChance: (chance as num?)?.round(),
      weatherCode: weatherCode.toInt(),
    );
  }
}
