import 'package:latlong2/latlong.dart';

class Dump {
  Dump({
    required this.id,
    required this.pos,
    required this.status,
    required this.size,
    required this.wasteType,
    required this.estKg,
    required this.confidence,
    required this.reporters,
    required this.priority,
    required this.level,
    required this.driver,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.recurrence,
    required this.firstReported,
    this.scheduledFor,
  });

  final String id;
  final LatLng pos;
  final String status;
  final String size;
  final String wasteType;
  final double estKg;
  final double confidence;
  final int reporters;
  final double priority;
  final String? level;
  final String? driver;
  final String? beforePhoto;
  final String? afterPhoto;
  final bool recurrence;
  final DateTime? firstReported;
  final String? scheduledFor;

  int get sizeLevel => size == 'small' ? 0 : size == 'large' ? 2 : 1;

  factory Dump.fromFeature(Map<String, dynamic> f) {
    final p = f['properties'] as Map<String, dynamic>;
    final c = (f['geometry']['coordinates'] as List).cast<num>();
    return Dump(
      id: p['id'] as String,
      pos: LatLng(c[1].toDouble(), c[0].toDouble()),
      status: p['status'] as String,
      size: p['size'] as String,
      wasteType: p['waste_type'] as String,
      estKg: (p['est_kg'] as num).toDouble(),
      confidence: (p['confidence'] as num?)?.toDouble() ?? 0,
      reporters: (p['reporter_count'] as num?)?.toInt() ?? 0,
      priority: (p['priority_score'] as num?)?.toDouble() ?? 0,
      level: p['priority_level'] as String?,
      driver: p['main_driver'] as String?,
      beforePhoto: p['before_photo'] as String?,
      afterPhoto: p['after_photo'] as String?,
      recurrence: p['recurrence'] == true,
      firstReported: p['first_reported_at'] == null ? null : DateTime.tryParse('${p['first_reported_at']}')?.toLocal(),
      scheduledFor: p['scheduled_for'] as String?,
    );
  }
}

class Candidate {
  Candidate({required this.id, required this.pos, required this.score, required this.baseScore, required this.signals, required this.merged});
  final String id;
  final LatLng pos;
  final double score;
  final double baseScore;
  final Map<String, double> signals;
  final int merged;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        id: j['id'] as String,
        pos: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        score: (j['score'] as num).toDouble(),
        baseScore: ((j['base_score'] ?? j['score']) as num).toDouble(),
        signals: ((j['signals'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toDouble())),
        merged: (j['merged'] as num?)?.toInt() ?? 0,
      );
}

const rejectReasonLabels = {
  'batiment': 'Bâtiment',
  'route': 'Route ou piste',
  'eau': 'Eau ou caniveau',
  'vegetation': 'Végétation',
  'rien_vu': 'Rien d’anormal',
  'deja_signale': 'Déjà signalé',
  'autre': 'Autre',
};

class AppUser {
  AppUser({required this.id, required this.name, required this.phone, required this.role, required this.points});
  final String id;
  final String name;
  final String phone;
  final String role;
  final int points;

  bool get isStaff => role == 'verifier' || role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        role: j['role'] as String,
        points: (j['points'] as num).toInt(),
      );
}

const sizeLabels = {'small': 'Petit', 'medium': 'Moyen', 'large': 'Gros'};
const sizeHints = {'small': 'Un tas, quelques sacs', 'medium': 'Plusieurs tas, une charrette', 'large': 'Un camion ou plus'};
const wasteLabels = {
  'household': 'Ordures ménagères',
  'rubble': 'Gravats',
  'plastic': 'Plastiques',
  'organic': 'Déchets organiques',
  'mixed': 'Mélange',
};
const statusLabels = {
  'pending': 'À vérifier',
  'verified': 'Vérifié',
  'scheduled': 'Programmé',
  'cleaned': 'Nettoyé',
  'rejected': 'Rejeté',
};
const driverLabels = {
  'size': 'Volume important',
  'age': 'Présent depuis longtemps',
  'water': 'Près d’un caniveau ou d’un cours d’eau',
  'sensitive': 'Près d’une école, d’un marché ou d’un centre de santé',
};
const levelLabels = {'critical': 'Critique', 'high': 'Élevée', 'medium': 'Moyenne', 'low': 'Faible'};
const flagLabels = {
  'photo_floue': 'Photo floue',
  'photo_sombre': 'Photo trop sombre',
  'contenu_douteux': 'Le contenu de la photo semble étranger à un dépotoir',
  'photo_copie_suspecte': 'Photo très proche de celle d’un autre signalement',
  'gps_imprecis': 'Position GPS imprécise',
  'deplacement_impossible': 'Déplacement trop rapide depuis le dernier signalement',
  'analyse_indisponible': 'Analyse de la photo indisponible',
};
const rejectLabels = {
  'hors_zone': 'La position est hors de Ouagadougou',
  'photo_absente': 'La photo est obligatoire',
  'photo_illisible': 'La photo est illisible',
  'doublon_meme_auteur': 'Vous avez déjà signalé ce dépotoir',
  'photo_reutilisee': 'Cette photo a déjà été utilisée pour un autre signalement',
};
