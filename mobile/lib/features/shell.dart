import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'communes_screen.dart';
import 'impact_screen.dart';
import 'map_screen.dart';
import 'plan_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
import 'verify_screen.dart';

class _Tab {
  const _Tab(this.icon, this.label, this.build, {this.badge = false});
  final IconData icon;
  final String label;
  final Widget Function(bool active) build;
  final bool badge;
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 0;
  final _seen = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<Session>().focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _onFocus() {
    if (context.read<Session>().focus.value == null) return;
    setState(() {
      _i = 1;
      _seen.add(1);
    });
  }

  @override
  void dispose() {
    context.read<Session>().focus.removeListener(_onFocus);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    final s = context.read<Session>();
    s.syncOutbox();
    s.refreshMe();
    s.refreshCounters();
  }

  List<_Tab> _tabs(bool staff, Lang l) => [
    _Tab(Icons.photo_camera_outlined, l.t('tab.report'), (a) => const ReportScreen()),
    _Tab(Icons.map_outlined, l.t('tab.map'), (a) => MapScreen(active: a)),
    _Tab(Icons.volunteer_activism_outlined, l.t('tab.impact'), (a) => ImpactScreen(active: a)),
    if (staff) _Tab(Icons.verified_user_outlined, l.t('tab.verify'), (a) => VerifyScreen(active: a), badge: true),
    if (staff) _Tab(Icons.local_shipping_outlined, l.t('tab.plan'), (a) => const PlanScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final tabs = _tabs(s.isStaff, context.watch<Lang>());
    if (_i >= tabs.length) _i = 0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onProfile: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
            Expanded(
              child: IndexedStack(
                index: _i,
                children: [
                  for (var k = 0; k < tabs.length; k++)
                    _seen.contains(k) ? tabs[k].build(k == _i) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Pal.surface.withValues(alpha: 0.97),
          border: const Border(top: BorderSide(color: Pal.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                for (var k = 0; k < tabs.length; k++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _i = k;
                        _seen.add(k);
                      }),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _i == k ? Pal.primaryFixed : Colors.transparent,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Icon(
                                  tabs[k].icon,
                                  size: 23,
                                  color: _i == k ? Pal.primaryDeep : Pal.inkSoft,
                                ),
                              ),
                              if (tabs[k].badge && s.toVerify > 0)
                                Positioned(
                                  right: 2,
                                  top: -4,
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 17),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Pal.error,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '${s.toVerify}',
                                      textAlign: TextAlign.center,
                                      style: body(10, w: FontWeight.w800, c: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tabs[k].label,
                            style: body(
                              10,
                              w: _i == k ? FontWeight.w800 : FontWeight.w600,
                              c: _i == k ? Pal.primaryDeep : Pal.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onProfile});
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final initial = s.name.isEmpty ? '?' : s.name.trim()[0].toUpperCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Pal.line),
                ),
                child: Image.asset('assets/images/logo_mark.png'),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunesScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_city, size: 18, color: Pal.primaryDeep),
                      const SizedBox(width: 6),
                      Text('Ouagadougou', style: head(14, w: FontWeight.w700)),
                      const Icon(Icons.expand_more, size: 18, color: Pal.inkSoft),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onProfile,
                icon: Badge(
                  isLabelVisible: s.unread > 0,
                  label: Text('${s.unread}'),
                  child: const Icon(Icons.notifications_none_rounded, color: Pal.ink),
                ),
              ),
              GestureDetector(
                onTap: onProfile,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Pal.primaryFixed,
                  child: Text(initial, style: head(15, c: Pal.onPrimaryFixed)),
                ),
              ),
            ],
          ),
        ),
        if (s.queued > 0 || s.syncing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Pal.tertiaryFixed,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Pal.tertiary),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(color: Pal.tertiary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('sync.queued', {'n': '${s.queued}'}),
                            style: body(13, w: FontWeight.w800, c: Pal.tertiaryDeep),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: s.syncing
                      ? null
                      : () async {
                          final r = await s.syncOutbox();
                          if (context.mounted)
                            toast(
                              context,
                              r.sent > 0 ? context.trRead('sync.sent', {'n': '${r.sent}'}) : context.trRead('sync.offline'),
                              error: r.sent == 0,
                            );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        s.syncing
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync, size: 17, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          context.tr('sync.button'),
                          style: head(13, w: FontWeight.w700, c: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
