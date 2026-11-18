import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

const kVoiceMaxSeconds = 60;

class VoiceClip {
  const VoiceClip(this.path, this.seconds);
  final String path;
  final int seconds;
}

String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

/// Enregistrement d'un mémo vocal joint au signalement (aucune transcription).
class VoiceNoteField extends StatefulWidget {
  const VoiceNoteField({super.key, required this.clip, required this.onChanged});
  final VoiceClip? clip;
  final ValueChanged<VoiceClip?> onChanged;

  @override
  State<VoiceNoteField> createState() => _VoiceNoteFieldState();
}

class _VoiceNoteFieldState extends State<VoiceNoteField> {
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  Timer? _timer;
  StreamSubscription<void>? _done;
  bool _recording = false;
  bool _playing = false;
  int _sec = 0;

  @override
  void initState() {
    super.initState();
    _done = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void didUpdateWidget(covariant VoiceNoteField old) {
    super.didUpdateWidget(old);
    if (old.clip != null && widget.clip == null && _playing) {
      _player.stop();
      _playing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _done?.cancel();
    _player.dispose();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) toast(context, context.trRead('voice.denied'), error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/memo-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 22050, numChannels: 1),
        path: path,
      );
      _sec = 0;
      if (!mounted) return;
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _sec++);
        if (_sec >= kVoiceMaxSeconds) _stop();
      });
    } catch (_) {
      if (mounted) toast(context, context.trRead('voice.error'), error: true);
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final secs = _sec;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (path != null && secs >= 1) widget.onChanged(VoiceClip(path, secs));
  }

  Future<void> _togglePlay() async {
    final c = widget.clip;
    if (c == null) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(c.path));
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _delete() async {
    final c = widget.clip;
    await _player.stop();
    if (mounted) setState(() => _playing = false);
    widget.onChanged(null);
    if (c != null) {
      try {
        await File(c.path).delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.clip;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _recording ? Pal.errorSoft : Pal.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic, color: _recording ? Pal.error : Pal.primaryDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('voice.title'), style: head(14, w: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _recording
                      ? _mmss(_sec)
                      : c != null
                      ? _mmss(c.seconds)
                      : context.tr('voice.hint'),
                  style: body(12, c: _recording ? Pal.error : Pal.inkSoft, w: _recording ? FontWeight.w800 : FontWeight.w400),
                ),
                if (!_recording && c == null)
                  Text(context.tr('voice.max', {'n': '$kVoiceMaxSeconds'}), style: body(11, c: Pal.outline)),
              ],
            ),
          ),
          if (_recording)
            IconButton.filled(
              onPressed: _stop,
              tooltip: context.tr('voice.stop'),
              style: IconButton.styleFrom(backgroundColor: Pal.error),
              icon: const Icon(Icons.stop_rounded),
            )
          else if (c != null) ...[
            IconButton(
              onPressed: _togglePlay,
              tooltip: context.tr('voice.listen'),
              icon: Icon(_playing ? Icons.pause_circle_outline : Icons.play_circle_outline, color: Pal.primaryDeep, size: 30),
            ),
            IconButton(
              onPressed: _delete,
              tooltip: context.tr('voice.delete'),
              icon: const Icon(Icons.delete_outline, color: Pal.inkSoft),
            ),
          ] else
            IconButton.filled(
              onPressed: _start,
              tooltip: context.tr('voice.record'),
              style: IconButton.styleFrom(backgroundColor: Pal.primary),
              icon: const Icon(Icons.fiber_manual_record, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Lecture d'un mémo hébergé sur le serveur.
class VoicePlayerTile extends StatefulWidget {
  const VoicePlayerTile({super.key, required this.url, this.seconds});
  final String url;
  final int? seconds;

  @override
  State<VoicePlayerTile> createState() => _VoicePlayerTileState();
}

class _VoicePlayerTileState extends State<VoicePlayerTile> {
  final _player = AudioPlayer();
  StreamSubscription<void>? _done;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _done = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
        if (mounted) setState(() => _playing = false);
      } else {
        await _player.play(UrlSource(widget.url));
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) toast(context, context.trRead('voice.error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Pal.primaryDeep, size: 34),
          ),
          Expanded(child: Text(context.tr('voice.verifier_title'), style: body(13, w: FontWeight.w600))),
          if (widget.seconds != null) Text(_mmss(widget.seconds!), style: body(12, c: Pal.inkSoft)),
        ],
      ),
    );
  }
}

/// Mémos vocaux des signalements d'un dépotoir (vérificateur, administrateur).
class DumpVoiceSection extends StatefulWidget {
  const DumpVoiceSection({super.key, required this.dumpId});
  final String dumpId;

  @override
  State<DumpVoiceSection> createState() => _DumpVoiceSectionState();
}

class _DumpVoiceSectionState extends State<DumpVoiceSection> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    try {
      final j = await s.api.get('/api/voice/by-dump/${Uri.encodeComponent(widget.dumpId)}');
      final list = ((j as Map)['items'] as List?) ?? [];
      if (mounted) setState(() => _items = [for (final e in list) Map<String, dynamic>.from(e as Map)]);
    } on ApiException {
      // route absente ou aucun mémo : on n'affiche rien
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final api = context.read<Session>().api;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          for (final it in _items)
            VoicePlayerTile(url: api.photoUrl('${it['file']}'), seconds: (it['duration_s'] as num?)?.toInt()),
        ],
      ),
    );
  }
}
