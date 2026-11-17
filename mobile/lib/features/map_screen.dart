import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'dump_sheet.dart';

Color statusColor(String s) => switch (s) {
      'pending' => Pal.pending,
      'verified' => Pal.dump,
      'scheduled' => Pal.planned,
      'cleaned' => Pal.cleaned,
      _ => Pal.inkSoft,
    };

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _ctrl = MapController();
  final Set<String> _filter = {'pending', 'verified', 'scheduled'};
  LatLng? _me;
  bool _risk = false, _cand = false, _sens = false;
  List<dynamic> _riskCells = [], _cands = [], _sensors = [];

  Future<void> _toggle(String which, bool on) async {
    final api = context.read<AppState>().api;
    setState(() {
      if (which == 'risk') _risk = on;
      if (which == 'cand') _cand = on;
      if (which == 'sens') _sens = on;
    });
    if (!on) return;
    try {
      if (which == 'risk') {
        final j = await api.get('/api/insights/risk');
        if (mounted) setState(() => _riskCells = j['cells'] as List);
      } else if (which == 'cand') {
        final j = await api.get('/api/candidates');
        if (mounted) setState(() => _cands = j['candidates'] as List);
      } else {
        final j = await api.get('/api/iot/status');
        if (mounted) setState(() => _sensors = j['sensors'] as List);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couche indisponible pour le moment')));
    }
  }

  static const _filters = {
    'pending': 'À vérifier',
    'verified': 'Vérifiés',
    'scheduled': 'Programmés',
    'cleaned': 'Nettoyés',
  };

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await Geolocator.isLocationServiceEnabled()) {
      messenger.showSnackBar(const SnackBar(content: Text('Activez la localisation du téléphone')));
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      messenger.showSnackBar(const SnackBar(content: Text('Autorisez la localisation pour vous situer')));
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
      final here = LatLng(p.latitude, p.longitude);
      setState(() => _me = here);
      _ctrl.move(here, 16);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Position introuvable pour le moment')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final shown = s.dumps.where((d) => _filter.contains(d.status)).toList();
    return Stack(children: [
      FlutterMap(
        mapController: _ctrl,
        options: const MapOptions(initialCenter: LatLng(12.3714, -1.5197), initialZoom: 12.6, minZoom: 9, maxZoom: 19),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'bf.ouaga.assainissement'),
          if (_risk)
            CircleLayer(circles: [
              for (final c in _riskCells)
                CircleMarker(point: LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()), radius: (c['radius_m'] as num).toDouble(), useRadiusInMeter: true, color: Pal.dump.withValues(alpha: 0.10 + 0.35 * (c['risk'] as num).toDouble() / 100), borderColor: Pal.dump, borderStrokeWidth: 1),
            ]),
          if (_cand)
            CircleLayer(circles: [
              for (final c in _cands)
                CircleMarker(point: LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()), radius: 40, useRadiusInMeter: true, color: Colors.transparent, borderColor: Pal.planned, borderStrokeWidth: 2),
            ]),
          MarkerLayer(
            markers: [
              if (_sens)
                for (final c in _sensors)
                  Marker(
                    point: LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(color: c['urgent'] == true ? Pal.dump : Pal.cleaned, shape: BoxShape.rectangle, borderRadius: BorderRadius.circular(4), border: Border.all(color: Pal.ink, width: 1.6)),
                      child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                    ),
                  ),
              for (final d in shown)
                Marker(
                  point: d.pos,
                  width: 46,
                  height: 46,
                  child: GestureDetector(
                    onTap: () => showDumpSheet(context, d),
                    child: MoundGlyph(level: d.sizeLevel, color: statusColor(d.status), size: 40 + d.priority / 12, ring: d.recurrence),
                  ),
                ),
              if (_me != null)
                Marker(
                  point: _me!,
                  width: 26,
                  height: 26,
                  child: Container(decoration: BoxDecoration(color: Pal.signal, shape: BoxShape.circle, border: Border.all(color: Pal.ink, width: 3))),
                ),
            ],
          ),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© contributeurs OpenStreetMap')]),
        ],
      ),
      Positioned(
        top: 10,
        left: 10,
        right: 10,
        child: SafeArea(
          child: Plate(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    FilterChip(label: const Text('Risque'), showCheckmark: false, selected: _risk, labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _risk ? Pal.surface : Pal.ink), onSelected: (v) => _toggle('risk', v)),
                    const SizedBox(width: 6),
                    if (s.user!.isStaff) ...[
                      FilterChip(label: const Text('Candidats'), showCheckmark: false, selected: _cand, labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _cand ? Pal.surface : Pal.ink), onSelected: (v) => _toggle('cand', v)),
                      const SizedBox(width: 6),
                      FilterChip(label: const Text('Capteurs'), showCheckmark: false, selected: _sens, labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _sens ? Pal.surface : Pal.ink), onSelected: (v) => _toggle('sens', v)),
                      const SizedBox(width: 10),
                    ],
                    for (final e in _filters.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          showCheckmark: false,
                          avatar: CircleAvatar(radius: 5, backgroundColor: statusColor(e.key)),
                          label: Text(e.value),
                          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _filter.contains(e.key) ? Pal.surface : Pal.ink),
                          selected: _filter.contains(e.key),
                          onSelected: (v) => setState(() => v ? _filter.add(e.key) : _filter.remove(e.key)),
                        ),
                      ),
                  ]),
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: s.loadingDumps ? null : s.refreshDumps,
                icon: s.loadingDumps ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Pal.ink)) : const Icon(Icons.refresh),
              ),
            ]),
          ),
        ),
      ),
      if (s.dumpError != null)
        Positioned(
          top: 84,
          left: 10,
          right: 10,
          child: SafeArea(child: Plate(color: Pal.signal, padding: const EdgeInsets.all(10), child: Text(s.dumpError!, style: const TextStyle(fontWeight: FontWeight.w700)))),
        ),
      Positioned(
        left: 14,
        bottom: 18,
        child: FloatingActionButton.small(
          heroTag: 'locate',
          backgroundColor: Pal.surface,
          foregroundColor: Pal.ink,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Pal.ink, width: 1.4)),
          onPressed: _locate,
          child: const Icon(Icons.my_location),
        ),
      ),
    ]);
  }
}
