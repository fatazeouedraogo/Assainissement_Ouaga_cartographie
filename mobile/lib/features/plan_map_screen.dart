import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

const _palette = [Pal.planned, Pal.dump, Pal.cleaned, Pal.pending, Color(0xFF7A4FA3), Color(0xFF008B8B)];

class PlanMapScreen extends StatefulWidget {
  const PlanMapScreen({super.key, required this.plan});
  final Map<String, dynamic> plan;

  @override
  State<PlanMapScreen> createState() => _PlanMapScreenState();
}

class _PlanMapScreenState extends State<PlanMapScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Map<String, LatLng> _pts;
  int _group = 0;
  double _speed = 1;

  List<Map<String, dynamic>> get _routes {
    final groups = (widget.plan['groups'] as List).cast<Map<String, dynamic>>();
    return (groups[_group]['routes'] as List).cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _pts = {for (final p in (widget.plan['points'] as List)) p['id'] as String: LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())};
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<LatLng> _path(Map<String, dynamic> r) => [for (final s in (r['stops'] as List)) _pts[s as String]!];

  LatLng _at(List<LatLng> path, double t) {
    if (path.length == 1) return path.first;
    const d = Distance();
    final seg = <double>[];
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final l = d.distance(path[i], path[i + 1]);
      seg.add(l);
      total += l;
    }
    var target = total * t;
    for (var i = 0; i < seg.length; i++) {
      if (target <= seg[i] || i == seg.length - 1) {
        final f = seg[i] == 0 ? 0.0 : (target / seg[i]).clamp(0.0, 1.0);
        return LatLng(path[i].latitude + (path[i + 1].latitude - path[i].latitude) * f, path[i].longitude + (path[i + 1].longitude - path[i].longitude) * f);
      }
      target -= seg[i];
    }
    return path.last;
  }

  @override
  Widget build(BuildContext context) {
    final groups = (widget.plan['groups'] as List).length;
    final routes = _routes;
    final first = _pts.values.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournées')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            if (groups > 1)
              Expanded(
                child: Wrap(spacing: 6, children: [
                  for (var g = 0; g < groups; g++)
                    ChoiceChip(
                      label: Text('Jour ${g + 1}'),
                      selected: _group == g,
                      showCheckmark: false,
                      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _group == g ? Pal.surface : Pal.ink),
                      onSelected: (_) => setState(() => _group = g),
                    ),
                ]),
              )
            else
              const Spacer(),
            const Text('Vitesse'),
            SizedBox(
              width: 130,
              child: Slider(
                value: _speed,
                min: 0.5,
                max: 4,
                onChanged: (v) {
                  setState(() => _speed = v);
                  _anim.duration = Duration(milliseconds: (14000 / v).round());
                  _anim.repeat();
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FlutterMap(
              options: MapOptions(initialCenter: first, initialZoom: 12.5, minZoom: 9, maxZoom: 19),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'bf.ouaga.assainissement'),
                PolylineLayer(polylines: [
                  for (var i = 0; i < routes.length; i++)
                    if (_path(routes[i]).length > 1) Polyline(points: _path(routes[i]), color: _palette[i % _palette.length].withValues(alpha: 0.85), strokeWidth: 3),
                ]),
                MarkerLayer(markers: [
                  for (final e in _pts.entries) Marker(point: e.value, width: 8, height: 8, child: Container(decoration: BoxDecoration(color: Pal.ink, shape: BoxShape.circle))),
                  for (var i = 0; i < routes.length; i++)
                    if (_path(routes[i]).isNotEmpty)
                      Marker(
                        point: _at(_path(routes[i]), (_anim.value + i * 0.13) % 1),
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle, border: Border.all(color: Pal.ink, width: 2)),
                          child: Icon(routes[i]['kind'] == 'tricycle' ? Icons.pedal_bike : Icons.local_shipping, size: 16, color: Colors.white),
                        ),
                      ),
                ]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${routes.length} rotation(s) ce jour-là · ${routes.fold<double>(0, (a, r) => a + (r['dist_km'] as num)).round()} km au total', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
