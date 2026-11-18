import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analytics.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Vue du pré-collecteur : données calculées par le moteur
/// (`POST /api/insights/precollectors`).
class PrecollectorsScreen extends StatefulWidget {
  const PrecollectorsScreen({super.key});

  @override
  State<PrecollectorsScreen> createState() => _PrecollectorsScreenState();
}

class _PrecollectorsScreenState extends State<PrecollectorsScreen> {
  List<PrecollectorView>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await s.api.post('/api/insights/precollectors', {}, 60);
      _items = parsePrecollectors(j);
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget body0;
    if (_loading) {
      body0 = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body0 = ErrorState(_error!, _load);
    } else if (_items == null || _items!.isEmpty) {
      body0 = const EmptyState(
        Icons.pedal_bike,
        'Aucun pré-collecteur',
        'Le moteur n’a renvoyé aucune zone de pré-collecte pour le moment.',
      );
    } else {
      body0 = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Text('${_items!.length} zone(s) de pré-collecte', style: body(13, c: Pal.inkSoft)),
            const SizedBox(height: 10),
            for (final p in _items!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: Pal.tertiaryFixed, borderRadius: BorderRadius.circular(11)),
                            child: const Icon(Icons.pedal_bike, color: Pal.tertiaryDeep, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(p.title, style: head(16))),
                        ],
                      ),
                      if (p.fields.isNotEmpty) const SizedBox(height: 12),
                      for (final f in p.fields.take(8))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(child: Text(f.key, style: body(13, c: Pal.inkSoft))),
                              Text(f.value, style: body(13, w: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Pré-collecteurs')), body: body0);
  }
}
