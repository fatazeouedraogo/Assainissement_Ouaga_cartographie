import 'package:flutter/material.dart';

/// Tout ce qui lit les réponses de l'API pour les courbes, la comparaison
/// de scénarios et les pré-collecteurs. Si le serveur change de format,
/// c'est ce fichier (et lui seul) qu'il faut ajuster.

class PlanEvent {
  const PlanEvent(this.label, this.icon, this.value);
  final String label;
  final IconData icon;
  final double? value;
}

const planEvents = {
  'rain_season': PlanEvent('Saison des pluies', Icons.water_drop_outlined, null),
  'truck_breakdown': PlanEvent('Camion en panne', Icons.car_crash_outlined, 1),
  'more_trucks': PlanEvent('Camion en plus', Icons.add_road, 1),
  'budget_cut': PlanEvent('Budget −20 %', Icons.savings_outlined, 0.2),
  'subscription_drop': PlanEvent('Abonnements −20 %', Icons.trending_down, 0.2),
};

num numOut(double v) => v == v.roundToDouble() ? v.round() : double.parse(v.toStringAsFixed(4));

Map<String, dynamic> scenarioBody(
  List<Map<String, dynamic>> controls,
  Map<String, double> vals,
  Set<String> events,
) => {
  'params': {
    for (final c in controls)
      if (vals[c['key']] != null) c['key'] as String: numOut(vals[c['key']]!),
  },
  'events': [
    for (final k in events)
      {'kind': k, if (planEvents[k]?.value != null) 'value': planEvents[k]!.value},
  ],
};

String fmtInt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

String prettyKey(String k) {
  final t = k.replaceAll('_', ' ').trim();
  return t.isEmpty ? k : t[0].toUpperCase() + t.substring(1);
}

num? statOf(dynamic v) {
  if (v is num) return v;
  if (v is Map && v['mean'] is num) return v['mean'] as num;
  return null;
}

List<double>? _nums(dynamic v) {
  if (v is List && v.isNotEmpty && v.every((e) => e is num)) {
    return [for (final e in v) (e as num).toDouble()];
  }
  return null;
}

dynamic _first(Map m, List<String> keys) {
  for (final k in keys) {
    if (m[k] != null) return m[k];
  }
  return null;
}

// ---------------------------------------------------------------- Courbes

class SimSeries {
  SimSeries(this.key, this.mean, this.lo, this.hi);
  final String key;
  final List<double> mean;
  final List<double>? lo;
  final List<double>? hi;
  String get label => prettyKey(key);
  bool get hasBand => lo != null && hi != null;
}

class SimData {
  SimData(this.days, this.series);
  final List<double> days;
  final List<SimSeries> series;
}

const _dayKeys = ['days', 'day', 'jours', 'jour', 't', 'x', 'time'];
const _meanKeys = ['mean', 'median', 'p50', 'values', 'value'];
const _loKeys = ['lo', 'low', 'lower', 'p10', 'p05', 'p5', 'ci_low', 'min'];
const _hiKeys = ['hi', 'high', 'upper', 'p90', 'p95', 'ci_high', 'max'];

SimSeries? _oneSeries(String key, dynamic v) {
  final plain = _nums(v);
  if (plain != null) return SimSeries(key, plain, null, null);
  if (v is Map) {
    final mean = _nums(_first(v, _meanKeys));
    if (mean == null) return null;
    var lo = _nums(_first(v, _loKeys));
    var hi = _nums(_first(v, _hiKeys));
    if (lo?.length != mean.length || hi?.length != mean.length) {
      lo = null;
      hi = null;
    }
    return SimSeries(key, mean, lo, hi);
  }
  return null;
}

/// Lit `simulation.series`, que le serveur le renvoie en colonnes
/// ({métrique: {mean, p10, p90}}) ou en lignes (un objet par jour).
SimData? parseSimSeries(dynamic raw) {
  if (raw is Map) {
    List<double>? days;
    for (final k in _dayKeys) {
      days ??= _nums(raw[k]);
    }
    final out = <SimSeries>[];
    for (final e in raw.entries) {
      if (_dayKeys.contains(e.key)) continue;
      final s = _oneSeries(e.key.toString(), e.value);
      if (s != null) out.add(s);
    }
    if (out.isEmpty) return null;
    final n = out.first.mean.length;
    return SimData(
      days != null && days.length == n ? days : [for (var i = 0; i < n; i++) i.toDouble()],
      out,
    );
  }
  if (raw is List && raw.isNotEmpty && raw.every((e) => e is Map)) {
    final rows = raw.cast<Map>();
    final keys = <String>{for (final r in rows) ...r.keys.map((e) => e.toString())};
    final dayKey = _dayKeys.firstWhere(keys.contains, orElse: () => '');
    final out = <SimSeries>[];
    for (final k in keys) {
      if (k == dayKey) continue;
      final mean = <double>[];
      final lo = <double>[];
      final hi = <double>[];
      var bands = true;
      for (final r in rows) {
        final v = r[k];
        if (v is num) {
          mean.add(v.toDouble());
          bands = false;
        } else if (v is Map && _first(v, _meanKeys) is num) {
          mean.add((_first(v, _meanKeys) as num).toDouble());
          final l = _first(v, _loKeys);
          final h = _first(v, _hiKeys);
          if (l is num && h is num) {
            lo.add(l.toDouble());
            hi.add(h.toDouble());
          } else {
            bands = false;
          }
        } else {
          mean.clear();
          break;
        }
      }
      if (mean.length == rows.length) {
        out.add(SimSeries(k, mean, bands ? lo : null, bands ? hi : null));
      }
    }
    if (out.isEmpty) return null;
    final days = dayKey.isEmpty
        ? [for (var i = 0; i < rows.length; i++) i.toDouble()]
        : [for (final r in rows) ((r[dayKey] as num?) ?? 0).toDouble()];
    return SimData(days, out);
  }
  return null;
}

// ---------------------------------------------------------------- Indicateurs

class MetricDef {
  const MetricDef(this.label, this.unit, {this.scale = 1, this.digits = 0, this.higherIsBetter = true});
  final String label;
  final String unit;
  final double scale;
  final int digits;
  final bool higherIsBetter;

  String format(num v) {
    final x = v * scale;
    final t = digits == 0 ? fmtInt(x) : x.toStringAsFixed(digits);
    return unit.isEmpty ? t : '$t $unit';
  }
}

const metricDefs = <String, MetricDef>{
  'coverage': MetricDef('Couverture à pied', '%', scale: 100),
  'collection_rate': MetricDef('Déchets collectés', '%', scale: 100),
  'leakage_rate': MetricDef('Fuites vers les dépotoirs', '%', scale: 100, higherIsBetter: false),
  'equity_index': MetricDef('Indice d’équité', '', digits: 2),
  'cost_per_month': MetricDef('Coût par mois', 'F', higherIsBetter: false),
  'km_per_day': MetricDef('Distance par jour', 'km', higherIsBetter: false),
  'co2_kg_per_day': MetricDef('CO₂ par jour', 'kg', higherIsBetter: false),
  'unserved_points': MetricDef('Points non desservis', '', higherIsBetter: false),
};

// ---------------------------------------------------------------- Scénarios

class ScenarioView {
  ScenarioView(this.name, this.metrics);
  final String name;
  final Map<String, double> metrics;
}

Map<String, double> extractMetrics(Map item) {
  final out = <String, double>{};
  void take(dynamic m) {
    if (m is! Map) return;
    for (final k in metricDefs.keys) {
      final v = statOf(m[k]);
      if (v != null) out[k] = v.toDouble();
    }
  }

  final plan = item['plan'] is Map ? item['plan'] as Map : const {};
  final sim = item['simulation'] is Map ? item['simulation'] as Map : const {};
  take(item['metrics']);
  take(plan['metrics']);
  take(item['summary']);
  take(sim['summary']);
  take(item);
  return out;
}

List<ScenarioView> parseScenarios(dynamic raw) {
  Iterable<MapEntry<String, dynamic>> entries = const [];
  if (raw is Map) {
    final list = _first(raw, ['scenarios', 'items', 'results']);
    if (list is List) {
      entries = [for (var i = 0; i < list.length; i++) MapEntry('${i == 0 ? 'A' : i == 1 ? 'B' : i + 1}', list[i])];
    } else if (list is Map) {
      entries = [for (final e in list.entries) MapEntry(e.key.toString(), e.value)];
    } else {
      entries = [
        for (final e in raw.entries)
          if (e.value is Map && extractMetrics(e.value as Map).isNotEmpty) MapEntry(e.key.toString(), e.value),
      ];
    }
  } else if (raw is List) {
    entries = [for (var i = 0; i < raw.length; i++) MapEntry('${i == 0 ? 'A' : i == 1 ? 'B' : i + 1}', raw[i])];
  }
  final out = <ScenarioView>[];
  for (final e in entries) {
    if (e.value is! Map) continue;
    final m = e.value as Map;
    final name = (m['name'] ?? m['label'] ?? e.key).toString();
    final metrics = extractMetrics(m);
    if (metrics.isNotEmpty) out.add(ScenarioView(name, metrics));
  }
  return out;
}

// ---------------------------------------------------------------- Pré-collecteurs

class PrecollectorView {
  PrecollectorView(this.title, this.fields);
  final String title;
  final List<MapEntry<String, String>> fields;
}

String _scalar(dynamic v) {
  if (v is bool) return v ? 'Oui' : 'Non';
  if (v is int) return fmtInt(v);
  if (v is double) return v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1);
  return v.toString();
}

List<PrecollectorView> parsePrecollectors(dynamic raw) {
  dynamic list = raw;
  if (raw is Map) list = _first(raw, ['precollectors', 'pre_collectors', 'items', 'results', 'data']);
  if (list is! List) return [];
  final out = <PrecollectorView>[];
  for (final it in list) {
    if (it is! Map) continue;
    final title = (_first(it, ['name', 'label', 'zone', 'id']) ?? 'Pré-collecteur').toString();
    final fields = <MapEntry<String, String>>[];
    for (final e in it.entries) {
      final k = e.key.toString();
      if (k == 'name' || k == 'label') continue;
      final v = e.value;
      if (v is num || v is bool || (v is String && v.isNotEmpty && v.length < 60)) {
        fields.add(MapEntry(prettyKey(k), _scalar(v)));
      } else if (v is List) {
        fields.add(MapEntry(prettyKey(k), fmtInt(v.length)));
      }
    }
    out.add(PrecollectorView(title, fields));
  }
  return out;
}
