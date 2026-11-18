import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/login_screen.dart';
import 'features/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await Session.load();
  final lang = await Lang.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: lang),
      ],
      child: const OuagaCleanApp(),
    ),
  );
}

class OuagaCleanApp extends StatelessWidget {
  const OuagaCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return MaterialApp(
      title: 'OuagaClean',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: s.loggedIn ? const Shell() : const LoginScreen(),
    );
  }
}
