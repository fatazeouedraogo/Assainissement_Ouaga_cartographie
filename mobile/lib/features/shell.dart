import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/motif.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'map_screen.dart';
import 'priorities_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
import 'simulator_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final staff = s.user!.isStaff;
    final pages = <Widget>[
      const MapScreen(),
      const PrioritiesScreen(),
      if (staff) const SimulatorScreen(),
      const ProfileScreen(),
    ];
    final dests = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: tr('nav_map')),
      NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: tr('nav_priorities')),
      if (staff) NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: tr('nav_simulator')),
      NavigationDestination(
        icon: Badge(isLabelVisible: s.pending > 0, label: Text('${s.pending}'), child: const Icon(Icons.person_outline)),
        selectedIcon: const Icon(Icons.person),
        label: tr('nav_me'),
      ),
    ];
    if (_i >= pages.length) _i = 0;
    return Scaffold(
      body: Column(children: [
        const MotifBand(height: 8),
        Expanded(child: IndexedStack(index: _i, children: pages)),
      ]),
      floatingActionButton: _i == 0
          ? FloatingActionButton.extended(
              backgroundColor: Pal.signal,
              foregroundColor: Pal.ink,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Pal.ink, width: 1.6)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen())),
              icon: const MoundGlyph(level: 1, color: Pal.surface, size: 26),
              label: Text(tr('report_btn'), style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      bottomNavigationBar: NavigationBar(selectedIndex: _i, onDestinationSelected: (v) => setState(() => _i = v), destinations: dests),
    );
  }
}
