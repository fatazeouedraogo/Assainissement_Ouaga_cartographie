import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'insights.dart';
import 'plan_map_screen.dart';

String pct(num v) => '${(v * 100).toStringAsFixed(1)} %';

String money(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

const _events = <String, Map<String, dynamic>>{
  'Camion en panne': {'kind': 'truck_breakdown', 'value': 1},
  'Saison des pluies': {'kind': 'rain_season'},
  'Budget −20 %': {'kind': 'budget_cut', 'value': 0.2},
  'Abonnements −20 %': {'kind': 'subscription_drop', 'value': 0.2},
  '+2 camions': {'kind': 'more_trucks', 'value': 2},
};

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  List<Map<String, dynamic>> _controls = [];
  final Map<String, double> _values = {};
  final Set<String> _active = {};
  Map<String, dynamic>? _result;
  List<dynamic>? _compare;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadControls();
  }

  Future<void> _loadControls() async {
    try {
      final j = await context.read<AppState>().api.get('/api/plan/controls');
      final list = (j['controls'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _controls = list;
        for (final c in list) {
          _values[c['key'] as String] = (c['default'] as num).toDouble();
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Map<String, dynamic> get _params {
    final out = <String, dynamic>{};
    for (final c in _controls) {
      final k = c['key'] as String;
      final v = _values[k]!;
      final intLike = (c['step'] as num) % 1 == 0 && (c['default'] as num) % 1 == 0;
      out[k] = intLike ? v.round() : double.parse(v.toStringAsFixed(4));
    }
    out['replications'] = 15;
    return out;
  }

  List<Map<String, dynamic>> get _eventList => [for (final e in _active) _events[e]!];

  Future<void> _run() async {
    final api = context.read<AppState>().api;
    setState(() {
      _busy = true;
      _error = null;
      _compare = null;
    });
    try {
      final j = await api.post('/api/plan', {'params': _params, 'events': _eventList, 'time_limit_s': 5});
      setState(() => _result = j as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compareRun() async {
    final api = context.read<AppState>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await api.post('/api/scenarios/compare', {
        'inline': [
          {'name': 'Situation actuelle', 'params': <String, dynamic>{}, 'events': <dynamic>[]},
          {'name': 'Votre scénario', 'params': _params, 'events': _eventList},
        ],
      });
      setState(() => _compare = j['scenarios'] as List);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final c in _controls) {
      groups.putIfAbsent(c['group'] as String, () => []).add(c);
    }
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        Text('Et si… ?', style: t.headlineMedium),
        const SizedBox(height: 4),
        Text('Changez les moyens, imposez un aléa, et le plan se recalcule avec toutes les réplications.', style: t.bodyMedium?.copyWith(color: Pal.inkSoft)),
        const SizedBox(height: 14),
        WeatherBanner(onActivate: () => setState(() => _active.add('Saison des pluies'))),
        const AskCard(),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _events.keys)
            FilterChip(
              label: Text(e),
              showCheckmark: false,
              selected: _active.contains(e),
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _active.contains(e) ? Pal.surface : Pal.ink),
              onSelected: (v) => setState(() => v ? _active.add(e) : _active.remove(e)),
            ),
        ]),
        const SizedBox(height: 14),
        if (_controls.isEmpty && _error == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Pal.ink))),
        for (final g in groups.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Plate(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.key.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Pal.inkSoft)),
                for (final c in g.value) _slider(c),
              ]),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Plate(color: const Color(0xFFF6D6D2), child: Text(_error!, style: const TextStyle(fontWeight: FontWeight.w600)))),
        FilledButton(onPressed: _busy || _controls.isEmpty ? null : _run, child: Text(_busy ? 'Calcul en cours…' : 'Lancer la simulation')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy || _controls.isEmpty ? null : _compareRun, child: const Text('Comparer à la situation actuelle')),
        const SizedBox(height: 18),
        const DetectionStatsCard(),
        if (_result != null) ..._resultViews(context),
        if (_result != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanMapScreen(plan: _result!['plan'] as Map<String, dynamic>))),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Voir les tournées en mouvement'),
          ),
          const SizedBox(height: 8),
          RecommendCard(params: _params, events: _eventList),
          const SizedBox(height: 8),
          ParetoCard(params: _params),
          const SizedBox(height: 8),
          const PdfButton(),
        ],
        if (_compare != null) ..._compareViews(context),
      ]),
    );
  }

  Widget _slider(Map<String, dynamic> c) {
    final k = c['key'] as String;
    final lo = (c['min'] as num).toDouble();
    final hi = (c['max'] as num).toDouble();
    final step = (c['step'] as num).toDouble();
    final v = _values[k] ?? lo;
    final divisions = ((hi - lo) / step).round().clamp(1, 1000);
    final unit = c['unit'] as String;
    final isRatio = unit.isEmpty && hi <= 3;
    final label = isRatio && hi <= 1 ? pct(v) : unit == 'FCFA' ? money(v) : '${step % 1 == 0 ? v.round() : v.toStringAsFixed(2)} $unit'.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(c['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Slider(value: v.clamp(lo, hi), min: lo, max: hi, divisions: divisions, onChanged: (x) => setState(() => _values[k] = x)),
      ]),
    );
  }

  List<Widget> _resultViews(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final plan = _result!['plan'] as Map<String, dynamic>;
    final m = plan['metrics'] as Map<String, dynamic>;
    final sim = _result!['simulation'] as Map<String, dynamic>?;
    final sum = sim?['summary'] as Map<String, dynamic>?;
    final warnings = (_result!['warnings'] as List?)?.cast<String>() ?? [];
    final events = (plan['applied_events'] as List?)?.cast<String>() ?? [];
    final over = m['within_budget'] == false;
    return [
      const SizedBox(height: 22),
      Text('Résultat', style: t.titleLarge),
      if (events.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Aléas appliqués : ${events.join(', ')}', style: t.bodyMedium?.copyWith(color: Pal.inkSoft))),
      if (warnings.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Plate(color: Pal.signal, padding: const EdgeInsets.all(10), child: Text(_warn(warnings), style: const TextStyle(fontWeight: FontWeight.w700)))),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.55,
        children: [
          if (sum != null) _Kpi('Déchets collectés', pct(sum['collection_rate']['mean']), 'entre ${pct(sum['collection_rate']['p05'])} et ${pct(sum['collection_rate']['p95'])}'),
          if (sum != null) _Kpi('Partis en dépotoirs', pct(sum['leakage_rate']['mean']), 'entre ${pct(sum['leakage_rate']['p05'])} et ${pct(sum['leakage_rate']['p95'])}', bad: true),
          _Kpi('Coût mensuel', money(m['cost_per_month']), over ? 'au-dessus du budget (${money(m['budget_month'])})' : 'dans le budget', bad: over),
          _Kpi('Couverture à pied', pct(m['coverage']), '${m['points']} points, marche ≤ ${m['p90_walk_m']} m pour 9 ménages sur 10'),
          _Kpi('Équité des quartiers', pct(m['equity_index']), 'périphérie / centre : ${pct(m['coverage_by_ring']['outer'] ?? 0)} / ${pct(m['coverage_by_ring']['inner'] ?? 0)}'),
          _Kpi('Parcours par jour', '${(m['km_per_day'] as num).round()} km', '${(m['co2_kg_per_day'] as num).round()} kg de CO₂'),
        ],
      ),
      if ((m['unserved_points'] as num) > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${m['unserved_points']} point(s) non desservis avec cette flotte.', style: t.bodyMedium?.copyWith(color: Pal.dump, fontWeight: FontWeight.w700))),
      if (sim != null) ...[
        const SizedBox(height: 16),
        Plate(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Déchets accumulés dans les dépotoirs', style: t.titleMedium),
            Text('Moyenne et fourchette 5–95 % sur ${sim['replications']} simulations', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
            const SizedBox(height: 10),
            SizedBox(height: 150, width: double.infinity, child: CustomPaint(painter: _BandChart(sim['series']['dump_stock_kg'] as Map<String, dynamic>))),
            const SizedBox(height: 6),
            Text('${sim['horizon_days']} jours simulés', style: t.bodySmall),
          ]),
        ),
      ],
    ];
  }

  String _warn(List<String> w) {
    const map = {
      'depot_a_renseigner': 'Garage non renseigné (valeur provisoire)',
      'decharge_a_renseigner': 'Décharge non renseignée (valeur provisoire)',
      'aucun_batiment_importe': 'Aucun bâtiment importé',
    };
    return w.map((x) => map[x] ?? x).join('\n');
  }

  List<Widget> _compareViews(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return [
      const SizedBox(height: 22),
      Text('Comparaison', style: t.titleLarge),
      const SizedBox(height: 8),
      for (final s in _compare!)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Plate(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['name'] as String, style: t.titleMedium),
              const SizedBox(height: 6),
              _line('Collecte', pct(s['headline']['collection_rate']['mean']), s['delta_vs_first']?['collection_rate']),
              _line('Fuites', pct(s['headline']['leakage_rate']['mean']), s['delta_vs_first']?['leakage_rate'], invert: true),
              _line('Coût mensuel', money(s['headline']['cost_per_month']), s['delta_vs_first']?['cost_per_month'], invert: true, isMoney: true),
              _line('Équité', pct(s['headline']['equity_index']), s['delta_vs_first']?['equity_index']),
            ]),
          ),
        ),
    ];
  }

  Widget _line(String label, String value, dynamic delta, {bool invert = false, bool isMoney = false}) {
    Widget? d;
    if (delta is num && delta != 0) {
      final good = invert ? delta < 0 : delta > 0;
      final txt = isMoney ? '${delta > 0 ? '+' : '−'}${money(delta.abs())}' : '${delta > 0 ? '+' : '−'}${(delta.abs() * 100).toStringAsFixed(1)} pt';
      d = Text(txt, style: TextStyle(fontWeight: FontWeight.w800, color: good ? Pal.cleaned : Pal.dump));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700)), if (d != null) ...[const SizedBox(width: 10), d]]),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.title, this.value, this.note, {this.bad = false});
  final String title;
  final String value;
  final String note;
  final bool bad;

  @override
  Widget build(BuildContext context) => Plate(
        padding: const EdgeInsets.all(12),
        color: bad ? const Color(0xFFF6D6D2) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.inkSoft)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22))),
          Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.2)),
        ]),
      );
}

class _BandChart extends CustomPainter {
  _BandChart(this.series);
  final Map<String, dynamic> series;

  @override
  void paint(Canvas canvas, Size size) {
    final mean = (series['mean'] as List).cast<num>().map((e) => e.toDouble()).toList();
    final lo = (series['p05'] as List).cast<num>().map((e) => e.toDouble()).toList();
    final hi = (series['p95'] as List).cast<num>().map((e) => e.toDouble()).toList();
    if (mean.length < 2) return;
    final top = hi.reduce((a, b) => a > b ? a : b);
    final maxV = top <= 0 ? 1.0 : top * 1.1;
    Offset pt(int i, double v) => Offset(size.width * i / (mean.length - 1), size.height - size.height * v / maxV);
    final axis = Paint()
      ..color = Pal.line
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = size.height * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axis);
    }
    final band = Path()..moveTo(pt(0, hi[0]).dx, pt(0, hi[0]).dy);
    for (var i = 1; i < hi.length; i++) {
      band.lineTo(pt(i, hi[i]).dx, pt(i, hi[i]).dy);
    }
    for (var i = lo.length - 1; i >= 0; i--) {
      band.lineTo(pt(i, lo[i]).dx, pt(i, lo[i]).dy);
    }
    canvas.drawPath(band..close(), Paint()..color = Pal.signal.withValues(alpha: 0.45));
    final line = Path()..moveTo(pt(0, mean[0]).dx, pt(0, mean[0]).dy);
    for (var i = 1; i < mean.length; i++) {
      line.lineTo(pt(i, mean[i]).dx, pt(i, mean[i]).dy);
    }
    canvas.drawPath(line, Paint()
      ..color = Pal.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4);
    final tp = TextPainter(text: TextSpan(text: '${top.round()} kg', style: const TextStyle(fontSize: 11, color: Pal.inkSoft)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant _BandChart old) => old.series != series;
}
