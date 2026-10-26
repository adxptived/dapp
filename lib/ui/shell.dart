import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/refdata.dart';
import '../data/store.dart';
import '../services/updater.dart';
import 'screens/analytics.dart';
import 'screens/home.dart';
import 'screens/rating.dart';
import 'screens/search.dart';
import 'screens/settings.dart';
import 'fx.dart';
import 'net_image.dart';
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
      // иконки героев — один раз на диск, дальше из кэша
      Future.delayed(const Duration(seconds: 4), () async {
        await RefData.I.refreshIfStale(store.od, store.dir).catchError((_) {});
        await ImageCache2.prefetch(RefData.I.heroes.values.expand((h) => RefData.I.lowData ? [h.icon] : [h.image, h.icon]));
      });
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

  Widget _tab(int i, Widget root) => IgnorePointer(
        ignoring: index != i,
        child: AnimatedOpacity(
          opacity: index == i ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: index == i ? Offset.zero : const Offset(0, 0.015),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: TickerMode(
              enabled: index == i,
              child: Navigator(
                key: _navKeys[i],
                onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => root, settings: s),
              ),
            ),
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
        backgroundColor: C.bg,
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
      padding: EdgeInsets.fromLTRB(28, 0, 28, bottom + 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12))],
        ),
        child: Glass(
          radius: BorderRadius.circular(40),
          color: Colors.white,
          tint: 0.06,
          blur: 16,
          child: SizedBox(
            height: 66,
            child: LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 16) / _icons.length;
              return Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: 8 + w * index + (w - 18) / 2,
                  bottom: 9,
                  width: 18,
                  height: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: C.lime,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [BoxShadow(color: C.lime.withValues(alpha: 0.6), blurRadius: 8)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    for (var i = 0; i < _icons.length; i++)
                      Expanded(
                        child: Semantics(
                          label: _icons[i].$3,
                          button: true,
                          child: Pressable(
                            scale: 0.85,
                            onTap: () => onTap(i),
                            child: SizedBox(
                              height: 66,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                  child: Icon(
                                    i == index ? _icons[i].$2 : _icons[i].$1,
                                    key: ValueKey(i == index),
                                    color: i == index ? C.lime : Colors.white.withValues(alpha: 0.85),
                                    size: 25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
