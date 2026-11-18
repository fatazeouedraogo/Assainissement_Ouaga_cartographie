import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'voice_note.dart';

Future<bool> showDumpSheet(BuildContext context, Dump d) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => DumpSheet(d),
  );
  return changed == true;
}

class DumpSheet extends StatefulWidget {
  const DumpSheet(this.d, {super.key});
  final Dump d;

  @override
  State<DumpSheet> createState() => _DumpSheetState();
}

class _DumpSheetState extends State<DumpSheet> {
  bool _busy = false;

  Future<void> _act(Future<dynamic> Function(Session s) call, String ok) async {
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

  Future<void> _reject() async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Motif du rejet', style: head(17)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'Ex. photo sans rapport, tas déjà évacué'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => c.text.trim().length >= 3 ? Navigator.pop(ctx, c.text.trim()) : null,
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _act(
      (s) => s.api.post('/api/dumps/${widget.d.id}/reject', {'reason': reason}),
      'Signalement rejeté',
    );
  }

  Future<void> _schedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
    );
    if (date == null || !mounted) return;
    final iso =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _act(
      (s) => s.api.post('/api/dumps/${widget.d.id}/schedule', {'date': iso}),
      'Passage programmé le ${fmtDate(iso)}',
    );
  }

  Future<void> _clean() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
    if (f == null || !mounted) return;
    await _act(
      (s) => s.api.upload('/api/dumps/${widget.d.id}/clean', {}, filePath: f.path),
      'Dépotoir clôturé',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final s = context.watch<Session>();
    final api = s.api;
    final photos = [
      if (d.beforePhoto != null) ('Avant', d.beforePhoto!),
      if (d.afterPhoto != null) ('Après', d.afterPhoto!),
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              Pill(
                statusLabels[d.status] ?? d.status,
                color: statusColor(d.status),
                bg: statusColor(d.status).withValues(alpha: 0.14),
              ),
              const SizedBox(width: 8),
              if (d.recurrence) const Pill('Récidive', color: Pal.tertiaryDeep, bg: Pal.tertiaryFixed),
              const Spacer(),
              Text(
                '${d.lat.toStringAsFixed(4)}, ${d.lon.toStringAsFixed(4)}',
                style: body(12, c: Pal.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${sizeLabels[d.size] ?? d.size} dépotoir · ${wasteLabels[d.waste] ?? d.waste}',
            style: head(21),
          ),
          const SizedBox(height: 4),
          Text('Environ ${fmtKg(d.kg)} · ${d.reporters} signalement(s)', style: body(14, c: Pal.inkSoft)),
          if (d.priority > 0) ...[
            const SizedBox(height: 16),
            AppCard(
              color: Pal.container,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(d.priority.round().toString(), style: head(30, c: Pal.error)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Priorité sanitaire${d.level != null ? ' · ${d.level}' : ''}', style: head(14)),
                        if (d.driver != null) Text(d.driver!, style: body(12, c: Pal.inkSoft, h: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (d.scheduledFor != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event_outlined, size: 18, color: Pal.secondary),
                const SizedBox(width: 8),
                Text('Passage prévu le ${fmtDate(d.scheduledFor)}', style: body(14, w: FontWeight.w600)),
              ],
            ),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (final p in photos)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              api.photoUrl(p.$2),
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 130,
                                color: Pal.container,
                                child: const Icon(Icons.broken_image_outlined, color: Pal.outline),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.$1,
                            style: body(12, w: FontWeight.w700, c: Pal.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (s.isStaff) DumpVoiceSection(dumpId: d.id),
          if (s.isStaff) ...[
            const SizedBox(height: 20),
            if (d.status == 'pending') ...[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _act((x) => x.api.post('/api/dumps/${d.id}/verify'), 'Dépotoir confirmé'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Confirmer le dépotoir'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reject,
                icon: const Icon(Icons.close, color: Pal.error),
                label: const Text('Rejeter'),
              ),
            ],
            if (d.status == 'verified' || d.status == 'scheduled') ...[
              FilledButton.icon(
                onPressed: _busy ? null : _schedule,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(d.status == 'scheduled' ? 'Changer la date de passage' : 'Programmer un passage'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _clean,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Clôturer avec photo après'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
