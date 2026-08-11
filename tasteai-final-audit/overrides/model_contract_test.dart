import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_ai_mobile/models/ai_status.dart';
import 'package:restaurant_ai_mobile/models/place.dart';

void main() {
  test('Place parses ranked backend contract', () {
    final place = Place.fromJson({
      'id': 'p1',
      'name': 'Test Cafe',
      'address': 'London',
      'lat': 51.5074,
      'lng': -0.1278,
      'rating': 4.6,
      'review_count': 120,
      'price_level': 2,
      'distance_km': 1.25,
      'distance_known': true,
      'ai_score': 1.234,
      'ai_mode': 'trained_lightgbm_huber',
      'ai_rank': 1,
      'ai_reasons': ['Matches coffee preference'],
      'types': ['coffee_shop'],
      'source': 'google',
    });

    expect(place.id, 'p1');
    expect(place.aiRank, 1);
    expect(place.aiMode, 'trained_lightgbm_huber');
    expect(place.aiReasons, contains('Matches coffee preference'));
    expect(place.distanceKnown, isTrue);
  });

  test('AI status parses strict production readiness', () {
    final status = AiStatus.fromJson({
      'ready': true,
      'require_trained_ai': true,
      'recommender': {
        'loaded': true,
        'required': true,
        'mode': 'trained_lightgbm_huber',
        'model_class': 'LGBMRegressor',
        'metrics': {'ndcg@5': 0.71},
      },
      'review_ai': {
        'loaded': true,
        'required': true,
        'mode': 'trained_tfidf_sentiment_hybrid',
        'model_class': 'Pipeline',
        'device': 'cpu',
        'metrics': {'accuracy': 0.825, 'f1': 0.8223},
      },
    });

    expect(status.ready, isTrue);
    expect(status.requireTrainedAi, isTrue);
    expect(status.recommender.loaded, isTrue);
    expect(status.reviewAi.loaded, isTrue);
    expect(status.reviewAi.requiredArtifact, isTrue);
  });
}
