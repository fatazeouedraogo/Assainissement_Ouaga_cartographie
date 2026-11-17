import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'dump_sheet.dart';
import 'map_screen.dart' show statusColor;

class PrioritiesScreen extends StatelessWidget {
  const PrioritiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = s.dumps.where((d) => d.status == 'verified' || d.status == 'scheduled').toList()..sort((a, b) => b.priority.compareTo(a.priority));
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: RefreshIndicator(
        color: Pal.ink,
        onRefresh: s.refreshDumps,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          Text('À traiter en premier', style: t.headlineMedium),
          const SizedBox(height: 4),
          Text('Classement par risque sanitaire : volume, ancienneté, caniveaux, écoles, marchés et centres de santé.', style: t.bodyMedium?.copyWith(color: Pal.inkSoft)),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Plate(child: Text('Aucun dépotoir vérifié pour le moment. Les signalements confirmés apparaîtront ici.')),
          for (var i = 0; i < items.length; i++) _Row(rank: i + 1, d: items[i]),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.d});
  final int rank;
  final Dump d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hot = d.priority >= 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDumpSheet(context, d),
        child: Plate(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          color: hot ? const Color(0xFFFBEFD0) : null,
          child: Row(children: [
            SizedBox(width: 28, child: Text('$rank', style: t.titleLarge?.copyWith(color: Pal.inkSoft))),
            MoundGlyph(level: d.sizeLevel, color: statusColor(d.status), size: 44, ring: d.recurrence),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sizeLabels[d.size]} · ${wasteLabels[d.wasteType]}', style: t.titleMedium),
                Text(d.driver == null ? statusLabels[d.status]! : driverLabels[d.driver] ?? '', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${d.priority.round()}', style: t.titleLarge),
              Text(levelLabels[d.level] ?? '', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: hot ? Pal.dump : Pal.inkSoft)),
            ]),
          ]),
        ),
      ),
    );
  }
}
