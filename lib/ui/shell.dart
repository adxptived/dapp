import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../services/updater.dart';
import 'screens/analytics.dart';
import 'screens/home.dart';
import 'screens/rating.dart';
import 'screens/search.dart';
import 'screens/settings.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  static final GlobalKey<ShellState> shellKey = GlobalKey<ShellState>();
  static bool skipStartup = false; // тесты/скриншоты: без сети при запуске
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> with WidgetsBindingObserver {
  int index = 0;
  final _navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  void go(int i) {
    if (i == index) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => index = i);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Shell.skipStartup) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<Store>();
      store.autoBackup();
      if (store.players.isNotEmpty) store.refreshAll();
      if (store.settings.autoUpdateCheck && mounted) {
        await Updater.checkAndPrompt(context, store, silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !Shell.skipStartup) {
      final store = context.read<Store>();
      store.reload().then((_) {
        if (store.players.isNotEmpty) store.refreshAll();
      });
    }
  }

  Widget _tab(int i, Widget root) => Offstage(
        offstage: index != i,
        child: TickerMode(
          enabled: index == i,
          child: Navigator(
            key: _navKeys[i],
            onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => root, settings: s),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (index != 0) {
          setState(() => index = 0);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(children: [
          _tab(0, const HomeScreen()),
          _tab(1, const RatingScreen()),
          _tab(2, const AnalyticsScreen()),
          _tab(3, const SearchScreen()),
          _tab(4, const SettingsScreen()),
        ]),
        bottomNavigationBar: _BottomNav(index: index, onTap: go),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  static const _icons = [
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.leaderboard_outlined, Icons.leaderboard_rounded, 'Рейтинг'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Аналитика'),
    (Icons.search_rounded, Icons.manage_search_rounded, 'Поиск'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Настройки'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 0, 32, bottom + 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: C.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: C.stroke),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (var i = 0; i < _icons.length; i++)
            Tooltip(
              message: _icons[i].$3,
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: i == index ? C.surface3 : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(i == index ? _icons[i].$2 : _icons[i].$1,
                      color: i == index ? C.lime : C.muted, size: 22),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
