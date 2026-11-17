import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/theme.dart';

Future<bool?> showCandidateSheet(BuildContext context, Candidate c) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.ground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _CandidateSheet(c: c),
      ),
    );

enum _Mode { view, confirm, dismiss }

class _CandidateSheet extends StatefulWidget {
  const _CandidateSheet({required this.c});
  final Candidate c;

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  _Mode _mode = _Mode.view;
  String _size = 'medium';
  String? _reason;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final api = context.read<AppState>().api;
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == _Mode.confirm) {
        await api.post('/api/candidates/${widget.c.id}/confirm', {'size': _size});
      } else {
        await api.post('/api/candidates/${widget.c.id}/dismiss', {'reason': _reason, if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()});
      }
      nav.pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context).textTheme;
    final s = c.signals;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Pal.planned.withValues(alpha: (c.score / 8).clamp(0.25, 1.0)), shape: BoxShape.circle, border: Border.all(color: Pal.ink, width: 1.8)),
              child: Text(c.score.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Zone suspecte repérée sur image', style: t.titleLarge),
                Text('À vérifier sur place. ${c.merged > 0 ? '${c.merged + 1} détections regroupées.' : ''}', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Plate(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pourquoi cette zone', style: t.titleMedium),
              const SizedBox(height: 8),
              _Signal('Texture irrégulière', (s['texture_z'] ?? 0) / 10),
              _Signal('Peu de végétation', -(s['vegetation_z'] ?? 0) / 10),
              _Signal('Luminosité inhabituelle', (s['brightness_z'] ?? 0) / 10),
              _Signal('Zone à risque connue', (s['risk'] ?? 0)),
            ]),
          ),
          const SizedBox(height: 14),
          if (_mode == _Mode.view) ...[
            Text('Allez voir sur place, puis décidez.', style: t.bodyMedium?.copyWith(color: Pal.inkSoft)),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => setState(() => _mode = _Mode.confirm), child: const Text('Dépotoir confirmé')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => setState(() => _mode = _Mode.dismiss), child: const Text('Fausse alerte')),
          ],
          if (_mode == _Mode.confirm) ...[
            Text('Quelle taille ?', style: t.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final e in sizeLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {_size},
              onSelectionChanged: (v) => setState(() => _size = v.first),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Enregistrement…' : 'Créer le dépotoir vérifié')),
            TextButton(onPressed: () => setState(() => _mode = _Mode.view), child: const Text('Retour')),
          ],
          if (_mode == _Mode.dismiss) ...[
            Text('Pourquoi est-ce une fausse alerte ?', style: t.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rejectReasonLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _reason == e.key,
                  showCheckmark: false,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _reason == e.key ? Pal.surface : Pal.ink),
                  onSelected: (_) => setState(() => _reason = e.key),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Précision (facultatif)')),
            FilledButton(onPressed: _busy || _reason == null ? null : _send, child: Text(_busy ? 'Enregistrement…' : 'Rejeter ce candidat')),
            TextButton(onPressed: () => setState(() => _mode = _Mode.view), child: const Text('Retour')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Pal.dump, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _Signal extends StatelessWidget {
  const _Signal(this.label, this.value);
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 160, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 6, color: Pal.ink, backgroundColor: Pal.line))),
        ]),
      );
}
