import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

Future<bool> showCandidateSheet(BuildContext context, Candidate c) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => CandidateSheet(c),
  );
  return changed == true;
}

class CandidateSheet extends StatefulWidget {
  const CandidateSheet(this.c, {super.key});
  final Candidate c;

  @override
  State<CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<CandidateSheet> {
  bool _busy = false;

  Future<void> _run(Future<dynamic> Function(Session s) call, String ok) async {
    final s = context.read<Session>();
    setState(() => _busy = true);
    try {
      await call(s);
      if (mounted) {
        toast(context, ok);
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final size = await pickOption<String>(context, 'Taille du dépotoir constaté', sizeLabels);
    if (size == null || !mounted) return;
    await _run(
      (s) => s.api.post('/api/candidates/${widget.c.id}/confirm', {'size': size}),
      'Dépotoir confirmé et ajouté',
    );
  }

  Future<void> _dismiss() async {
    final reason = await pickOption<String>(
      context,
      'Pourquoi est-ce une fausse alerte ?',
      rejectReasonLabels,
    );
    if (reason == null || !mounted) return;
    await _run(
      (s) => s.api.post('/api/candidates/${widget.c.id}/dismiss', {'reason': reason}),
      'Fausse alerte enregistrée',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final entries = c.signals.entries.where((e) => e.value is num).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(9)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Pill('Détecté par satellite', color: Pal.secondary, bg: Pal.secondaryFixed),
                const Spacer(),
                Text(
                  '${c.lat.toStringAsFixed(4)}, ${c.lon.toStringAsFixed(4)}',
                  style: body(12, c: Pal.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Zone suspecte', style: head(21)),
            const SizedBox(height: 4),
            Text(
              'Score de détection ${c.score.toStringAsFixed(1)}. À confirmer sur le terrain.',
              style: body(14, c: Pal.inkSoft, h: 1.35),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in entries)
                    Pill(
                      '${e.key} ${(e.value as num).toStringAsFixed(2)}',
                      color: Pal.inkSoft,
                      bg: Pal.container,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Dépotoir confirmé'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _dismiss,
              icon: const Icon(Icons.close, color: Pal.error),
              label: const Text('Fausse alerte'),
            ),
          ],
        ),
      ),
    );
  }
}
