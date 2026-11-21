import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/stock/daily_brief_weather_service.dart';

void main() {
  test('weather explanation includes local condition and forecast context', () {
    const weather = DailyBriefWeather(
      temperatureC: 28,
      feelsLikeC: 30,
      maxTemperatureC: 32,
      precipitationChance: 60,
      weatherCode: 61,
    );

    final explanation = weather.explanation('sw');
    expect(explanation, contains('Hali ya sasa katika eneo lako: Mvua.'));
    expect(explanation, contains('Joto ni 28°C (linahisiwa 30°C)'));
    expect(explanation, contains('Uwezekano wa mvua leo ni 60%'));
    expect(
      weather.practicalTips('sw'),
      contains('Beba mwamvuli au koti la mvua na panga safari mapema.'),
    );
    expect(
      weather.practicalTips('sw'),
      contains('Hakikisha unakunywa maji ya kutosha.'),
    );
  });

  test('weather actions cover storms, fog, and calm conditions', () {
    const storm = DailyBriefWeather(
      temperatureC: 24,
      feelsLikeC: 24,
      maxTemperatureC: 28,
      precipitationChance: 80,
      weatherCode: 95,
    );
    const fog = DailyBriefWeather(
      temperatureC: 18,
      feelsLikeC: 18,
      maxTemperatureC: 18,
      precipitationChance: 10,
      weatherCode: 45,
    );
    const calm = DailyBriefWeather(
      temperatureC: 24,
      feelsLikeC: 24,
      maxTemperatureC: 28,
      precipitationChance: 10,
      weatherCode: 0,
    );

    expect(storm.practicalTips('sw').first, contains('Epuka maeneo ya wazi'));
    expect(fog.practicalTips('sw').first, contains('punguza mwendo'));
    expect(calm.practicalTips('sw').first, contains('Hali ni tulivu'));
  });
}
