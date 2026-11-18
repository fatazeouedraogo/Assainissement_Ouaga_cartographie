import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'language_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List _notifs = [];
  List _mine = [];
  late final TextEditingController _server;
  String? _apiState;
  String? _engineState;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: context.read<Session>().api.base);
    _load();
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    try {
      final n = await s.api.get('/api/notifications') as Map;
      final m = await s.api.get('/api/reports/mine') as Map;
      if (mounted) {
        setState(() {
          _notifs = (n['items'] as List?) ?? [];
          _mine = (m['reports'] as List?) ?? [];
        });
      }
    } on ApiException catch (e) {
      if (e.unauthorized) await s.logout();
    }
  }

  Future<void> _markRead() async {
    final s = context.read<Session>();
    try {
      await s.api.post('/api/notifications/read');
      await s.refreshCounters();
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _check() async {
    final s = context.read<Session>();
    setState(() {
      _checking = true;
      _apiState = null;
      _engineState = null;
    });
    await s.setBase(_server.text);
    try {
      await s.api.get('/health', timeout: 8);
      _apiState = 'ok';
    } on ApiException catch (e) {
      _apiState = e.message;
    }
    if (s.isStaff && _apiState == 'ok') {
      try {
        await s.api.get('/api/plan/controls', timeout: 12);
        _engineState = 'ok';
      } on ApiException catch (e) {
        _engineState = e.message;
      }
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final roleLabel = switch (s.role) {
      'admin' => 'Administrateur',
      'verifier' => 'Vérificateur',
      'agent' => 'Agent',
      _ => 'Citoyen',
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Pal.primaryFixed,
                  child: Text(
                    s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                    style: head(22, c: Pal.onPrimaryFixed),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: head(18)),
                      Text('${s.user?['phone'] ?? ''}', style: body(13, c: Pal.inkSoft)),
                      const SizedBox(height: 6),
                      Pill(roleLabel),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text('${s.points}', style: head(24, c: Pal.primaryDeep)),
                    Text('points', style: body(11, c: Pal.inkSoft)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const LanguageCard(),
          SectionTitle(
            'Notifications',
            trailing: _notifs.isEmpty
                ? null
                : TextButton(onPressed: _markRead, child: const Text('Tout lire')),
          ),
          if (_notifs.isEmpty)
            const AppCard(child: Text('Aucune notification.'))
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < _notifs.length && i < 8; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.circle,
                        size: 10,
                        color: (_notifs[i] as Map)['read_at'] == null ? Pal.primary : Pal.line,
                      ),
                      title: Text('${(_notifs[i] as Map)['title']}', style: body(14, w: FontWeight.w700)),
                      subtitle: Text('${(_notifs[i] as Map)['body']}', style: body(12, c: Pal.inkSoft)),
                    ),
                  ],
                ],
              ),
            ),
          SectionTitle('Mes signalements'),
          if (_mine.isEmpty)
            const AppCard(child: Text('Vous n’avez encore rien signalé.'))
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < _mine.length && i < 8; i++) ...[
                    if (i > 0) const Divider(),
                    Builder(
                      builder: (_) {
                        final r = _mine[i] as Map;
                        final st = (r['dump_status'] ?? r['status']) as String? ?? 'pending';
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${sizeLabels[r['size']] ?? r['size']} · ${wasteLabels[r['waste_type']] ?? r['waste_type']}',
                            style: body(14, w: FontWeight.w600),
                          ),
                          subtitle: Text(
                            fmtDate(r['created_at'] as String?),
                            style: body(12, c: Pal.inkSoft),
                          ),
                          trailing: Pill(
                            statusLabels[st] ?? st,
                            color: statusColor(st),
                            bg: statusColor(st).withValues(alpha: 0.14),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          SectionTitle('Connexion au serveur'),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Adresse de l’API'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: const Text('Tester la connexion'),
          ),
          if (_apiState != null) _status('API Express', _apiState!),
          if (_engineState != null) _status('Moteur de calcul FastAPI', _engineState!),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () async {
              await s.logout();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.logout, color: Pal.error),
            label: const Text('Se déconnecter', style: TextStyle(color: Pal.error)),
          ),
        ],
      ),
    );
  }

  Widget _status(String name, String state) {
    final ok = state == 'ok';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, size: 20, color: ok ? Pal.primaryDeep : Pal.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok ? '$name : joignable' : '$name : $state',
              style: body(13, w: FontWeight.w600, c: ok ? Pal.onPrimaryFixed : const Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}
