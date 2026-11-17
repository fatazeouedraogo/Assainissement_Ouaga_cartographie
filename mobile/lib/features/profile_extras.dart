import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';

class NotificationsCard extends StatefulWidget {
  const NotificationsCard({super.key});

  @override
  State<NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<NotificationsCard> {
  List<dynamic> _items = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await context.read<AppState>().api.get('/api/notifications');
      if (mounted) {
        setState(() {
          _items = j['items'] as List;
          _unread = j['unread'] as int;
        });
      }
    } on ApiException catch (_) {}
  }

  Future<void> _read() async {
    await context.read<AppState>().api.post('/api/notifications/read');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 22),
      Row(children: [
        Text(tr('notifications'), style: Theme.of(context).textTheme.titleLarge),
        if (_unread > 0) ...[const SizedBox(width: 8), Badge(label: Text('$_unread'))],
        const Spacer(),
        if (_unread > 0) TextButton(onPressed: _read, child: const Text('Tout lire')),
      ]),
      const SizedBox(height: 6),
      Plate(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: [
          for (final n in _items.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(n['kind'] == 'cleaned' ? Icons.check_circle : n['kind'] == 'scheduled' ? Icons.event : Icons.verified, color: n['read_at'] == null ? Pal.ink : Pal.inkSoft),
              title: Text('${n['title']}', style: TextStyle(fontWeight: n['read_at'] == null ? FontWeight.w800 : FontWeight.w500)),
              subtitle: Text('${n['body']}'),
            ),
        ]),
      ),
    ]);
  }
}

class SubscriptionCard extends StatefulWidget {
  const SubscriptionCard({super.key});

  @override
  State<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<SubscriptionCard> {
  int _price = 0;
  String? _until;
  String _provider = 'orange';
  int _months = 1;
  final _wallet = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final p = await api.get('/api/subscriptions/price');
      final m = await api.get('/api/subscriptions/mine');
      if (mounted) {
        setState(() {
          _price = (p['price_month'] as num).toInt();
          _until = m['active_until'] as String?;
        });
      }
    } on ApiException catch (_) {}
  }

  Future<void> _pay() async {
    final api = context.read<AppState>().api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final j = await api.post('/api/subscriptions/pay', {'provider': _provider, 'wallet_phone': _wallet.text.trim(), 'months': _months});
      messenger.showSnackBar(SnackBar(content: Text('${j['notice']} Réf. ${j['reference']}')));
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.fields.isNotEmpty ? e.fields.join(', ') : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 22),
      Text(tr('subscription'), style: t.titleLarge),
      const SizedBox(height: 6),
      Plate(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_until == null ? 'Pas d’abonnement actif' : 'Actif jusqu’au ${_until!.substring(0, 10)}', style: t.titleMedium),
          Text('$_price FCFA par mois · paiement simulé, aucun argent n’est débité', style: t.bodySmall?.copyWith(color: Pal.inkSoft)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'orange', label: Text('Orange Money')), ButtonSegment(value: 'moov', label: Text('Moov Money'))],
                selected: {_provider},
                onSelectionChanged: (s) => setState(() => _provider = s.first),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _wallet, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro du portefeuille')),
          const SizedBox(height: 6),
          Row(children: [
            const Text('Durée'),
            Expanded(child: Slider(value: _months.toDouble(), min: 1, max: 12, divisions: 11, label: '$_months mois', onChanged: (v) => setState(() => _months = v.round()))),
            Text('$_months mois', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          FilledButton(onPressed: _busy || _price == 0 ? null : _pay, child: Text(_busy ? 'Paiement…' : 'Payer ${_price * _months} FCFA (simulation)')),
        ]),
      ),
    ]);
  }
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 22),
        Text(tr('language'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final e in languages.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: I18n.lang == e.key,
              showCheckmark: false,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: I18n.lang == e.key ? Pal.surface : Pal.ink),
              onSelected: (_) async {
                await I18n.set(e.key);
                onChanged();
              },
            ),
        ]),
        const SizedBox(height: 4),
        const Text('Mooré et dioula : traductions à saisir par des locuteurs (assets/i18n). En attendant, le français s’affiche.', style: TextStyle(fontSize: 12, color: Pal.inkSoft)),
      ]);
}
