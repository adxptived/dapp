// Эффекты интерфейса: нажатие с пружинкой, «жидкое стекло», появление элементов, анимированные числа, переходы.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Кнопка без квадратной подсветки: при нажатии слегка сжимается и тускнеет, даёт тактильный отклик.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96, this.haptic = true});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: !enabled ? 0.45 : (_down ? 0.82 : 1),
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// «Жидкое стекло»: размытие и насыщение того, что позади, полупрозрачная заливка, блик сверху
/// и световая грань по контуру (ярче слева-сверху, как у стекла на свету).
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double tint;
  final Color color;
  const Glass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(rCard)),
    this.padding = EdgeInsets.zero,
    this.blur = 28,
    this.tint = 0.45,
    this.color = const Color(0xFF1D1A24),
  });

  static final _saturate = ColorFilter.matrix(<double>[
    1.35, -0.25, -0.10, 0, 0, //
    -0.10, 1.25, -0.15, 0, 0, //
    -0.10, -0.25, 1.35, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.compose(outer: _saturate, inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur)),
        child: CustomPaint(
          foregroundPainter: GlassEdgePainter(radius),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(color, Colors.white, 0.10)!.withValues(alpha: tint),
                  color.withValues(alpha: tint),
                  color.withValues(alpha: (tint + 0.1).clamp(0, 1)),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Световая грань и блик стекла (рисуется поверх содержимого).
class GlassEdgePainter extends CustomPainter {
  final BorderRadius radius;
  final double strength;
  GlassEdgePainter(this.radius, {this.strength = 1});
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = radius.toRRect(rect).deflate(0.6);
    // грань: свет падает слева-сверху
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.38 * strength),
            Colors.white.withValues(alpha: 0.06 * strength),
            Colors.white.withValues(alpha: 0.02 * strength),
            Colors.white.withValues(alpha: 0.16 * strength),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
    // блик в верхней части
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.07 * strength), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlassEdgePainter o) => o.radius != radius || o.strength != strength;
}

/// Живой фон: тёмная база и медленно плывущие мягкие цветные пятна — их видно сквозь стеклянные карточки.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});
  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _AuroraPainter(_c), size: Size.infinite),
      );
}

class _AuroraPainter extends CustomPainter {
  final Animation<double> t;
  _AuroraPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = C.bg);
    final a = t.value * 2 * math.pi;
    final w = size.width, h = size.height;
    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    blob(Offset(w * (0.25 + 0.10 * math.sin(a)), h * (0.06 + 0.03 * math.cos(a))), w * 0.95, const Color(0x8A5A3FD0));
    blob(Offset(w * (0.95 + 0.08 * math.cos(a * 1.3)), h * (0.30 + 0.05 * math.sin(a))), w * 0.75, const Color(0x553F55D8));
    blob(Offset(w * (0.05 + 0.08 * math.sin(a * 0.8)), h * (0.62 + 0.04 * math.cos(a * 1.1))), w * 0.70, const Color(0x40A048C8));
    blob(Offset(w * (0.75 + 0.06 * math.cos(a)), h * (0.92 + 0.02 * math.sin(a))), w * 0.65, const Color(0x333B2D8F));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter o) => false;
}

/// Плавное появление снизу с задержкой по номеру элемента (лесенка).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 18});
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!TickerMode.of(context)) {
      _c.value = 1; // экран строится в фоне — без анимации, чтобы ничего не «застряло» невидимым
      return;
    }
    final delay = (widget.index.clamp(0, 8)) * 45;
    if (delay == 0) {
      _c.forward();
    } else {
      _t = Timer(Duration(milliseconds: delay), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.offset), child: child),
        ),
        child: widget.child,
      );
}

/// Число, которое «докручивается» до нового значения.
class AnimatedNumber extends StatelessWidget {
  final num value;
  final TextStyle style;
  final String Function(num)? format;
  final Duration duration;
  const AnimatedNumber(this.value, {super.key, required this.style, this.format, this.duration = const Duration(milliseconds: 700)});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(format != null ? format!(v) : v.round().toString(), style: style),
      );
}

/// Переход между экранами: лёгкий сдвиг + проявление.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );

/// Нижняя «стеклянная» шторка.
Future<T?> showGlassSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, MediaQuery.of(c).viewInsets.bottom + 10),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Flexible(child: builder(c)),
          ]),
        ),
      ),
    ),
  );
}

/// Выбор одного значения в стеклянной шторке.
Future<V?> pickOption<V>(BuildContext context, String title, Map<V, String> options, V current) {
  return showGlassSheet<V>(
    context,
    (c) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 10), child: Text(title, style: T.title)),
        for (final e in options.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Pressable(
              onTap: () => Navigator.of(c).pop(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: e.key == current ? C.lime : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(e.value,
                        style: T.body.copyWith(color: e.key == current ? C.onLime : C.text, fontWeight: FontWeight.w700)),
                  ),
                  if (e.key == current) const Icon(Icons.check_rounded, color: C.onLime, size: 20),
                ]),
              ),
            ),
          ),
      ],
    ),
  );
}
