import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await s.register(_name.text.trim(), _phone.text.trim(), _pass.text);
      } else {
        await s.login(_phone.text.trim(), _pass.text);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.fields.isNotEmpty ? e.fields.join('\n') : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _server() async {
    final s = context.read<AppState>();
    final c = TextEditingController(text: s.api.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adresse du serveur'),
        content: TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'http://192.168.1.10:3000')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) await s.api.saveBase(c.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        children: [
          const MotifBand(height: 22),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                children: [
                  Row(children: [
                    const MoundGlyph(level: 2, color: Pal.signal, size: 54),
                    const SizedBox(width: 10),
                    Text('OUAGA\nPROPRE', style: t.headlineMedium),
                  ]),
                  const SizedBox(height: 14),
                  Text(tr('tagline'), style: t.bodyLarge?.copyWith(color: Pal.inkSoft)),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('name'))),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('phone'), hintText: '+226 70 00 00 00')),
                  const SizedBox(height: 12),
                  TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: tr('password'))),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: t.bodyMedium?.copyWith(color: Pal.dump, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Un instant…' : _register ? tr('register') : tr('login'))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(_register ? 'J’ai déjà un compte' : 'Première visite ? Créer un compte'),
                  ),
                  TextButton(onPressed: _server, child: const Text('Adresse du serveur')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
