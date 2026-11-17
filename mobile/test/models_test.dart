import 'package:flutter_test/flutter_test.dart';
import 'package:ouaga_assainissement/core/models.dart';

void main() {
  test('Dump.fromFeature lit une entité GeoJSON de l’API', () {
    final d = Dump.fromFeature({
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [-1.5197, 12.3714]},
      'properties': {
        'id': 'abc',
        'status': 'verified',
        'size': 'large',
        'waste_type': 'rubble',
        'est_kg': 1500,
        'confidence': 0.97,
        'reporter_count': 3,
        'priority_score': 71.4,
        'priority_level': 'high',
        'main_driver': 'water',
        'recurrence': true,
        'first_reported_at': '2026-11-01T08:00:00.000Z',
      },
    });
    expect(d.pos.latitude, closeTo(12.3714, 1e-9));
    expect(d.pos.longitude, closeTo(-1.5197, 1e-9));
    expect(d.sizeLevel, 2);
    expect(d.recurrence, true);
    expect(d.priority, closeTo(71.4, 1e-9));
  });
}
