import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analytics.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Comparateur A / B : A reprend les réglages de l'onglet Réglages,
/// B part de A avec les imprévus et réglages modifiés ci-dessous.
/// Les deux sont calculés par le moteur, rien n'est estimé dans l'app.
class ComparePanel extends StatefulWidget {
  const ComparePanel({super.key, required this.controls, required this.values, required this.events});
  final List<Map<String, dynamic>> controls;
  final Map<String, double> values;
  final Set<String> events;

  @override
  State<ComparePanel> createState() => _ComparePanelState();
}

class _ComparePanelState extends State<ComparePanel> {
  late final Set<String> _bEvents = {...widget.events};
  final Map<String, double> _over = {};
  List<ScenarioView>? _res;
  bool _running = false;

  Map<String, dynamic>? _control(String key) {
    for (final c in widget.controls) {
      if (c['key'] == key) return c;
    }
    return null;
  }

  Future<void> _addOverride() async {
    final free = {
      for (final c in widget.controls)
        if (!_over.containsKey(c['key'])) c['key'] as String: '${c['label']}',
    };
    if (free.isEmpty) return;
    final k = await pickOption<String>(context, 'Réglage à modifier pour B', free);
    if (k != null) setState(() => _over[k] = widget.values[k] ?? 0);
  }

  Future<void> _run() async {
    final s = context.read<Session>();
    setState(() => _running = true);
    try {
      final a = scenarioBody(widget.controls, widget.values, widget.events);
      final b = scenarioBody(widget.controls, {...widget.values, ..._over}, _bEvents);
      final j = await s.api.post('/api/scenarios/compare', {
        'inline': [
          {'name': 'Scénario A', ...a},
          {'name': 'Scénario B', ...b},
        ],
      }, 120);
      final list = parseScenarios(j);
      if (!mounted) return;
      if (list.length < 2) {
        toast(context, 'Réponse inattendue du serveur : deux scénarios attendus.', error: true);
      } else {
        setState(() => _res = list);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Comparateur stratégique'),
        Text(
          'Comparez vos réglages actuels (A) à une variante (B). Chaque scénario est calculé par le moteur.',
          style: body(13, c: Pal.inkSoft, h: 1.35),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Row(
            children: [
              _badge('A', Pal.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Situation actuelle', style: head(15)),
                    Text(
                      widget.events.isEmpty ? 'Réglages de l’onglet Réglages' : '${widget.events.length} imprévu(s) actif(s)',
                      style: body(12, c: Pal.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          color: Pal.primaryFixed.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [_badge('B', Pal.primaryDeep), const SizedBox(width: 12), Text('Variante à tester', style: head(15))]),
              const SizedBox(height: 14),
              Text('Imprévus ou décisions', style: body(12, w: FontWeight.w700, c: Pal.inkSoft)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in planEvents.entries)
                    FilterChip(
                      label: Text(e.value.label),
                      selected: _bEvents.contains(e.key),
                      onSelected: (v) => setState(() => v ? _bEvents.add(e.key) : _bEvents.remove(e.key)),
                      selectedColor: Pal.primaryFixed,
                      backgroundColor: Colors.white,
                      checkmarkColor: Pal.primaryDeep,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Réglages modifiés', style: body(12, w: FontWeight.w700, c: Pal.inkSoft)),
              for (final k in _over.keys.toList()) _overrideRow(k),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _addOverride,
                icon: const Icon(Icons.tune),
                label: const Text('Modifier un réglage'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.compare_arrows),
          label: Text(_running ? 'Calcul des deux scénarios…' : 'Comparer A et B'),
        ),
        if (_res != null) ..._table(_res!),
      ],
    );
  }

  Widget _badge(String t, Color c) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(11)),
    child: Text(t, style: head(16, c: Colors.white)),
  );

  Widget _overrideRow(String key) {
    final c = _control(key);
    if (c == null) return const SizedBox.shrink();
    final min = (c['min'] as num).toDouble();
    final max = (c['max'] as num).toDouble();
    final step = (c['step'] as num?)?.toDouble() ?? 1;
    final v = _over[key]!.clamp(min, max);
    final div = step > 0 ? ((max - min) / step).round() : 0;
    final unit = c['unit'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('${c['label']}', style: body(13, w: FontWeight.w600))),
            Text(
              '${numOut(v)}${unit == null || unit.isEmpty ? '' : ' $unit'}',
              style: body(12, w: FontWeight.w800, c: Pal.primaryDeep),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _over.remove(key)),
            ),
          ],
        ),
        Slider(
          value: v,
          min: min,
          max: max,
          divisions: div > 0 && div <= 400 ? div : null,
          activeColor: Pal.primary,
          onChanged: (x) => setState(() => _over[key] = x),
        ),
      ],
    );
  }

  List<Widget> _table(List<ScenarioView> r) {
    final a = r[0], b = r[1];
    final rows = [
      for (final e in metricDefs.entries)
        if (a.metrics.containsKey(e.key) || b.metrics.containsKey(e.key)) e,
    ];
    return [
      const SectionTitle('Résultat'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(flex: 5, child: SizedBox()),
                Expanded(flex: 3, child: Text('A', textAlign: TextAlign.end, style: head(13, c: Pal.inkSoft))),
                Expanded(flex: 3, child: Text('B', textAlign: TextAlign.end, style: head(13, c: Pal.primaryDeep))),
              ],
            ),
            const Divider(height: 14),
            for (final e in rows) _row(e.value, a.metrics[e.key], b.metrics[e.key]),
          ],
        ),
      ),
    ];
  }

  Widget _row(MetricDef d, double? a, double? b) {
    String? delta;
    Color dc = Pal.inkSoft;
    if (a != null && b != null && a != b) {
      final diff = (b - a) * d.scale;
      delta = '${diff > 0 ? '+' : '−'}${d.digits == 0 ? fmtInt(diff.abs()) : diff.abs().toStringAsFixed(d.digits)}${d.unit.isEmpty ? '' : ' ${d.unit}'}';
      dc = (diff > 0) == d.higherIsBetter ? Pal.primaryDeep : Pal.error;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: Text(d.label, style: body(13, w: FontWeight.w600, h: 1.25))),
          Expanded(
            flex: 3,
            child: Text(a == null ? '—' : d.format(a), textAlign: TextAlign.end, style: body(13, c: Pal.inkSoft)),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(b == null ? '—' : d.format(b), style: body(13, w: FontWeight.w800)),
                if (delta != null) Text(delta, style: body(11, w: FontWeight.w700, c: dc)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
