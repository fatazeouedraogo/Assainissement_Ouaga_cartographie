import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/models.dart';

String _money(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

class WeatherBanner extends StatefulWidget {
  const WeatherBanner({super.key, required this.onActivate});
  final VoidCallback onActivate;

  @override
  State<WeatherBanner> createState() => _WeatherBannerState();
}

class _WeatherBannerState extends State<WeatherBanner> {
  Map<String, dynamic>? _w;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().api.get('/api/insights/weather').then((j) {
      if (mounted) setState(() => _w = j as Map<String, dynamic>);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    if (w == null || w['available'] != true || w['rainy'] != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Plate(
        color: Pal.signal,
        child: Row(children: [
          const Icon(Icons.thunderstorm_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text('Fortes pluies annoncées : ${w['total_mm']} mm sur 7 jours, pic à ${w['peak_mm']} mm.', style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: widget.onActivate, child: const Text('Simuler')),
        ]),
      ),
    );
  }
}

class AskCard extends StatefulWidget {
  const AskCard({super.key});

  @override
  State<AskCard> createState() => _AskCardState();
}

class _AskCardState extends State<AskCard> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _answer;
  bool _isError = false;

  Future<void> _ask() async {
    final api = context.read<AppState>().api;
    if (_c.text.trim().length < 3) return;
    setState(() {
      _busy = true;
      _answer = null;
    });
    try {
      final j = await api.post('/api/insights/ask', {'question': _c.text.trim()});
      setState(() {
        _answer = j['answer'] as String;
        _isError = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _answer = e.message;
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Plate(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Posez votre question', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _c,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText: 'Et si on avait 3 camions de plus pendant la saison des pluies ?',
              suffixIcon: IconButton(onPressed: _busy ? null : _ask, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward)),
            ),
          ),
          if (_answer != null) ...[
            const SizedBox(height: 10),
            Text(_answer!, style: TextStyle(height: 1.4, fontWeight: FontWeight.w600, color: _isError ? Pal.dump : Pal.ink)),
          ],
        ]),
      );
}

class RecommendCard extends StatefulWidget {
  const RecommendCard({super.key, required this.params, required this.events});
  final Map<String, dynamic> params;
  final List<Map<String, dynamic>> events;

  @override
  State<RecommendCard> createState() => _RecommendCardState();
}

class _RecommendCardState extends State<RecommendCard> {
  List<dynamic>? _rank;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    final api = context.read<AppState>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await api.post('/api/insights/recommend', {'params': widget.params, 'events': widget.events});
      setState(() => _rank = j['ranking'] as List);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton(onPressed: _busy ? null : _run, child: Text(_busy ? 'Évaluation des réponses…' : 'Que faire face à cet aléa ?')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Pal.dump))),
      if (_rank != null) ...[
        const SizedBox(height: 10),
        for (var i = 0; i < _rank!.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Plate(
              color: i == 0 ? const Color(0xFFFBEFD0) : null,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (i == 0) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.star, size: 18, color: Pal.ink)),
                  Expanded(child: Text(_rank![i]['response'] as String, style: t.titleMedium)),
                ]),
                const SizedBox(height: 4),
                Text('Collecte ${(100 * (_rank![i]['collection_rate'] as num)).toStringAsFixed(1)} % (${(_rank![i]['gain_collection_pts'] as num) >= 0 ? '+' : ''}${_rank![i]['gain_collection_pts']} pts) · coût ${_money(_rank![i]['extra_cost_month'] as num)} de plus par mois${_rank![i]['within_budget'] == false ? ' · hors budget' : ''}', style: t.bodySmall),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class ParetoCard extends StatefulWidget {
  const ParetoCard({super.key, required this.params});
  final Map<String, dynamic> params;

  @override
  State<ParetoCard> createState() => _ParetoCardState();
}

class _ParetoCardState extends State<ParetoCard> {
  List<dynamic>? _pts;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    final api = context.read<AppState>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await api.post('/api/insights/pareto', {'params': widget.params});
      setState(() => _pts = j['points'] as List);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton(onPressed: _busy ? null : _run, child: Text(_busy ? 'Exploration des compromis…' : 'Voir les compromis coût, fuites et équité')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Pal.dump))),
      if (_pts != null) ...[
        const SizedBox(height: 10),
        Plate(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chaque point est un plan possible', style: t.titleMedium),
            Text('Plus bas à gauche, c’est mieux : moins cher et moins de fuites. Les points pleins ne sont battus par aucun autre plan.', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
            const SizedBox(height: 10),
            SizedBox(height: 190, width: double.infinity, child: CustomPaint(painter: _ParetoPainter(_pts!))),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Coût mensuel →', style: t.bodySmall), Text('↑ fuites', style: t.bodySmall)]),
          ]),
        ),
        const SizedBox(height: 8),
        for (final p in _pts!.where((p) => p['pareto'] == true))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${p['trucks']} camions · passage tous les ${p['frequency_days']} j · priorité périphérie ${p['equity_boost']} : ${_money(p['cost'] as num)}, fuites ${(100 * (p['leakage'] as num)).toStringAsFixed(1)} %, équité ${(100 * (p['equity'] as num)).round()} %', style: t.bodySmall),
          ),
      ],
    ]);
  }
}

class _ParetoPainter extends CustomPainter {
  _ParetoPainter(this.pts);
  final List<dynamic> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = pts.map((p) => (p['cost'] as num).toDouble()).toList();
    final ys = pts.map((p) => (p['leakage'] as num).toDouble()).toList();
    final x0 = xs.reduce((a, b) => a < b ? a : b), x1 = xs.reduce((a, b) => a > b ? a : b);
    final y0 = ys.reduce((a, b) => a < b ? a : b), y1 = ys.reduce((a, b) => a > b ? a : b);
    final dx = (x1 - x0) == 0 ? 1.0 : x1 - x0, dy = (y1 - y0) == 0 ? 1.0 : y1 - y0;
    final axis = Paint()
      ..color = Pal.line
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, axis..style = PaintingStyle.stroke);
    for (final p in pts) {
      final x = 14 + (size.width - 28) * (((p['cost'] as num) - x0) / dx);
      final y = size.height - 14 - (size.height - 28) * (((p['leakage'] as num) - y0) / dy);
      final eq = (p['equity'] as num).toDouble().clamp(0.0, 1.0);
      final fill = Color.lerp(Pal.dump, Pal.cleaned, eq)!;
      final on = p['pareto'] == true;
      canvas.drawCircle(Offset(x, y), on ? 9 : 6, Paint()..color = on ? fill : fill.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(x, y), on ? 9 : 6, Paint()
        ..color = Pal.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 1.8 : 1);
    }
  }

  @override
  bool shouldRepaint(covariant _ParetoPainter old) => old.pts != pts;
}

class PdfButton extends StatefulWidget {
  const PdfButton({super.key});

  @override
  State<PdfButton> createState() => _PdfButtonState();
}

class _PdfButtonState extends State<PdfButton> {
  bool _busy = false;

  Future<void> _go() async {
    final api = context.read<AppState>().api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await api.postBytes('/api/insights/report.pdf');
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/note-de-decision.pdf');
      await f.writeAsBytes(bytes);
      messenger.showSnackBar(SnackBar(content: Text('Note enregistrée : ${f.path}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: _busy ? null : _go, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(_busy ? 'Création…' : 'Note PDF pour le maire'));
}


class DetectionStatsCard extends StatefulWidget {
  const DetectionStatsCard({super.key});

  @override
  State<DetectionStatsCard> createState() => _DetectionStatsCardState();
}

class _DetectionStatsCardState extends State<DetectionStatsCard> {
  Map<String, dynamic>? _s;
  double _min = 1.5;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await context.read<AppState>().api.get('/api/candidates/stats') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _s = j;
          _min = ((j['current'] as Map)['min_score'] as num).toDouble().clamp(0.0, 10.0);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _apply() async {
    final api = context.read<AppState>().api;
    final cur = _s!['current'] as Map;
    setState(() => _busy = true);
    try {
      await api.put('/api/settings/detection', {'min_score': double.parse(_min.toStringAsFixed(1)), 'merge_m': cur['merge_m'], 'risk_weight': cur['risk_weight']});
      await _load();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = _s;
    if (s == null) return _error == null ? const SizedBox.shrink() : Text(_error!, style: const TextStyle(color: Pal.dump));
    final isAdmin = context.read<AppState>().user?.role == 'admin';
    final precision = s['precision'] as num?;
    final suggested = s['suggested_threshold'] as num?;
    return Plate(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Précision de la détection', style: t.titleMedium),
        const SizedBox(height: 6),
        Text(precision == null ? 'Aucun candidat vérifié sur le terrain pour le moment.' : '${s['confirmed']} confirmés sur ${s['reviewed']} vérifiés : ${(precision * 100).round()} % de bonnes alertes', style: t.titleLarge?.copyWith(fontSize: 18)),
        Text('${s['pending']} candidat(s) en attente de vérification', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
        if (s['note'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${s['note']}', style: t.bodySmall?.copyWith(color: Pal.dump, fontWeight: FontWeight.w700))),
        if ((s['reject_reasons'] as Map).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Fausses alertes : ${(s['reject_reasons'] as Map).entries.map((e) => '${rejectReasonLabels[e.key] ?? e.key} (${e.value})').join(', ')}', style: t.bodySmall),
        ],
        const SizedBox(height: 10),
        for (final r in (s['thresholds'] as List).where((r) => r['reviewed'] > 0))
          Text('Score ≥ ${r['threshold']} : ${r['confirmed']}/${r['reviewed']} confirmés${r['precision'] == null ? '' : ' (${((r['precision'] as num) * 100).round()} %)'}', style: t.bodySmall),
        if (suggested != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Seuil conseillé : $suggested', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
        if (isAdmin) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('Seuil minimal'),
            Expanded(child: Slider(value: _min, min: 0, max: 10, divisions: 100, label: _min.toStringAsFixed(1), onChanged: (v) => setState(() => _min = v))),
            Text(_min.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          OutlinedButton(onPressed: _busy ? null : _apply, child: Text(_busy ? 'Application…' : 'Appliquer ce seuil aux prochaines analyses')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Pal.dump))),
      ]),
    );
  }
}
