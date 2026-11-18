import 'package:flutter_test/flutter_test.dart';
import 'package:ouagaclean/core/models.dart';

void main() {
  test('formats de poids', () {
    expect(fmtKg(50), '50 kg');
    expect(fmtKg(1500), '1.5 t');
  });

  test('formats de durée et de date', () {
    expect(fmtHours(30), '30 h');
    expect(fmtHours(72), '3 j');
    expect(fmtHours(null), '—');
    expect(fmtDate('2026-11-18T10:00:00Z'), '18/11/2026');
  });

  test('lecture d’un dépotoir GeoJSON', () {
    final d = Dump.fromFeature({
      'geometry': {
        'coordinates': [-1.5197, 12.3714],
      },
      'properties': {
        'id': 'abc',
        'status': 'verified',
        'size': 'large',
        'est_kg': 1500,
        'priority_score': 71.4,
      },
    });
    expect(d.lat, 12.3714);
    expect(d.lon, -1.5197);
    expect(d.status, 'verified');
    expect(d.kg, 1500);
    expect(d.priority, closeTo(71.4, 0.01));
  });

  test('libellés des motifs de rejet couvrent l’API', () {
    for (final k in ['batiment', 'route', 'eau', 'vegetation', 'rien_vu', 'deja_signale', 'autre']) {
      expect(rejectReasonLabels.containsKey(k), isTrue);
    }
  });
}
