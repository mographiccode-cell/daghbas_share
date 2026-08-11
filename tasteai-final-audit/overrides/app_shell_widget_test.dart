import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:restaurant_ai_mobile/app_locale.dart';
import 'package:restaurant_ai_mobile/models/ai_status.dart';
import 'package:restaurant_ai_mobile/models/place.dart';
import 'package:restaurant_ai_mobile/screens/app_shell_screen.dart';
import 'package:restaurant_ai_mobile/services/api_service.dart';

class FakeTasteAiApi extends ApiService {
  int nearbyCalls = 0;
  int discoverCalls = 0;

  static const _status = AiStatus(
    ready: true,
    coreReady: true,
    enhancedReady: true,
    requireTrainedAi: true,
    requireTrainedReviewAi: true,
    recommender: AiComponentStatus(
      loaded: true,
      mode: 'trained_lightgbm_huber',
      modelClass: 'LGBMRegressor',
      requiredArtifact: true,
      metrics: {},
    ),
    reviewAi: AiComponentStatus(
      loaded: true,
      mode: 'trained_tfidf_sentiment_hybrid',
      modelClass: 'Pipeline',
      device: 'cpu',
      requiredArtifact: true,
      metrics: {},
    ),
  );

  static const _places = [
    Place(
      id: 'p1',
      name: 'Harbor Cafe',
      address: 'London',
      lat: 51.5074,
      lng: -0.1278,
      rating: 4.8,
      reviewCount: 820,
      priceLevel: 2,
      distanceKm: 0,
      distanceKnown: false,
      aiScore: 1.2,
      aiRank: 1,
      aiMode: 'trained_lightgbm_huber',
      aiReasons: ['category_preference'],
      types: ['cafe'],
      source: 'google',
      featured: false,
    ),
    Place(
      id: 'p2',
      name: 'Garden Kitchen',
      address: 'London',
      lat: 51.509,
      lng: -0.12,
      rating: 4.6,
      reviewCount: 610,
      priceLevel: 3,
      distanceKm: 0,
      distanceKnown: false,
      aiScore: 1.0,
      aiRank: 2,
      aiMode: 'trained_lightgbm_huber',
      aiReasons: ['high_rating'],
      types: ['restaurant'],
      source: 'google',
      featured: false,
    ),
  ];

  @override
  Future<Map<String, dynamic>> health() async => {
        'status': 'ok',
        'data_source': 'google',
        'live_places_ready': true,
      };

  @override
  Future<AiStatus> aiStatus() async => _status;

  @override
  Future<List<Place>> nearby(double lat, double lng, {int radius = 5000, String languageCode = 'en'}) async {
    nearbyCalls++;
    return _places;
  }

  @override
  Future<List<Place>> discover({
    required String country,
    required String city,
    required String area,
    String query = '',
    double? lat,
    double? lng,
    String languageCode = 'en',
  }) async {
    discoverCalls++;
    return _places;
  }
}

void main() {
  setUp(() {
    appLocale.value = const Locale('en');
  });

  testWidgets('shell starts without silently requesting nearby places and exposes complete filters', (tester) async {
    final api = FakeTasteAiApi();
    await tester.pumpWidget(MaterialApp(home: AppShellScreen(api: api, onLogout: () {})));
    await tester.pumpAndSettle();

    expect(api.nearbyCalls, 0);
    expect(find.text('Start with a location'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Minimum review count'), findsOneWidget);
    expect(find.text('Price range'), findsOneWidget);
    expect(find.textContaining('Distance filtering requires current location'), findsOneWidget);
  });

  testWidgets('manual worldwide location search populates top-rated and personalized results', (tester) async {
    final api = FakeTasteAiApi();
    await tester.pumpWidget(MaterialApp(home: AppShellScreen(api: api, onLogout: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose location').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Country'), 'United Kingdom');
    await tester.enterText(find.widgetWithText(TextField, 'City'), 'London');
    await tester.tap(find.text('Explore this location'));
    await tester.pumpAndSettle();

    expect(api.discoverCalls, 1);
    expect(find.text('United Kingdom, London'), findsOneWidget);
    expect(find.text('Top rated'), findsOneWidget);
    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Harbor Cafe'), findsWidgets);
    expect(find.text('Garden Kitchen'), findsWidgets);
    expect(find.text('See all'), findsOneWidget);
  });
}
