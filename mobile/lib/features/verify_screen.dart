import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'candidate_sheet.dart';
import 'dump_sheet.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.active});
  final bool active;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  List<Dump> _pending = [];
  List<Candidate> _cands = [];
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VerifyScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = _pending.isEmpty && _cands.isEmpty;
      _error = null;
    });
    try {
      final d = await s.api.get('/api/dumps', query: {'status': 'pending', 'limit': '300'}) as Map;
      final pending = [
        for (final f in (d['features'] as List)) Dump.fromFeature(Map<String, dynamic>.from(f as Map)),
      ];
      final c = await s.api.get('/api/candidates') as Map;
      final st = await s.api.get('/api/candidates/stats') as Map;
      if (mounted) {
        setState(() {
          _pending = pending;
          _cands = [
            for (final x in (c['candidates'] as List))
              Candidate.fromJson(Map<String, dynamic>.from(x as Map)),
          ];
          _stats = Map<String, dynamic>.from(st);
        });
        s.setToVerify(pending.length);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _pending.isEmpty && _cands.isEmpty) return ErrorState(_error!, _load);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(14)),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                labelStyle: head(13, w: FontWeight.w700),
                unselectedLabelStyle: head(13, w: FontWeight.w600, c: Pal.inkSoft),
                labelColor: Pal.ink,
                tabs: [
                  Tab(text: 'Signalements (${_pending.length})', height: 38),
                  Tab(text: 'Satellite (${_cands.length})', height: 38),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                RefreshIndicator(onRefresh: _load, color: Pal.primary, child: _pendingList()),
                RefreshIndicator(onRefresh: _load, color: Pal.primary, child: _candList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(Dump d, bool ok) async {
    final s = context.read<Session>();
    String? reason;
    if (!ok) {
      reason = await pickOption<String>(context, 'Motif du rejet', const {
        'Photo sans rapport avec un dépotoir': 'Photo sans rapport',
        'Doublon d’un signalement existant': 'Doublon',
        'Hors du périmètre de la commune': 'Hors périmètre',
        'Déjà nettoyé': 'Déjà nettoyé',
      });
      if (reason == null || !mounted) return;
    }
    try {
      if (ok) {
        await s.api.post('/api/dumps/${d.id}/verify');
      } else {
        await s.api.post('/api/dumps/${d.id}/reject', {'reason': reason});
      }
      if (mounted) toast(context, ok ? 'Dépotoir confirmé' : 'Signalement rejeté');
      _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Widget _pendingList() {
    final api = context.read<Session>().api;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: Pal.tertiary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MODÉRATION CITOYENNE',
                    style: body(11, w: FontWeight.w800, c: Pal.tertiaryDeep),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('${_pending.length} signalement(s) en attente', style: head(24)),
              const SizedBox(height: 6),
              Text(
                'Contrôle de conformité avant injection dans le plan de collecte.',
                style: body(13, c: Pal.inkSoft, h: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_pending.isEmpty)
          const SizedBox(
            height: 260,
            child: EmptyState(Icons.task_alt, 'Rien à vérifier', 'Tous les signalements ont été traités.'),
          ),
        for (final d in _pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('#${d.id.substring(0, 6).toUpperCase()}', style: head(17))),
                      Pill(sizeLabels[d.size] ?? d.size, color: Pal.inkSoft, bg: Pal.container),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (d.beforePhoto != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Image.network(
                            api.photoUrl(d.beforePhoto!),
                            height: 190,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 190,
                              color: Pal.container,
                              child: const Icon(Icons.broken_image_outlined, color: Pal.outline),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                wasteLabels[d.waste] ?? d.waste,
                                style: body(11, w: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: Pal.primaryDeep),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${d.lat.toStringAsFixed(4)}° N, ${d.lon.abs().toStringAsFixed(4)}° ${d.lon < 0 ? 'O' : 'E'}',
                            style: body(14, w: FontWeight.w600),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            context.read<Session>().focus.value = [d.lat, d.lon];
                          },
                          child: const Icon(Icons.open_in_new, size: 20, color: Pal.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: d.reporters > 1 ? Pal.primaryFixed : Pal.tertiaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          d.reporters > 1 ? Icons.check_circle_outline : Icons.info_outline,
                          size: 20,
                          color: d.reporters > 1 ? Pal.onPrimaryFixed : Pal.tertiaryDeep,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${d.reporters} signalement(s) • confiance ${(d.confidence * 100).round()} % • ~${fmtKg(d.kg)}',
                            style: body(
                              13,
                              w: FontWeight.w600,
                              c: d.reporters > 1 ? Pal.onPrimaryFixed : Pal.tertiaryDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _decide(d, false),
                          style: FilledButton.styleFrom(
                            backgroundColor: Pal.errorSoft,
                            foregroundColor: const Color(0xFF991B1B),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.block, size: 18),
                          label: const Text('Rejeter'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _decide(d, true),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Valider'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _candList() {
    final st = _stats ?? {};
    final precision = st['precision'] as num?;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        AppCard(
          color: Pal.secondaryFixed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Précision de la détection', style: head(15, c: const Color(0xFF1E3A8A))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    precision == null ? '—' : '${(precision * 100).round()} %',
                    style: head(30, c: Pal.secondary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${st['confirmed'] ?? 0} confirmés sur ${st['reviewed'] ?? 0} vérifiés sur le terrain',
                      style: body(13, c: const Color(0xFF1E3A8A), h: 1.3),
                    ),
                  ),
                ],
              ),
              if (st['suggested_threshold'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Seuil conseillé : ${st['suggested_threshold']}',
                  style: body(12, w: FontWeight.w700, c: Pal.secondary),
                ),
              ],
              if (st['note'] != null) ...[
                const SizedBox(height: 6),
                Text('${st['note']}', style: body(12, c: Pal.inkSoft, h: 1.3)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_cands.isEmpty)
          const SizedBox(
            height: 260,
            child: EmptyState(
              Icons.satellite_alt,
              'Aucun candidat',
              'Lancez une analyse satellite pour en obtenir.',
            ),
          )
        else
          for (final c in _cands)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () async {
                  if (await showCandidateSheet(context, c)) _load();
                },
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Pal.secondaryFixed,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.satellite_alt, color: Pal.secondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Zone suspecte · score ${c.score.toStringAsFixed(1)}', style: head(15)),
                          const SizedBox(height: 2),
                          Text(
                            '${c.lat.toStringAsFixed(4)}, ${c.lon.toStringAsFixed(4)}',
                            style: body(12, c: Pal.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Pal.outline),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
