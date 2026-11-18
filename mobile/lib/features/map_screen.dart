import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'candidate_sheet.dart';
import 'dump_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.active});
  final bool active;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _ouaga = LatLng(12.3714, -1.5197);
  final _map = MapController();
  List<Dump> _dumps = [];
  List<Candidate> _cands = [];
  bool _loading = true;
  String? _error;
  String _filter = 'todo';
  bool _showCands = false;
  LatLng? _me;
  DateTime? _lastSync;

  static const _filters = {
    'todo': 'À traiter',
    'scheduled': 'Programmés',
    'cleaned': 'Nettoyés',
    'pending': 'En attente',
    'all': 'Tous',
  };

  @override
  void initState() {
    super.initState();
    context.read<Session>().focus.addListener(_onFocus);
    _load();
    _onFocus();
  }

  @override
  void dispose() {
    context.read<Session>().focus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final f = context.read<Session>().focus.value;
    if (f == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _map.move(LatLng(f[0], f[1]), 18);
      } catch (_) {}
    });
  }

  int _count(String k) => _dumps
      .where(
        (d) => switch (k) {
          'todo' => d.status == 'verified' || d.status == 'scheduled',
          'all' => d.status != 'rejected',
          _ => d.status == k,
        },
      )
      .length;

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = _dumps.isEmpty;
      _error = null;
    });
    try {
      final j = await s.api.get('/api/dumps', query: {'limit': '2000'}) as Map;
      final list = [
        for (final f in (j['features'] as List)) Dump.fromFeature(Map<String, dynamic>.from(f as Map)),
      ];
      var cands = <Candidate>[];
      if (s.isStaff) {
        try {
          final cj = await s.api.get('/api/candidates') as Map;
          cands = [
            for (final c in (cj['candidates'] as List))
              Candidate.fromJson(Map<String, dynamic>.from(c as Map)),
          ];
        } on ApiException {
          cands = [];
        }
      }
      if (mounted) {
        setState(() {
          _dumps = list;
          _cands = cands;
          _lastSync = DateTime.now();
        });
      }
    } on ApiException catch (e) {
      if (e.unauthorized) await s.logout();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Dump> get _visible => _dumps.where((d) {
    switch (_filter) {
      case 'todo':
        return d.status == 'verified' || d.status == 'scheduled';
      case 'all':
        return d.status != 'rejected';
      default:
        return d.status == _filter;
    }
  }).toList();

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final ll = LatLng(p.latitude, p.longitude);
      setState(() => _me = ll);
      _map.move(ll, 16);
    } catch (_) {
      if (mounted) toast(context, 'Position introuvable.', error: true);
    }
  }

  Future<void> _openDump(Dump d) async {
    if (await showDumpSheet(context, d)) _load();
  }

  Future<void> _openCand(Candidate c) async {
    if (await showCandidateSheet(context, c)) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (_error != null && _dumps.isEmpty) return ErrorState(_error!, _load);
    final dumps = _visible;
    final stack = Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(initialCenter: _ouaga, initialZoom: 12.5, minZoom: 9, maxZoom: 19),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'bf.ouagaclean.app',
            ),
            MarkerLayer(
              markers: [
                for (final d in dumps)
                  Marker(
                    point: LatLng(d.lat, d.lon),
                    width: 34,
                    height: 34,
                    child: GestureDetector(
                      onTap: () => _openDump(d),
                      child: Container(
                        decoration: BoxDecoration(
                          color: statusColor(d.status),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: d.size == 'large' ? 3 : 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          d.status == 'cleaned' ? Icons.check : Icons.delete_outline,
                          color: Colors.white,
                          size: d.size == 'large' ? 19 : 16,
                        ),
                      ),
                    ),
                  ),
                if (s.isStaff && _showCands)
                  for (final c in _cands)
                    Marker(
                      point: LatLng(c.lat, c.lon),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _openCand(c),
                        child: Transform.rotate(
                          angle: 0.785,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Pal.secondary,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Transform.rotate(
                              angle: -0.785,
                              child: const Icon(Icons.satellite_alt, color: Colors.white, size: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Pal.secondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${e.value} (${_count(e.key)})'),
                      selected: _filter == e.key,
                      onSelected: (_) => setState(() => _filter = e.key),
                      selectedColor: Pal.primary,
                      backgroundColor: Colors.white,
                      showCheckmark: false,
                      side: BorderSide(color: _filter == e.key ? Pal.primary : Pal.line),
                      labelStyle: body(13, w: FontWeight.w700, c: _filter == e.key ? Colors.white : Pal.ink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                if (s.isStaff)
                  FilterChip(
                    label: Text('Satellite${_cands.isEmpty ? '' : ' (${_cands.length})'}'),
                    avatar: const Icon(Icons.satellite_alt, size: 16),
                    selected: _showCands,
                    onSelected: (v) => setState(() => _showCands = v),
                    selectedColor: Pal.secondaryFixed,
                    backgroundColor: Colors.white,
                    showCheckmark: false,
                    side: BorderSide(color: _showCands ? Pal.secondary : Pal.line),
                    labelStyle: body(13, w: FontWeight.w700, c: _showCands ? Pal.secondary : Pal.ink),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 26,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'refresh',
                onPressed: _load,
                backgroundColor: Colors.white,
                foregroundColor: Pal.ink,
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'me',
                onPressed: _locate,
                backgroundColor: Pal.primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.my_location),
              ),
            ],
          ),
        ),
        Positioned(
          left: 8,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('© contributeurs OpenStreetMap', style: body(10, c: Pal.inkSoft)),
          ),
        ),
        if (!_loading && dumps.isEmpty && _error == null)
          Positioned(
            bottom: 30,
            left: 16,
            right: 90,
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Text('Aucun dépotoir dans ce filtre.', style: body(13, c: Pal.inkSoft)),
            ),
          ),
      ],
    );
    return Column(
      children: [
        Expanded(child: stack),
        _panel(s),
      ],
    );
  }

  Widget _panel(Session s) {
    final t = _lastSync;
    final hm = t == null
        ? '—'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    Widget dot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: body(12, w: FontWeight.w600, c: Pal.inkSoft),
        ),
      ],
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              dot(statusColor('verified'), 'Confirmé'),
              dot(statusColor('scheduled'), 'Programmé'),
              dot(statusColor('cleaned'), 'Nettoyé'),
              dot(statusColor('pending'), 'En attente'),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final ok = await launchUrl(
                Uri.parse('${s.api.base.replaceAll(RegExp(r'/+$'), '')}/api/public/dumps.geojson'),
                mode: LaunchMode.externalApplication,
              );
              if (!ok && mounted) toast(context, 'Impossible d’ouvrir le lien.', error: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Pal.primary, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.public, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partager / exporter vers OpenStreetMap',
                          style: head(14, w: FontWeight.w700, c: Colors.white),
                        ),
                        Text('GeoJSON ODbL • dépotoirs vérifiés', style: body(11, c: Colors.white70)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'ODbL',
                      style: body(11, w: FontWeight.w800, c: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.circle, size: 8, color: Pal.primary),
              const SizedBox(width: 6),
              Text(
                'Dernière synchro : $hm',
                style: body(12, w: FontWeight.w600, c: Pal.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
