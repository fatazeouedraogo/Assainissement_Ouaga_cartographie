import 'package:flutter_test/flutter_test.dart';
import 'package:ouagaclean/core/analytics.dart';

void main() {
  test('séries en colonnes avec bande', () {
    final d = parseSimSeries({
      'days': [0, 1, 2],
      'stock': {
        'mean': [3, 2, 1],
        'p10': [2, 1, 0],
        'p90': [4, 3, 2],
      },
    })!;
    expect(d.series.single.hasBand, isTrue);
    expect(d.days.last, 2);
  });

  test('séries en lignes', () {
    final d = parseSimSeries([
      {'day': 0, 'stock': 5},
      {'day': 1, 'stock': 4},
    ])!;
    expect(d.series.single.mean, [5, 4]);
  });

  test('série absente', () {
    expect(parseSimSeries(null), isNull);
  });

  test('scénarios A et B', () {
    final r = parseScenarios({
      'scenarios': [
        {'name': 'A', 'plan': {'metrics': {'coverage': 0.6, 'cost_per_month': 100}}},
        {'name': 'B', 'plan': {'metrics': {'coverage': 0.7, 'cost_per_month': 120}}},
      ],
    });
    expect(r.length, 2);
    expect(r[1].metrics['coverage'], 0.7);
  });

  test('pré-collecteurs', () {
    final r = parsePrecollectors({
      'precollectors': [
        {'name': 'Zone 1', 'stops': 4, 'kg': 120.5},
      ],
    });
    expect(r.single.title, 'Zone 1');
    expect(r.single.fields.length, 2);
  });
}
