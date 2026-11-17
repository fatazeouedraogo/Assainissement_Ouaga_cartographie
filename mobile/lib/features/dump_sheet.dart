import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'map_screen.dart' show statusColor;

void showDumpSheet(BuildContext context, Dump d) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pal.ground,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (ctx, ctl) => _DumpSheet(dump: d, controller: ctl),
    ),
  );
}

class _DumpSheet extends StatefulWidget {
  const _DumpSheet({required this.dump, required this.controller});
  final Dump dump;
  final ScrollController controller;

  @override
  State<_DumpSheet> createState() => _DumpSheetState();
}

class _DumpSheetState extends State<_DumpSheet> {
  Map<String, dynamic>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await context.read<AppState>().api.get('/api/dumps/${widget.dump.id}');
      if (mounted) setState(() => _detail = j as Map<String, dynamic>);
    } on ApiException catch (_) {}
  }

  Future<void> _act(Future<void> Function(Api api) run) async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await run(s.api);
      await s.refreshDumps();
      nav.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 120)));
    if (date == null) return;
    final iso = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _act((api) => api.post('/api/dumps/${widget.dump.id}/schedule', {'date': iso}));
  }

  Future<void> _clean() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
    if (shot == null) return;
    await _act((api) => api.multipart('/api/dumps/${widget.dump.id}/clean', {}, filePath: shot.path));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dump;
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final comps = (_detail?['detail'] as Map?)?['contributions'] as Map?;
    final reports = (_detail?['reports'] as List?) ?? const [];
    return ListView(controller: widget.controller, padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
      Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MoundGlyph(level: d.sizeLevel, color: statusColor(d.status), size: 58, ring: d.recurrence),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusLabels[d.status] ?? d.status, style: t.titleLarge),
            Text('${sizeLabels[d.size]} · ${wasteLabels[d.wasteType]} · ~${d.estKg.round()} kg', style: t.bodyMedium?.copyWith(color: Pal.inkSoft)),
            if (d.recurrence) Text('Récidive : ce lieu avait déjà été nettoyé', style: t.bodyMedium?.copyWith(color: Pal.dump, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      if (d.beforePhoto != null || d.afterPhoto != null)
        Row(children: [
          if (d.beforePhoto != null) Expanded(child: _Photo(url: s.api.photoUrl(d.beforePhoto), caption: 'Avant')),
          if (d.afterPhoto != null) ...[const SizedBox(width: 8), Expanded(child: _Photo(url: s.api.photoUrl(d.afterPhoto), caption: 'Après'))],
        ]),
      const SizedBox(height: 16),
      Plate(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Priorité sanitaire', style: t.titleMedium),
            const Spacer(),
            Text('${d.priority.round()}/100', style: t.titleLarge),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: d.priority / 100, minHeight: 10, color: d.priority >= 60 ? Pal.dump : Pal.pending, backgroundColor: Pal.line)),
          const SizedBox(height: 10),
          if (d.driver != null) Text('Pourquoi : ${driverLabels[d.driver] ?? d.driver}', style: t.bodyMedium),
          if (comps != null) ...[
            const SizedBox(height: 10),
            for (final e in comps.entries) _Bar(label: _short(e.key as String), value: (e.value as num).toDouble()),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Plate(
        child: Row(children: [
          Expanded(child: _Stat('${(d.confidence * 100).round()} %', 'confiance')),
          Expanded(child: _Stat('${d.reporters}', d.reporters > 1 ? 'personnes ont signalé' : 'personne a signalé')),
          if (d.scheduledFor != null) Expanded(child: _Stat(d.scheduledFor!.substring(0, 10), 'passage prévu')),
        ]),
      ),
      if (reports.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Signalements', style: t.titleMedium),
        const SizedBox(height: 6),
        for (final r in reports.take(6))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${r['author']}'),
            subtitle: Text('${sizeLabels[r['size']]} · crédibilité ${((r['credibility'] as num) * 100).round()} %'),
            trailing: ((r['flags'] as List).isNotEmpty) ? const Icon(Icons.flag, color: Pal.pending, size: 18) : null,
          ),
      ],
      if (s.user!.isStaff) ...[
        const SizedBox(height: 18),
        if (d.status == 'pending') FilledButton(onPressed: _busy ? null : () => _act((api) => api.post('/api/dumps/${d.id}/verify')), child: const Text('Confirmer le dépotoir')),
        if (d.status == 'verified' || d.status == 'scheduled') ...[
          OutlinedButton(onPressed: _busy ? null : _schedule, child: Text(d.status == 'scheduled' ? 'Changer la date de passage' : 'Programmer un passage')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _clean, child: const Text('Clôturer avec photo après nettoyage')),
        ],
      ],
    ]);
  }

  String _short(String k) => const {'size': 'Volume', 'age': 'Ancienneté', 'water': 'Eau', 'sensitive': 'Lieux sensibles'}[k] ?? k;
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.caption});
  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Pal.line, child: const Icon(Icons.broken_image_outlined))),
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: (value / 30).clamp(0, 1), minHeight: 6, color: Pal.ink, backgroundColor: Pal.line))),
          SizedBox(width: 38, child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
      ]);
}
