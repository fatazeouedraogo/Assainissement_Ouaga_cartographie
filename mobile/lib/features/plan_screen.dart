import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/analytics.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'plan_compare.dart';
import 'plan_simulation.dart';
import 'precollectors_screen.dart';
import 'report_button.dart';

String _int(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

num? _stat(dynamic v) {
  if (v is num) return v;
  if (v is Map && v['mean'] is num) return v['mean'] as num;
  return null;
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  List<Map<String, dynamic>> _controls = [];
  final Map<String, double> _vals = {};
  final Set<String> _on = {};
  Map<String, dynamic>? _res;
  String? _error;
  bool _loading = true;
  bool _running = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = context.read<Session>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await s.api.get('/api/plan/controls');
      final list = (j is Map ? j['controls'] : j) as List;
      _controls = [for (final c in list) Map<String, dynamic>.from(c as Map)];
      for (final c in _controls) {
        _vals[c['key'] as String] = (c['default'] as num).toDouble();
      }
      try {
        final last = await s.api.get('/api/plan/latest');
        _res = Map<String, dynamic>.from(last as Map);
      } on ApiException {
        _res = null;
      }
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run() async {
    final s = context.read<Session>();
    setState(() => _running = true);
    try {
      final j = await s.api.post('/api/plan', {
        'params': {for (final c in _controls) c['key'] as String: numOut(_vals[c['key']]!)},
        'events': [
          for (final k in _on) {'kind': k, if (planEvents[k]!.value != null) 'value': planEvents[k]!.value},
        ],
        'simulate': true,
        'time_limit_s': 6,
      }, 90);
      if (mounted) {
        setState(() {
          _res = Map<String, dynamic>.from(j as Map);
          _tab = 1;
        });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, _init);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text('Plan de collecte', style: head(26)),
        const SizedBox(height: 2),
        Text('Réglez les moyens, testez un imprévu, lisez le résultat.', style: body(14, c: Pal.inkSoft)),
        const SizedBox(height: 14),
        _Segments(
          labels: const ['Réglages', 'Résultat', 'Courbes', 'Comparer'],
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 6),
        if (_tab == 0)
          ..._settings()
        else if (_tab == 1)
          ..._resultTab()
        else if (_tab == 2)
          SimulationPanel(result: _res)
        else
          ComparePanel(controls: _controls, values: _vals, events: _on),
      ],
    );
  }

  List<Widget> _settings() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final c in _controls) {
      groups.putIfAbsent((c['group'] as String?) ?? 'Réglages', () => []).add(c);
    }
    return [
      SectionTitle('Paramètres de la commune'),
      for (final g in groups.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: g.key == groups.keys.first,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                title: Text(g.key, style: head(15)),
                children: [for (final c in g.value) _slider(c)],
              ),
            ),
          ),
        ),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Pal.tertiaryFixed.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Pal.tertiaryFixed),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Pal.tertiary, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.bolt, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SIMULATION D’ALÉAS RÉELS',
                        style: body(10, w: FontWeight.w800, c: Pal.tertiaryDeep),
                      ),
                      Text('Crash-test en direct', style: head(17)),
                    ],
                  ),
                ),
                Pill(
                  _on.isEmpty ? 'INACTIF' : '${_on.length} ACTIF(S)',
                  color: _on.isEmpty ? Pal.inkSoft : Pal.tertiaryDeep,
                  bg: _on.isEmpty ? Pal.container : Pal.tertiaryFixed,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in planEvents.entries)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(e.value.icon, color: _on.contains(e.key) ? Pal.error : Pal.inkSoft, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(e.value.label, style: head(14, w: FontWeight.w700)),
                    ),
                    Switch(
                      value: _on.contains(e.key),
                      activeTrackColor: Pal.primary,
                      onChanged: (v) => setState(() => v ? _on.add(e.key) : _on.remove(e.key)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _running ? null : _run,
        icon: _running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : const Icon(Icons.autorenew_rounded),
        label: Text(_running ? 'Calcul en cours…' : 'Recalculer le plan maintenant'),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: Text(
            'Optimisation sous contraintes de capacité et de route',
            style: body(12, c: Pal.inkSoft),
          ),
        ),
      ),
    ];
  }

  List<Widget> _resultTab() {
    if (_res == null) {
      return [
        const SizedBox(height: 40),
        const EmptyState(
          Icons.local_shipping_outlined,
          'Aucun plan calculé',
          'Réglez les paramètres puis touchez « Recalculer le plan maintenant ».',
        ),
      ];
    }
    return _result(_res!);
  }

  Widget _slider(Map<String, dynamic> c) {
    final key = c['key'] as String;
    final min = (c['min'] as num).toDouble();
    final max = (c['max'] as num).toDouble();
    final step = (c['step'] as num?)?.toDouble() ?? 1;
    final v = _vals[key]!.clamp(min, max);
    final div = step > 0 ? ((max - min) / step).round() : 0;
    final unit = c['unit'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text('${c['label']}', style: body(14, w: FontWeight.w600, h: 1.25)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(99)),
              child: Text(
                '${numOut(v)}${unit == null || unit.isEmpty ? '' : ' $unit'}',
                style: body(12, w: FontWeight.w800, c: Pal.primaryDeep),
              ),
            ),
          ],
        ),
        Slider(
          value: v,
          min: min,
          max: max,
          divisions: div > 0 && div <= 400 ? div : null,
          activeColor: Pal.primary,
          onChanged: (x) => setState(() => _vals[key] = x),
        ),
      ],
    );
  }

  List<Widget> _result(Map<String, dynamic> r) {
    final plan = Map<String, dynamic>.from((r['plan'] ?? r) as Map);
    final m = Map<String, dynamic>.from((plan['metrics'] as Map?) ?? {});
    final sim = (r['simulation'] as Map?) ?? {};
    final sum = (sim['summary'] as Map?) ?? {};
    final warnings = (r['warnings'] as List?) ?? [];
    final cov = (m['coverage'] as num?)?.toDouble();
    final eq = (m['equity_index'] as num?)?.toDouble();
    final col = _stat(sum['collection_rate']);
    final leak = _stat(sum['leakage_rate']);
    final groups = plan['groups'] is List
        ? [for (final g in (plan['groups'] as List)) Map<String, dynamic>.from(g as Map)]
        : <Map<String, dynamic>>[];
    final hasRoutes = groups.isNotEmpty && plan['points'] is List;
    var n = 0;
    return [
      SectionTitle(
        'Plan optimisé',
        trailing: m['within_budget'] == null
            ? null
            : (m['within_budget'] == true
                  ? const Pill('Dans le budget')
                  : const Pill('Hors budget', color: Color(0xFF991B1B), bg: Pal.errorSoft)),
      ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          Kpi(
            cov == null ? '—' : '${(cov * 100).round()} %',
            'couverture à pied',
            color: Pal.primaryDeep,
            icon: Icons.directions_walk,
          ),
          Kpi(
            eq == null ? '—' : eq.toStringAsFixed(2),
            'indice d’équité',
            color: Pal.secondary,
            icon: Icons.balance,
          ),
          Kpi(
            m['cost_per_month'] == null ? '—' : '${_int(m['cost_per_month'] as num)} F',
            'coût par mois',
            color: Pal.ink,
            icon: Icons.payments_outlined,
          ),
          Kpi(
            m['km_per_day'] == null ? '—' : '${(m['km_per_day'] as num).toStringAsFixed(0)} km',
            'parcourus par jour',
            color: Pal.ink,
            icon: Icons.route_outlined,
          ),
          if (col != null)
            Kpi(
              '${(col * 100).round()} %',
              'déchets collectés',
              color: Pal.primaryDeep,
              icon: Icons.recycling,
            ),
          if (leak != null)
            Kpi(
              '${(leak * 100).round()} %',
              'fuites vers les dépotoirs',
              color: Pal.error,
              icon: Icons.water_damage_outlined,
            ),
          if (m['co2_kg_per_day'] != null)
            Kpi(
              '${(m['co2_kg_per_day'] as num).toStringAsFixed(0)} kg',
              'CO₂ par jour',
              color: Pal.inkSoft,
              icon: Icons.eco_outlined,
            ),
          if (m['unserved_points'] != null)
            Kpi(
              '${m['unserved_points']}',
              'point(s) non desservi(s)',
              color: Pal.tertiaryDeep,
              icon: Icons.report_problem_outlined,
            ),
        ],
      ),
      if ((plan['applied_events'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in (plan['applied_events'] as List))
              Pill('$e', color: Pal.secondary, bg: Pal.secondaryFixed),
          ],
        ),
      ],
      for (final w in warnings)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppCard(
            color: Pal.tertiaryFixed,
            padding: const EdgeInsets.all(12),
            child: Text('$w', style: body(13, c: Pal.tertiaryDeep, h: 1.3)),
          ),
        ),
      if (hasRoutes) ...[
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlanMapScreen(plan: plan))),
          icon: const Icon(Icons.route_outlined),
          label: const Text('Voir les tournées en mouvement'),
        ),
        SectionTitle('Détail des tournées'),
        for (final g in groups)
          for (final rt in ((g['routes'] as List?) ?? []))
            Builder(
              builder: (_) {
                n++;
                final route = Map<String, dynamic>.from(rt as Map);
                final tri = route['kind'] == 'tricycle';
                final stops = (route['stops'] as List?)?.length ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tri ? Pal.tertiary : Pal.secondary,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(n.toString().padLeft(2, '0'), style: head(17, c: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tri ? 'Tricycle' : 'Camion-benne', style: head(15)),
                              const SizedBox(height: 2),
                              Text(
                                '$stops arrêt(s) • ${g['name'] ?? g['label'] ?? 'tournée'}',
                                style: body(12, c: Pal.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        Icon(tri ? Icons.pedal_bike : Icons.local_shipping_outlined, color: Pal.outline),
                      ],
                    ),
                  ),
                );
              },
            ),
      ],
      const SectionTitle('Aller plus loin'),
      OutlinedButton.icon(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrecollectorsScreen())),
        icon: const Icon(Icons.pedal_bike),
        label: const Text('Vue des pré-collecteurs'),
      ),
      const SizedBox(height: 10),
      const ReportButton(),
    ];
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.labels, required this.index, required this.onTap});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: index == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: head(13, w: FontWeight.w700, c: index == i ? Pal.ink : Pal.inkSoft),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PlanMapScreen extends StatefulWidget {
  const PlanMapScreen({super.key, required this.plan});
  final Map<String, dynamic> plan;

  @override
  State<PlanMapScreen> createState() => _PlanMapScreenState();
}

class _PlanMapScreenState extends State<PlanMapScreen> with SingleTickerProviderStateMixin {
  static const _palette = [
    Pal.secondary,
    Pal.primaryDeep,
    Pal.tertiary,
    Color(0xFF7C3AED),
    Pal.error,
    Color(0xFF0891B2),
  ];
  late final AnimationController _anim;
  late final Map<String, LatLng> _pts;
  int _group = 0;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _pts = {
      for (final p in (widget.plan['points'] as List))
        (p as Map)['id'] as String: LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
    };
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _groups => [
    for (final g in (widget.plan['groups'] as List)) Map<String, dynamic>.from(g as Map),
  ];

  List<Map<String, dynamic>> get _routes => [
    for (final r in (_groups[_group]['routes'] as List? ?? [])) Map<String, dynamic>.from(r as Map),
  ];

  List<LatLng> _path(Map<String, dynamic> r) => [
    for (final s in (r['stops'] as List))
      if (_pts[s] != null) _pts[s]!,
  ];

  LatLng _at(List<LatLng> p, double t) {
    if (p.length == 1) return p.first;
    final seg = <double>[];
    var total = 0.0;
    for (var i = 0; i < p.length - 1; i++) {
      final d = math.sqrt(
        math.pow(p[i + 1].latitude - p[i].latitude, 2) + math.pow(p[i + 1].longitude - p[i].longitude, 2),
      );
      seg.add(d);
      total += d;
    }
    var target = (t < 0.5 ? t * 2 : (1 - t) * 2) * total;
    for (var i = 0; i < seg.length; i++) {
      if (target <= seg[i] || i == seg.length - 1) {
        final f = seg[i] == 0 ? 0.0 : (target / seg[i]).clamp(0.0, 1.0);
        return LatLng(
          p[i].latitude + (p[i + 1].latitude - p[i].latitude) * f,
          p[i].longitude + (p[i + 1].longitude - p[i].longitude) * f,
        );
      }
      target -= seg[i];
    }
    return p.last;
  }

  void _setSpeed(double v) {
    setState(() => _speed = v);
    _anim
      ..duration = Duration(milliseconds: (14000 / v).round())
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;
    final all = _pts.values.toList();
    final paths = [for (final r in routes) _path(r)];
    return Scaffold(
      appBar: AppBar(title: const Text('Tournées')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: all.isEmpty ? const LatLng(12.3714, -1.5197) : all.first,
                initialZoom: 13,
                initialCameraFit: all.length > 1
                    ? CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(40), maxZoom: 17)
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'bf.ouagaclean.app',
                ),
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i < paths.length; i++)
                      if (paths[i].length > 1)
                        Polyline(
                          points: paths[i],
                          color: _palette[i % _palette.length].withValues(alpha: 0.75),
                          strokeWidth: 4,
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final p in all)
                      Marker(
                        point: p,
                        width: 12,
                        height: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Pal.ink, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => MarkerLayer(
                    markers: [
                      for (var i = 0; i < paths.length; i++)
                        if (paths[i].isNotEmpty)
                          Marker(
                            point: _at(paths[i], (_anim.value + i * 0.13) % 1),
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _palette[i % _palette.length],
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(
                                routes[i]['kind'] == 'tricycle' ? Icons.pedal_bike : Icons.local_shipping,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_groups.length > 1)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var g = 0; g < _groups.length; g++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  '${_groups[g]['name'] ?? _groups[g]['label'] ?? 'Groupe ${g + 1}'}',
                                ),
                                selected: _group == g,
                                onSelected: (_) => setState(() => _group = g),
                                selectedColor: Pal.primaryFixed,
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Text('${routes.length} tournée(s)', style: body(13, w: FontWeight.w700)),
                      const Spacer(),
                      for (final v in const [1.0, 2.0, 4.0])
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text('${v.round()}×'),
                            selected: _speed == v,
                            onSelected: (_) => _setSpeed(v),
                            selectedColor: Pal.primaryFixed,
                            showCheckmark: false,
                          ),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('© contributeurs OpenStreetMap', style: body(10, c: Pal.inkSoft)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
