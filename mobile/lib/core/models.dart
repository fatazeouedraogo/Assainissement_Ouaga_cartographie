import 'package:flutter/material.dart';

import 'theme.dart';

const statusLabels = {
  'pending': 'En attente',
  'verified': 'Confirmé',
  'scheduled': 'Programmé',
  'cleaned': 'Nettoyé',
  'rejected': 'Rejeté',
};

const sizeLabels = {'small': 'Petit', 'medium': 'Moyen', 'large': 'Gros'};

const wasteLabels = {
  'household': 'Ménagers',
  'rubble': 'Gravats',
  'plastic': 'Plastiques',
  'organic': 'Organiques',
  'mixed': 'Mélangés',
};

const rejectReasonLabels = {
  'batiment': 'Bâtiment',
  'route': 'Route',
  'eau': 'Eau',
  'vegetation': 'Végétation',
  'rien_vu': 'Rien d’anormal',
  'deja_signale': 'Déjà signalé',
  'autre': 'Autre',
};

Color statusColor(String s) => switch (s) {
  'verified' => Pal.error,
  'scheduled' => Pal.secondary,
  'cleaned' => Pal.primaryDeep,
  'pending' => Pal.tertiary,
  _ => Pal.outline,
};

class Dump {
  Dump(this.raw, this.lat, this.lon);
  final Map<String, dynamic> raw;
  final double lat;
  final double lon;

  factory Dump.fromFeature(Map<String, dynamic> f) {
    final c = (f['geometry']['coordinates'] as List);
    return Dump(
      Map<String, dynamic>.from(f['properties'] as Map),
      (c[1] as num).toDouble(),
      (c[0] as num).toDouble(),
    );
  }

  String get id => raw['id'] as String;
  String get status => raw['status'] as String? ?? 'pending';
  String get size => raw['size'] as String? ?? 'medium';
  String get waste => raw['waste_type'] as String? ?? 'mixed';
  double get kg => (raw['est_kg'] as num?)?.toDouble() ?? 0;
  double get confidence => (raw['confidence'] as num?)?.toDouble() ?? 0;
  int get reporters => (raw['reporter_count'] as num?)?.toInt() ?? 0;
  double get priority => (raw['priority_score'] as num?)?.toDouble() ?? 0;
  String? get level => raw['priority_level'] as String?;
  String? get driver => raw['main_driver'] as String?;
  String? get beforePhoto => raw['before_photo'] as String?;
  String? get afterPhoto => raw['after_photo'] as String?;
  String? get scheduledFor => raw['scheduled_for'] as String?;
  bool get recurrence => raw['recurrence'] == true;
}

class Candidate {
  Candidate(this.id, this.score, this.lat, this.lon, this.signals);
  final String id;
  final double score;
  final double lat;
  final double lon;
  final Map<String, dynamic> signals;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
    j['id'] as String,
    (j['score'] as num).toDouble(),
    (j['lat'] as num).toDouble(),
    (j['lon'] as num).toDouble(),
    j['signals'] is Map ? Map<String, dynamic>.from(j['signals'] as Map) : {},
  );
}

String fmtKg(num kg) => kg >= 1000 ? '${(kg / 1000).toStringAsFixed(1)} t' : '${kg.round()} kg';

String fmtHours(num? h) {
  if (h == null) return '—';
  return h < 48 ? '${h.round()} h' : '${(h / 24).round()} j';
}

String fmtDate(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  final p = iso.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}
