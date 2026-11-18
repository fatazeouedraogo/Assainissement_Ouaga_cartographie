import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

String _ago(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

class ImpactScreen extends StatefulWidget {
  const ImpactScreen({super.key, required this.active});
  final bool active;

  @override
  State<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends State<ImpactScreen> {
  Map<String, dynamic>? _ov;
  List _hot = [];
  List _leaders = [];
  List _mine = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ImpactScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = _ov == null;
      _error = null;
    });
    try {
      final r = await Future.wait([
        s.api.get('/api/public/overview'),
        s.api.get('/api/public/hotspots'),
        s.api.get('/api/public/leaderboard'),
        s.api.get('/api/reports/mine'),
      ]);
      if (mounted) {
        setState(() {
          _ov = Map<String, dynamic>.from(r[0] as Map);
          _hot = ((r[1] as Map)['hotspots'] as List?) ?? [];
          _leaders = ((r[2] as Map)['leaders'] as List?) ?? [];
          _mine = ((r[3] as Map)['reports'] as List?) ?? [];
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(Map by, String k) => ((by[k] as Map?)?['count'] as num?)?.toInt() ?? 0;

  double get _tonnes {
    const kg = {'small': 50.0, 'medium': 300.0, 'large': 1500.0};
    var t = 0.0;
    for (final r in _mine) {
      final m = r as Map;
      if (m['dump_status'] == 'cleaned') t += kg[m['size']] ?? 0;
    }
    return t / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _ov == null) return ErrorState(_error!, _load);
    final ov = _ov ?? {};
    final by = (ov['by_status'] as Map?) ?? {};
    final toDo = _count(by, 'verified') + _count(by, 'scheduled');
    final rec = ((ov['recurrence_rate'] as num?) ?? 0) * 100;
    return RefreshIndicator(
      onRefresh: _load,
      color: Pal.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('Mes signalements & impact', style: head(24)),
          const SizedBox(height: 2),
          Text('Suivi citoyen • Ouagadougou', style: body(14, c: Pal.inkSoft)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined, color: Pal.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'IMPACT CIVIQUE',
                      style: body(12, w: FontWeight.w800, c: Pal.primary),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${s.points} pts',
                        style: body(12, w: FontWeight.w700, c: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_mine.length} dépotoir(s) signalé(s) • ${_tonnes.toStringAsFixed(1)} tonne(s) évacuée(s) grâce à vous',
                  style: head(20, c: Colors.white, h: 1.25),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chaque dépôt validé est transmis à la mairie, puis nettoyé par la brigade.',
                  style: body(13, c: Colors.white70, h: 1.35),
                ),
              ],
            ),
          ),
          if (s.queued > 0) ...[
            const SizedBox(height: 18),
            Text('En attente de réseau', style: head(17)),
            const SizedBox(height: 10),
            AppCard(
              color: Pal.tertiaryFixed,
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: Pal.tertiaryDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Conservé sur le téléphone', style: head(15, c: Pal.tertiaryDeep)),
                        Text(
                          '${s.queued} signalement(s) pas encore envoyé(s)',
                          style: body(13, c: Pal.tertiaryDeep),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: s.syncing ? null : () => s.syncOutbox().then((_) => _load()),
                    child: const Text('Envoyer'),
                  ),
                ],
              ),
            ),
          ],
          SectionTitle('Vos signalements'),
          if (_mine.isEmpty)
            const AppCard(child: Text('Vous n’avez encore rien signalé. Utilisez l’onglet Signaler.'))
          else
            for (final r in _mine.take(12)) _reportCard(s, Map<String, dynamic>.from(r as Map)),
          SectionTitle('La ville en chiffres'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              Kpi('$toDo', 'dépotoirs à traiter', color: Pal.error, icon: Icons.warning_amber_rounded),
              Kpi(
                '${(ov['cleaned_last_30_days'] as num?)?.toInt() ?? 0}',
                'nettoyés en 30 jours',
                color: Pal.primaryDeep,
                icon: Icons.check_circle_outline,
              ),
              Kpi(
                fmtHours(ov['avg_hours_to_clean'] as num?),
                'délai moyen de traitement',
                color: Pal.secondary,
                icon: Icons.timer_outlined,
              ),
              Kpi('${rec.round()} %', 'de récidive', color: Pal.tertiaryDeep, icon: Icons.replay),
            ],
          ),
          SectionTitle('Classement des citoyens'),
          _list([
            for (var i = 0; i < _leaders.length && i < 8; i++)
              (
                '${(_leaders[i] as Map)['rank'] ?? i + 1}. ${(_leaders[i] as Map)['name']}',
                '${(_leaders[i] as Map)['points']} pts',
              ),
          ], 'Pas encore de classement.'),
          SectionTitle('Points chauds de récidive'),
          _list([
            for (var i = 0; i < _hot.length && i < 6; i++)
              (
                '${((_hot[i] as Map)['lat'] as num).toStringAsFixed(3)}, ${((_hot[i] as Map)['lon'] as num).toStringAsFixed(3)}',
                '${(_hot[i] as Map)['recurrences']} récidive(s)',
              ),
          ], 'Aucune récidive pour le moment.'),
        ],
      ),
    );
  }

  Widget _list(List<(String, String)> rows, String empty) {
    if (rows.isEmpty) return AppCard(child: Text(empty));
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].$1, style: body(14, w: FontWeight.w600)),
                  ),
                  Text(
                    rows[i].$2,
                    style: body(14, w: FontWeight.w800, c: Pal.primaryDeep),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportCard(Session s, Map<String, dynamic> r) {
    final dumpStatus = r['dump_status'] as String?;
    final rejected = r['status'] == 'rejected' || dumpStatus == 'rejected';
    var reached = 1;
    if (!rejected) reached = 1;
    if (!rejected && (dumpStatus == 'verified' || dumpStatus == 'scheduled' || dumpStatus == 'cleaned'))
      reached = 2;
    if (!rejected && dumpStatus == 'cleaned') reached = 3;
    const steps = ['1. Envoyé', '2. Contrôle auto OK', '3. Vérifié mairie', '4. Nettoyé'];
    final photo = r['photo_path'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: photo == null
                      ? Container(
                          width: 72,
                          height: 72,
                          color: Pal.container,
                          child: const Icon(Icons.image_outlined, color: Pal.outline),
                        )
                      : Image.network(
                          s.api.photoUrl(photo),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: Pal.container,
                            child: const Icon(Icons.broken_image_outlined, color: Pal.outline),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${sizeLabels[r['size']] ?? r['size']} • ${wasteLabels[r['waste_type']] ?? r['waste_type']}',
                              style: head(15),
                            ),
                          ),
                          Text(_ago(r['created_at'] as String?), style: body(11, c: Pal.inkSoft)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (rejected)
                        const Pill('Refusé', color: Color(0xFF991B1B), bg: Pal.errorSoft)
                      else
                        Pill(
                          statusLabels[dumpStatus ?? 'pending'] ?? 'En attente',
                          color: statusColor(dumpStatus ?? 'pending'),
                          bg: statusColor(dumpStatus ?? 'pending').withValues(alpha: 0.14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!rejected)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: i <= reached ? Pal.primary : Pal.container,
                        borderRadius: BorderRadius.circular(99),
                        border: i == reached ? Border.all(color: Pal.primaryDeep, width: 2) : null,
                      ),
                      child: Text(
                        steps[i],
                        style: body(11, w: FontWeight.w700, c: i <= reached ? Colors.white : Pal.inkSoft),
                      ),
                    ),
                ],
              )
            else if (((r['reject_reasons'] as List?) ?? []).isNotEmpty)
              Text('Motif : ${(r['reject_reasons'] as List).join(', ')}', style: body(12, c: Pal.inkSoft)),
            if (r['lat'] is num && r['lon'] is num)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      s.focus.value = [(r['lat'] as num).toDouble(), (r['lon'] as num).toDouble()],
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Voir sur la carte'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
