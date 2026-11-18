import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// Courbes de la simulation multi-agents, telles que renvoyées par
/// `simulation.series` après le calcul du plan.
class SimulationPanel extends StatefulWidget {
  const SimulationPanel({super.key, required this.result});
  final Map<String, dynamic>? result;

  @override
  State<SimulationPanel> createState() => _SimulationPanelState();
}

class _SimulationPanelState extends State<SimulationPanel> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: EmptyState(
          Icons.show_chart,
          'Pas encore de simulation',
          'Calculez un plan dans l’onglet Réglages pour voir l’évolution jour après jour.',
        ),
      );
    }
    final sim = r['simulation'] is Map ? r['simulation'] as Map : const {};
    final data = parseSimSeries(sim['series']);
    final summary = sim['summary'] is Map ? sim['summary'] as Map : const {};
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: EmptyState(
          Icons.show_chart,
          'Aucune courbe renvoyée',
          'Le moteur n’a pas fourni de série temporelle pour ce plan.',
        ),
      );
    }
    if (_sel >= data.series.length) _sel = 0;
    final s = data.series[_sel];
    final horizon = data.days.last.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Évolution sur $horizon jours', trailing: Pill('Simulation multi-agents', color: Pal.secondary, bg: Pal.secondaryFixed)),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < data.series.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(data.series[i].label),
                    selected: _sel == i,
                    onSelected: (_) => setState(() => _sel = i),
                    selectedColor: Pal.primaryFixed,
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(8, 16, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: Text(s.label, style: head(15)),
              ),
              BandChart(days: data.days, mean: s.mean, lo: s.lo, hi: s.hi),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 0, 0),
                child: Row(
                  children: [
                    Container(width: 18, height: 4, decoration: BoxDecoration(color: Pal.primaryDeep, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Text('Moyenne', style: body(11, c: Pal.inkSoft)),
                    if (s.hasBand) ...[
                      const SizedBox(width: 14),
                      Container(width: 18, height: 10, decoration: BoxDecoration(color: Pal.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Text('Marge d’incertitude', style: body(11, c: Pal.inkSoft)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(child: _tile('Début', s.mean.first)),
              const SizedBox(width: 10),
              Expanded(child: _tile('Fin', s.mean.last)),
              const SizedBox(width: 10),
              Expanded(child: _tile('Écart', s.mean.last - s.mean.first, signed: true)),
            ],
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SectionTitle('Bilan de la simulation'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              for (final e in metricDefs.entries)
                if (statOf(summary[e.key]) != null) Kpi(e.value.format(statOf(summary[e.key])!), e.value.label),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tile(String label, double v, {bool signed = false}) {
    final txt = (signed && v > 0 ? '+' : '') + (v.abs() >= 100 ? fmtInt(v) : v.toStringAsFixed(1));
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: body(11, c: Pal.inkSoft)),
          const SizedBox(height: 2),
          Text(txt, style: head(17)),
        ],
      ),
    );
  }
}
