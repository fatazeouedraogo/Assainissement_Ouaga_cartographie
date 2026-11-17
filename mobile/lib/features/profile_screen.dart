import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'profile_extras.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _overview;
  List<dynamic> _leaders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final o = await s.api.get('/api/public/overview');
      final l = await s.api.get('/api/public/leaderboard');
      if (mounted) {
        setState(() {
          _overview = o as Map<String, dynamic>;
          _leaders = l['leaders'] as List;
        });
      }
    } on ApiException catch (_) {}
    await s.refreshMe();
  }

  int _count(String status) => (_overview?['by_status'] as Map?)?[status]?['count'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user!;
    final t = Theme.of(context).textTheme;
    final hours = (_overview?['avg_hours_to_clean'] as num?)?.toDouble();
    return SafeArea(
      child: RefreshIndicator(
        color: Pal.ink,
        onRefresh: () async {
          await _load();
          await s.refreshDumps();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
          Text(u.name, style: t.headlineMedium),
          Text(u.role == 'admin' ? 'Administration' : u.role == 'verifier' ? 'Vérificateur' : u.role == 'agent' ? 'Agent de terrain' : 'Citoyen', style: t.bodyMedium?.copyWith(color: Pal.inkSoft)),
          const SizedBox(height: 14),
          Plate(
            color: Pal.ink,
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u.points}', style: t.headlineMedium?.copyWith(color: Pal.signal, fontSize: 40)),
                Text('points gagnés', style: t.bodyMedium?.copyWith(color: Pal.surface)),
              ])),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                for (final b in s.badges) Chip(label: Text(b, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), backgroundColor: Pal.signal, side: BorderSide.none, visualDensity: VisualDensity.compact),
              ]),
            ]),
          ),
          if (s.pending > 0) ...[
            const SizedBox(height: 10),
            Plate(
              color: Pal.signal,
              child: Row(children: [
                Expanded(child: Text('${s.pending} signalement(s) en attente d’envoi', style: const TextStyle(fontWeight: FontWeight.w800))),
                TextButton(onPressed: s.syncing ? null : s.sync, child: Text(s.syncing ? 'Envoi…' : 'Envoyer')),
              ]),
            ),
          ],
          const NotificationsCard(),
          const SubscriptionCard(),
          LanguagePicker(onChanged: () => setState(() {})),
          const SizedBox(height: 22),
          Text('La ville en ce moment', style: t.titleLarge),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Num('${_count('verified') + _count('scheduled')}', 'dépotoirs à traiter')),
            const SizedBox(width: 8),
            Expanded(child: _Num('${_overview?['cleaned_last_30_days'] ?? 0}', 'nettoyés en 30 jours')),
            const SizedBox(width: 8),
            Expanded(child: _Num(hours == null ? '—' : hours < 48 ? '${hours.round()} h' : '${(hours / 24).round()} j', 'délai moyen')),
          ]),
          if (_leaders.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Ceux qui font bouger les choses', style: t.titleLarge),
            const SizedBox(height: 8),
            Plate(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                for (final l in _leaders.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      SizedBox(width: 30, child: Text('${l['rank']}', style: t.titleMedium?.copyWith(color: Pal.inkSoft))),
                      Expanded(child: Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text('${l['points']} pts', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(onPressed: s.logout, child: Text(tr('logout'))),
        ]),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Plate(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26)),
          Text(label, style: const TextStyle(fontSize: 12, color: Pal.inkSoft, height: 1.2)),
        ]),
      );
}
