import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();
  late final TextEditingController _server;
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: context.read<Session>().api.base);
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _pass.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim().replaceAll(' ', '');
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone))
      return setState(() => _error = 'Entrez un numéro de téléphone valide.');
    if (_pass.text.length < (_register ? 6 : 1))
      return setState(() => _error = 'Le mot de passe doit contenir au moins 6 caractères.');
    if (_register && _name.text.trim().length < 2) return setState(() => _error = 'Entrez votre nom.');
    final s = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await s.setBase(_server.text);
      if (_register) {
        await s.register(_name.text.trim(), phone, _pass.text);
      } else {
        await s.login(phone, _pass.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(child: Image.asset('assets/images/logo.png', width: 250)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Pal.container, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  for (final e in {false: 'Connexion', true: 'Inscription'}.entries)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _register = e.key;
                          _error = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _register == e.key ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: _register == e.key
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            e.value,
                            textAlign: TextAlign.center,
                            style: head(
                              14,
                              w: FontWeight.w700,
                              c: _register == e.key ? Pal.ink : Pal.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_register) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom complet'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                hintText: '+226 70 00 00 01',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _hide,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Pal.errorSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Pal.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: body(13, c: const Color(0xFF991B1B))),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(_register ? 'Créer mon compte' : 'Se connecter'),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showServer = !_showServer),
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: Text('Adresse du serveur', style: body(13, w: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: Pal.inkSoft),
              ),
            ),
            if (_showServer)
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'API', hintText: 'http://192.168.1.10:3000'),
              ),
          ],
        ),
      ),
    );
  }
}
