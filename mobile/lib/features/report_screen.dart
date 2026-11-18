import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'voice_note.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _picker = ImagePicker();
  final _note = TextEditingController();
  XFile? _photo;
  Position? _pos;
  String? _gpsError;
  bool _locating = false;
  bool _busy = false;
  bool _flood = false;
  String _size = 'small';
  String _waste = 'mixed';
  Map<String, dynamic>? _result;
  VoiceClip? _clip;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final l = context.read<Lang>();
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw l.t('report.gps.off');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw l.t('report.gps.denied');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) setState(() => _pos = p);
    } catch (e) {
      if (mounted) setState(() => _gpsError = e is String ? e : l.t('report.gps.notfound'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _take(ImageSource src) async {
    try {
      final f = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 82);
      if (f != null && mounted) setState(() => _photo = f);
    } catch (_) {
      if (mounted) toast(context, context.trRead('report.err.camera'), error: true);
    }
  }

  String _coords(Position p) =>
      '${p.latitude.abs().toStringAsFixed(4)}° ${p.latitude >= 0 ? 'N' : 'S'}, ${p.longitude.abs().toStringAsFixed(4)}° ${p.longitude >= 0 ? 'E' : 'O'}';

  Future<void> _send() async {
    if (_photo == null) return toast(context, context.trRead('report.err.photo'), error: true);
    if (_pos == null) return toast(context, context.trRead('report.err.gps'), error: true);
    final s = context.read<Session>();
    final note = [
      if (_flood) '[Zone inondable / caniveau]',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ].join(' ');
    final fields = <String, String>{
      'client_id': const Uuid().v4(),
      'lat': _pos!.latitude.toStringAsFixed(6),
      'lon': _pos!.longitude.toStringAsFixed(6),
      'accuracy_m': _pos!.accuracy.toStringAsFixed(0),
      'size': _size,
      'waste_type': _waste,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      if (note.isNotEmpty) 'note': note,
    };
    final clip = _clip;
    setState(() => _busy = true);
    try {
      final j = await s.api.upload('/api/reports', fields, filePath: _photo!.path) as Map;
      s.addPoints((j['points_awarded'] as num?)?.toInt() ?? 0);
      var voicePending = false;
      if (clip != null) {
        try {
          await s.api.upload(
            '/api/voice',
            {'client_id': fields['client_id']!, 'duration_s': '${clip.seconds}'},
            filePath: clip.path,
            field: 'audio',
          );
        } on ApiException catch (e) {
          if (e.network || e.status >= 500 || e.status == 401 || e.status == 408 || e.status == 429) {
            await s.outbox.addAudioOnly(fields['client_id']!, clip.path, clip.seconds);
            await s.noteQueued();
            voicePending = true;
          }
        }
      }
      if (clip != null) _deleteQuietly(clip.path);
      if (mounted) {
        setState(() {
          _result = {...Map<String, dynamic>.from(j), if (voicePending) 'voice_pending': true};
          _photo = null;
          _clip = null;
          _note.clear();
          _flood = false;
        });
      }
    } on ApiException catch (e) {
      if (e.network || e.status >= 500) {
        await s.outbox.add(fields, _photo!.path, audioPath: clip?.path, audioSeconds: clip?.seconds ?? 0);
        await s.noteQueued();
        if (clip != null) _deleteQuietly(clip.path);
        if (mounted) {
          setState(() {
            _photo = null;
            _clip = null;
            _note.clear();
            _flood = false;
            _result = {'queued': true};
          });
        }
      } else if (mounted) {
        toast(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _deleteQuietly(String path) {
    File(path).delete().catchError((_) => File(path));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(context.tr('report.title'), style: head(26)),
        const SizedBox(height: 2),
        Text(context.tr('report.subtitle'), style: body(14, c: Pal.inkSoft)),
        if (_result != null) ...[
          const SizedBox(height: 14),
          _ResultCard(_result!, onClose: () => setState(() => _result = null)),
        ],
        const SizedBox(height: 16),
        _photoCard(),
        const SizedBox(height: 14),
        _gpsCard(),
        const SizedBox(height: 14),
        VoiceNoteField(clip: _clip, onChanged: (c) => setState(() => _clip = c)),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Pal.secondaryFixed, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.flood_outlined, color: Pal.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('report.flood.title'), style: head(14, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(context.tr('report.flood.hint'), style: body(12, c: Pal.inkSoft)),
                  ],
                ),
              ),
              Switch(
                value: _flood,
                activeTrackColor: Pal.primary,
                onChanged: (v) => setState(() => _flood = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(context.tr('report.size.title'), style: head(17)),
        const SizedBox(height: 10),
        _sizeRow(
          'small',
          Icons.shopping_bag_outlined,
          Pal.primaryDeep,
          Pal.primaryFixed,
          context.tr('report.size.small'),
          context.tr('report.size.small.hint'),
        ),
        const SizedBox(height: 8),
        _sizeRow(
          'medium',
          Icons.shopping_cart_outlined,
          Pal.tertiaryDeep,
          Pal.tertiaryFixed,
          context.tr('report.size.medium'),
          context.tr('report.size.medium.hint'),
        ),
        const SizedBox(height: 8),
        _sizeRow(
          'large',
          Icons.warning_amber_rounded,
          Pal.error,
          Pal.errorSoft,
          context.tr('report.size.large'),
          context.tr('report.size.large.hint'),
        ),
        const SizedBox(height: 20),
        Text(context.tr('report.waste.title'), style: head(17)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in wasteLabels.entries)
              ChoiceChip(
                label: Text(context.tr('waste.${e.key}')),
                selected: _waste == e.key,
                onSelected: (_) => setState(() => _waste = e.key),
                selectedColor: Pal.primaryFixed,
                backgroundColor: Colors.white,
                side: BorderSide(color: _waste == e.key ? Pal.primary : Pal.line),
                labelStyle: body(
                  13,
                  w: FontWeight.w700,
                  c: _waste == e.key ? Pal.onPrimaryFixed : Pal.inkSoft,
                ),
                showCheckmark: false,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _note,
          maxLength: 300,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: context.tr('report.note.label'),
            hintText: context.tr('report.note.hint'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 20),
          label: Text(context.tr(_busy ? 'report.sending' : 'report.send')),
        ),
      ],
    );
  }

  Widget _photoCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_a_photo_outlined, color: Pal.primaryDeep, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr('report.photo.title'), style: head(16))),
              _photo == null
                  ? Pill(context.tr('report.required'), color: const Color(0xFF991B1B), bg: Pal.errorSoft)
                  : Pill(context.tr('report.added')),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _take(ImageSource.camera),
            child: Container(
              height: 190,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(16)),
              child: _photo == null
                  ? Stack(
                      children: [
                        Positioned.fill(child: CustomPaint(painter: _FramePainter())),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.center_focus_weak, color: Colors.white54, size: 44),
                              const SizedBox(height: 8),
                              Text(context.tr('report.photo.hint'), style: body(14, c: Colors.white70)),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 12,
                          child: Text(
                            context.tr('report.photo.none'),
                            style: body(13, w: FontWeight.w600, c: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_photo!.path), fit: BoxFit.cover),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: CircleAvatar(
                            backgroundColor: Pal.primary,
                            foregroundColor: Colors.white,
                            child: const Icon(Icons.refresh),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 6,
                child: FilledButton.icon(
                  onPressed: () => _take(ImageSource.camera),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: Text(context.tr('report.photo.take')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: FilledButton.tonalIcon(
                  onPressed: () => _take(ImageSource.gallery),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Pal.container,
                    foregroundColor: Pal.ink,
                  ),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: Text(context.tr('report.photo.gallery', {'n': _photo == null ? '0' : '1'})),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gpsCard() {
    final p = _pos;
    final good = p != null && p.accuracy <= 30;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Pal.primaryDeep, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr('report.gps.title'), style: head(16))),
              if (p != null)
                Pill(
                  '± ${p.accuracy.round()} m',
                  color: good ? Pal.onPrimaryFixed : Pal.tertiaryDeep,
                  bg: good ? Pal.primaryFixed : Pal.tertiaryFixed,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _locating
                        ? context.tr('report.gps.searching')
                        : (p == null ? (_gpsError ?? context.tr('report.gps.unknown')) : _coords(p)),
                    style: p == null
                        ? body(14, c: _gpsError != null ? Pal.error : Pal.inkSoft, h: 1.3)
                        : head(18),
                  ),
                ),
                if (p != null)
                  Icon(good ? Icons.verified : Icons.info_outline, color: good ? Pal.primary : Pal.tertiary),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 130,
              child: Stack(
                children: [
                  if (p != null)
                    FlutterMap(
                      key: ValueKey('${p.latitude}${p.longitude}'),
                      options: MapOptions(
                        initialCenter: LatLng(p.latitude, p.longitude),
                        initialZoom: 17,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'bf.ouagaclean.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(p.latitude, p.longitude),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin, color: Pal.primaryDeep, size: 40),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Container(
                      color: const Color(0xFFCFE0E3),
                      child: const Center(
                        child: Icon(Icons.location_searching, color: Pal.inkSoft, size: 32),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: _locating ? null : _locate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _locating
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.near_me_outlined, size: 16, color: Pal.primaryDeep),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('report.gps.recalibrate'),
                                style: head(13, w: FontWeight.w700, c: Pal.primaryDeep),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (p != null && p.accuracy > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr('report.gps.low'),
                style: body(12, c: Pal.tertiaryDeep),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sizeRow(String key, IconData icon, Color fg, Color bg, String title, String hint) {
    final on = _size == key;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _size = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? Pal.primaryFixed.withValues(alpha: 0.55) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? Pal.primary : Pal.line, width: on ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: head(15)),
                  const SizedBox(height: 2),
                  Text(hint, style: body(12, c: Pal.inkSoft, h: 1.3)),
                ],
              ),
            ),
            Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? Pal.primary : Pal.outline),
          ],
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const m = 22.0;
    const l = 26.0;
    final w = size.width;
    final h = size.height;
    for (final c in [
      [m, m, 1.0, 1.0],
      [w - m, m, -1.0, 1.0],
      [m, h - m, 1.0, -1.0],
      [w - m, h - m, -1.0, -1.0],
    ]) {
      final x = c[0];
      final y = c[1];
      canvas.drawLine(Offset(x, y), Offset(x + c[2] * l, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + c[3] * l), p);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.r, {required this.onClose});
  final Map<String, dynamic> r;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (r['queued'] == true) {
      return _box(
        Pal.tertiaryFixed,
        Icons.cloud_upload_outlined,
        Pal.tertiaryDeep,
        context.tr('result.queued.title'),
        context.tr('result.queued.text'),
      );
    }
    final rep = (r['report'] as Map?) ?? {};
    final dup = r['duplicate'] == true;
    final status = rep['status'] as String?;
    final pts = (r['points_awarded'] as num?)?.toInt() ?? 0;
    if (status == 'rejected') {
      final reasons = ((rep['reject_reasons'] as List?) ?? []).join(', ');
      return _box(
        Pal.errorSoft,
        Icons.block,
        const Color(0xFF991B1B),
        context.tr('result.rejected.title'),
        reasons.isEmpty ? context.tr('result.rejected.default') : reasons,
      );
    }
    if (dup) {
      return _box(
        Pal.secondaryFixed,
        Icons.copy_all_outlined,
        Pal.secondary,
        context.tr('result.dup.title'),
        context.tr('result.dup.text'),
      );
    }
    final base = pts > 0
        ? context.tr('result.ok.points', {'n': '$pts'})
        : context.tr('result.ok.text');
    return _box(
      Pal.primaryFixed,
      Icons.check_circle_outline,
      Pal.onPrimaryFixed,
      context.tr('result.ok.title'),
      r['voice_pending'] == true ? '$base ${context.tr('result.voice_pending')}' : base,
    );
  }

  Widget _box(Color bg, IconData icon, Color fg, String title, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: head(15, c: fg)),
                const SizedBox(height: 2),
                Text(text, style: body(13, c: fg, h: 1.35)),
              ],
            ),
          ),
          InkWell(
            onTap: onClose,
            child: Icon(Icons.close, size: 18, color: fg),
          ),
        ],
      ),
    );
  }
}
