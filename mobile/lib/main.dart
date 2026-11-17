import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/state.dart';
import 'core/theme.dart';
import 'features/login_screen.dart';
import 'features/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  I18n.load();
  runApp(ChangeNotifierProvider(create: (_) => AppState()..boot(), child: const OuagaApp()));
}

class OuagaApp extends StatelessWidget {
  const OuagaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'Ouaga Propre',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: s.booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator(color: Pal.ink)))
          : s.user == null
              ? const LoginScreen()
              : const Shell(),
    );
  }
}
