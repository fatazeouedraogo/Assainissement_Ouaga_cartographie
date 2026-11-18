import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analytics.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Communes enregistrées sur le serveur (`GET /api/admin/communes`).
class CommunesScreen extends StatefulWidget {
  const CommunesScreen({super.key});

  @override
  State<CommunesScreen> createState() => _CommunesScreenState();
}

class _CommunesScreenState extends State<CommunesScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await s.api.get('/api/admin/communes');
      _items = [for (final c in ((j as Map)['communes'] as List? ?? [])) Map<String, dynamic>.from(c as Map)];
    } on ApiException catch (e) {
      _error = e.status == 404
          ? 'Le serveur ne propose pas encore les communes (module à installer côté API).'
          : e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = ErrorState(_error!, _load);
    } else if (_items.isEmpty) {
      content = const EmptyState(
        Icons.location_city,
        'Aucune commune enregistrée',
        'Importez les limites d’une commune sur le serveur pour la voir ici.',
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            for (final c in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => QuartiersScreen(communeId: _n(c['id']), name: '${c['name']}')),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Pal.primaryFixed, borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.location_city, color: Pal.primaryDeep),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['name']}', style: head(16)),
                            if (c['mairie'] != null) Text('${c['mairie']}', style: body(12, w: FontWeight.w600, c: Pal.primaryDeep)),
                            Text(
                              [
                                if (c['province'] != null) '${c['province']}',
                                if (c['region'] != null) '${c['region']}',
                              ].join(' • '),
                              style: body(12, c: Pal.inkSoft),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_n(c['quartiers'])} quartier(s) • ${_n(c['open_count'])} à traiter • ${_n(c['cleaned_count'])} nettoyé(s)',
                              style: body(12, w: FontWeight.w600),
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
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Communes')), body: content);
  }
}

/// Classement des quartiers d'une commune (`GET /api/admin/communes/:id/quartiers`).
class QuartiersScreen extends StatefulWidget {
  const QuartiersScreen({super.key, required this.communeId, required this.name});
  final int communeId;
  final String name;

  @override
  State<QuartiersScreen> createState() => _QuartiersScreenState();
}

class _QuartiersScreenState extends State<QuartiersScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  bool _byOpen = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await s.api.get('/api/admin/communes/${widget.communeId}/quartiers');
      _items = [for (final q in ((j as Map)['quartiers'] as List? ?? [])) Map<String, dynamic>.from(q as Map)];
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  double _share(Map<String, dynamic> q) {
    final t = _n(q['open_count']) + _n(q['cleaned_count']);
    return t == 0 ? 0 : _n(q['cleaned_count']) / t;
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = ErrorState(_error!, _load);
    } else if (_items.isEmpty) {
      content = const EmptyState(
        Icons.holiday_village_outlined,
        'Aucun quartier enregistré',
        'Importez les secteurs ou villages de cette commune sur le serveur.',
      );
    } else {
      final list = [..._items]
        ..sort((a, b) => _byOpen
            ? _n(b['open_count']).compareTo(_n(a['open_count']))
            : _share(b).compareTo(_share(a)));
      final noGeom = _items.where((q) => q['has_geom'] != true).length;
      content = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Plus à traiter'),
                  selected: _byOpen,
                  onSelected: (_) => setState(() => _byOpen = true),
                  selectedColor: Pal.primaryFixed,
                  showCheckmark: false,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mieux nettoyés'),
                  selected: !_byOpen,
                  onSelected: (_) => setState(() => _byOpen = false),
                  selectedColor: Pal.primaryFixed,
                  showCheckmark: false,
                ),
              ],
            ),
            if (noGeom > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppCard(
                  color: Pal.tertiaryFixed,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$noGeom quartier(s) sans limites sur le serveur : leurs compteurs restent à zéro.',
                    style: body(12, c: Pal.tertiaryDeep, h: 1.3),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            for (var i = 0; i < list.length; i++) _tile(i + 1, list[i]),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(widget.name)), body: content);
  }

  Widget _tile(int rank, Map<String, dynamic> q) {
    final open = _n(q['open_count']);
    final cleaned = _n(q['cleaned_count']);
    final share = _share(q);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(10)),
                  child: Text('$rank', style: head(14, c: Pal.inkSoft)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prettyKey('${q['name']}'), style: head(15)),
                      if (q['arrondissement'] != null)
                        Text('${q['arrondissement']}', style: body(12, c: Pal.inkSoft)),
                    ],
                  ),
                ),
                Pill(
                  '${open + cleaned == 0 ? '—' : '${(share * 100).round()} %'} nettoyé',
                  color: Pal.onPrimaryFixed,
                  bg: Pal.primaryFixed,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 7,
                backgroundColor: Pal.container,
                color: Pal.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text('$open à traiter • $cleaned nettoyé(s)', style: body(12, c: Pal.inkSoft)),
          ],
        ),
      ),
    );
  }
}
