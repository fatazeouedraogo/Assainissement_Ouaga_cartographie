import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  XFile? _photo;
  Position? _pos;
  String _locMsg = 'Recherche de votre position…';
  String _size = 'medium';
  String _type = 'household';
  final _note = TextEditingController();
  bool _busy = false;
  final _speech = stt.SpeechToText();
  bool _listening = false;

  Future<void> _dictate() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(onStatus: (s) {
      if (s == 'done' && mounted) setState(() => _listening = false);
    });
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dictée indisponible sur ce téléphone')));
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(localeId: 'fr_FR', onResult: (r) => setState(() => _note.text = r.recognizedWords));
  }

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _pos = null;
      _locMsg = 'Recherche de votre position…';
    });
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _locMsg = 'Activez la localisation du téléphone');
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _locMsg = 'Localisation refusée. Autorisez-la dans les réglages.');
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)));
      if (mounted) setState(() => _pos = p);
    } catch (_) {
      if (mounted) setState(() => _locMsg = 'Position introuvable. Sortez à découvert puis réessayez.');
    }
  }

  Future<void> _shoot() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
    if (x != null) setState(() => _photo = x);
  }

  Future<void> _send() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final r = await s.submitReport(
        lat: _pos!.latitude,
        lon: _pos!.longitude,
        accuracy: _pos!.accuracy,
        size: _size,
        wasteType: _type,
        photoPath: _photo!.path,
        note: _note.text,
      );
      if (!mounted) return;
      await _showResult(r);
      if (r.status != 'rejected') nav.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fields.isNotEmpty ? e.fields.join(', ') : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(SubmitResult r) {
    String title;
    final lines = <String>[];
    if (r.queued) {
      title = 'Enregistré sur le téléphone';
      lines.add('Pas de réseau pour le moment. Le signalement partira tout seul dès que la connexion reviendra.');
    } else if (r.status == 'rejected') {
      title = 'Signalement refusé';
      lines.addAll(r.rejects.map((c) => rejectLabels[c] ?? c));
    } else {
      title = r.status == 'flagged' ? 'Reçu, à contrôler' : 'Signalement reçu';
      if (r.points > 0) lines.add('+${r.points} points');
      if (r.reporters > 1) lines.add('${r.reporters} personnes ont signalé ce lieu.');
      if (r.dumpStatus == 'verified') lines.add('Le dépotoir est confirmé.');
      lines.addAll(r.flags.map((f) => flagLabels[f] ?? f));
    }
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l))]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ready = _photo != null && _pos != null && !_busy;
    final acc = _pos?.accuracy;
    return Scaffold(
      appBar: AppBar(title: Text(tr('report_title'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        InkWell(
          onTap: _shoot,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 210,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Pal.ink, width: 1.6)),
            child: _photo == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.photo_camera_outlined, size: 40),
                    const SizedBox(height: 8),
                    Text(tr('take_photo'), style: t.titleMedium),
                    Text(tr('frame_hint'), style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
                  ])
                : Stack(fit: StackFit.expand, children: [
                    Image.file(File(_photo!.path), fit: BoxFit.cover),
                    const Positioned(right: 8, bottom: 8, child: CircleAvatar(backgroundColor: Pal.signal, foregroundColor: Pal.ink, child: Icon(Icons.refresh))),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        Plate(
          child: Row(children: [
            Icon(_pos == null ? Icons.gps_not_fixed : Icons.gps_fixed, color: _pos == null ? Pal.inkSoft : acc! <= 30 ? Pal.cleaned : Pal.pending),
            const SizedBox(width: 10),
            Expanded(
              child: _pos == null
                  ? Text(_locMsg)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}', style: t.titleMedium),
                      Text(acc! <= 30 ? 'Position précise (±${acc.round()} m)' : 'Position approximative (±${acc.round()} m). Sortez à découvert pour mieux la fixer.', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
                    ]),
            ),
            IconButton(onPressed: _locate, icon: const Icon(Icons.refresh)),
          ]),
        ),
        const SizedBox(height: 20),
        Text(tr('which_size'), style: t.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          for (final e in const ['small', 'medium', 'large'])
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: e == 'large' ? 0 : 8),
                child: InkWell(
                  onTap: () => setState(() => _size = e),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: _size == e ? Pal.signal : Pal.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _size == e ? Pal.ink : Pal.line, width: _size == e ? 1.8 : 1),
                    ),
                    child: Column(children: [
                      MoundGlyph(level: e == 'small' ? 0 : e == 'medium' ? 1 : 2, color: Pal.surface, size: 52),
                      const SizedBox(height: 4),
                      Text(sizeLabels[e]!, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(sizeHints[e]!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.2)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Text(tr('which_type'), style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in wasteLabels.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _type == e.key,
              showCheckmark: false,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _type == e.key ? Pal.surface : Pal.ink),
              onSelected: (_) => setState(() => _type = e.key),
            ),
        ]),
        const SizedBox(height: 20),
        TextField(controller: _note, maxLength: 300, maxLines: 2, decoration: InputDecoration(labelText: 'Précision (facultatif)', hintText: 'Près du marché, côté caniveau…', suffixIcon: IconButton(tooltip: 'Dicter', onPressed: _dictate, icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Pal.dump : Pal.ink)))),
        const SizedBox(height: 12),
        FilledButton(onPressed: ready ? _send : null, child: Text(_busy ? tr('sending') : tr('send_report'))),
        if (!ready && !_busy) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_photo == null ? 'Prenez d’abord la photo.' : 'En attente de la position.', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: Pal.inkSoft))),
      ]),
    );
  }
}
