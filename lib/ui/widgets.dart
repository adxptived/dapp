// Общие виджеты в стиле макета: карточки, круглые кнопки, шапка, таблицы, бар-метр, кольцо, мини-графики.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/refdata.dart';
import '../logic/ranks.dart';
import 'fx.dart';
import 'net_image.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;
  final double radius;
  final Gradient? gradient;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = C.surface,
    this.onTap,
    this.radius = rCard,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, scale: 0.975, child: card);
  }
}

class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double size;
  final Color? color;
  final String? tooltip;
  final bool glass;
  const CircleBtn(this.icon,
      {super.key, this.onTap, this.filled = false, this.size = 46, this.color, this.tooltip, this.glass = false});

  @override
  Widget build(BuildContext context) {
    final iconW = Icon(icon, size: size * 0.44, color: filled ? C.onLime : C.text);
    final Widget body = glass
        ? Glass(radius: BorderRadius.circular(size), tint: 0.35, child: SizedBox(width: size, height: size, child: Center(child: iconW)))
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? C.lime : (color ?? C.surface2),
              border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: filled ? [BoxShadow(color: C.lime.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -4)] : null,
            ),
            child: Center(child: iconW),
          );
    final w = Pressable(onTap: onTap, scale: 0.88, child: body);
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class Avatar extends StatelessWidget {
  final String? url;
  final double size;
  final String? fallback;
  final int? badge;
  final bool ring;
  const Avatar(this.url, {super.key, this.size = 44, this.fallback, this.badge, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final letter = (fallback ?? '?').isEmpty ? '?' : fallback!.characters.first.toUpperCase();
    final placeholder = Container(
      width: size,
      height: size,
      color: C.surface3,
      alignment: Alignment.center,
      child: Text(letter, style: T.sub.copyWith(fontSize: size * 0.4)),
    );
    final img = NetImage(url, width: size, height: size, placeholder: placeholder);
    final circle = Container(
      decoration: ring ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.lime, width: 2)) : null,
      padding: ring ? const EdgeInsets.all(2) : null,
      child: ClipOval(child: img),
    );
    if (badge == null) return circle;
    return Stack(clipBehavior: Clip.none, children: [
      circle,
      Positioned(
        left: -4,
        top: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: C.lime, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.bg, width: 2)),
          child: Text('$badge', style: T.tiny.copyWith(color: C.onLime, fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}

class HeroIcon extends StatelessWidget {
  final int? heroId;
  final double height;
  final bool portrait;
  final double radius;
  const HeroIcon(this.heroId, {super.key, this.height = 32, this.portrait = true, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final h = RefData.I.hero(heroId);
    final w = portrait ? height * 16 / 9 : height;
    final ph = Container(width: w, height: height, color: C.surface3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: h == null ? ph : NetImage(portrait && !RefData.I.lowData ? h.image : h.icon, width: w, height: height, placeholder: ph),
    );
  }
}

class ItemIcon extends StatelessWidget {
  final int? itemId;
  final double height;
  const ItemIcon(this.itemId, {super.key, this.height = 24});
  @override
  Widget build(BuildContext context) {
    final it = RefData.I.item(itemId);
    final w = height * 88 / 64;
    final ph = Container(width: w, height: height, color: C.surface3);
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: it == null ? ph : NetImage(it.image, width: w, height: height, placeholder: ph),
    );
    return it == null ? img : Tooltip(message: it.name, child: img);
  }
}

class RankBadge extends StatelessWidget {
  final int? rankTier;
  final int? leaderboard;
  final double size;
  final bool label;
  const RankBadge(this.rankTier, {super.key, this.leaderboard, this.size = 28, this.label = true});

  @override
  Widget build(BuildContext context) {
    final url = rankIconUrl(rankTier);
    final stars = rankStarsUrl(rankTier);
    final icon = url == null
        ? Icon(Icons.shield_outlined, size: size, color: C.faint)
        : SizedBox(
            width: size,
            height: size,
            child: Stack(children: [
              NetImage(url, width: size, height: size, fit: BoxFit.contain),
              if (stars != null) NetImage(stars, width: size, height: size, fit: BoxFit.contain),
            ]),
          );
    if (!label) return icon;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      icon,
      const SizedBox(width: 6),
      Text(rankLabel(rankTier, leaderboard), style: T.small),
    ]);
  }
}

/// Шапка экрана: круглая кнопка слева, заголовок по центру, аватар справа.
/// Верхняя панель: плавающая стеклянная капсула (как нижнее меню) — кнопка, заголовок, аватар.
class TopBar extends StatelessWidget {
  final String title;
  final IconData? leading;
  final VoidCallback? onLeading;
  final Widget? trailing;
  const TopBar({super.key, required this.title, this.leading, this.onLeading, this.trailing});

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final icon = leading ?? (canPop ? Icons.arrow_back_ios_new_rounded : null);
    final tap = onLeading ?? (canPop ? () => Navigator.of(context).pop() : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Glass(
        radius: BorderRadius.circular(32),
        color: Colors.white,
        tint: 0.06,
        blur: 16,
        child: SizedBox(
          height: height,
          child: Row(children: [
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 44,
              child: icon == null
                  ? null
                  : Pressable(
                      scale: 0.85,
                      onTap: tap,
                      child: Center(child: Icon(icon, size: icon == Icons.arrow_back_ios_new_rounded ? 19 : 22, color: Colors.white)),
                    ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(title,
                    key: ValueKey(title),
                    textAlign: TextAlign.center,
                    style: T.sub.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: trailing == null ? null : FittedBox(fit: BoxFit.scaleDown, child: trailing),
            ),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}

class LimeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;
  final bool dark;
  const LimeButton(this.label, {super.key, this.onTap, this.icon, this.busy = false, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? C.text : C.onLime;
    return Pressable(
      onTap: busy ? null : onTap,
      scale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: dark ? C.surface2 : C.lime,
          borderRadius: BorderRadius.circular(40),
          border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.14)) : null,
          boxShadow: dark || onTap == null ? null : [BoxShadow(color: C.lime.withValues(alpha: 0.28), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 8))],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: busy
                ? SizedBox(key: const ValueKey('b'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                : Row(key: ValueKey(label), mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
                    Text(label, style: T.sub.copyWith(color: fg)),
                  ]),
          ),
        ),
      ),
    );
  }
}

class SmallPill extends StatelessWidget {
  final String text;
  final bool lime;
  final VoidCallback? onTap;
  final IconData? icon;
  const SmallPill(this.text, {super.key, this.lime = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: lime ? C.lime : C.glass,
        borderRadius: BorderRadius.circular(30),
        border: lime ? null : Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: T.small.copyWith(color: lime ? C.onLime : C.text, fontWeight: FontWeight.w600)),
        if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 16, color: lime ? C.onLime : C.text)],
      ]),
    );
    return onTap == null ? body : Pressable(onTap: onTap, child: body);
  }
}

/// Фильтр-«чип» (как Movement Type ⌄ на макете): выбор в стеклянной шторке.
class DropChip<V> extends StatelessWidget {
  final String label;
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;
  const DropChip({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () async {
        final v = await pickOption<V>(context, label, options, value);
        if (v != null) onChanged(v);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.glass,
          borderRadius: BorderRadius.circular(rInner),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: T.tiny),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(options[value] ?? '', key: ValueKey(value), style: T.tiny.copyWith(color: C.text)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ]),
      ),
    );
  }
}

/// Сегментный переключатель с «едущей» лаймовой плашкой.
class Segments<V> extends StatelessWidget {
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;
  const Segments({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    final idx = keys.indexOf(value).clamp(0, keys.length - 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.glass2,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / keys.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            left: w * idx,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: C.lime,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(color: C.lime.withValues(alpha: 0.3), blurRadius: 14, spreadRadius: -4)],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < keys.length; i++)
              Expanded(
                child: Pressable(
                  scale: 0.92,
                  onTap: () => onChanged(keys[i]),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      style: T.small.copyWith(color: i == idx ? C.onLime : C.muted, fontWeight: FontWeight.w700),
                      child: Text(options[keys[i]]!, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Таблица «метрика — значение» с тёмными строками.
class KvTable extends StatelessWidget {
  final String? headLeft, headRight;
  final List<(String, Widget)> rows;
  const KvTable({super.key, this.headLeft, this.headRight, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: C.glass2, borderRadius: BorderRadius.circular(rInner)),
      child: Column(children: [
        if (headLeft != null)
          _row(Text(headLeft!, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)),
              Text(headRight ?? '', style: T.small.copyWith(color: C.text)), divider: true),
        for (var i = 0; i < rows.length; i++)
          _row(Text(rows[i].$1, style: T.small.copyWith(color: C.text, fontWeight: FontWeight.w700)), rows[i].$2,
              divider: i < rows.length - 1),
      ]),
    );
  }

  Widget _row(Widget l, Widget r, {bool divider = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: 1)) : null),
        child: Row(children: [Expanded(flex: 5, child: l), Expanded(flex: 6, child: Align(alignment: Alignment.centerLeft, child: r))]),
      );
}

/// Сетка показателей: подпись мелко, значение крупно — вместо «табличного» вида.
class StatGrid extends StatelessWidget {
  final List<StatItem> items;
  final int columns;
  const StatGrid(this.items, {super.key, this.columns = 2});
  @override
  Widget build(BuildContext context) {
    final rows = <List<StatItem>>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(items.sublist(i, i + columns > items.length ? items.length : i + columns));
    }
    return Column(children: [
      for (var r = 0; r < rows.length; r++)
        Padding(
          padding: EdgeInsets.only(bottom: r == rows.length - 1 ? 0 : 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: i < rows[r].length ? _tile(rows[r][i]) : const SizedBox()),
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _tile(StatItem it) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: it.accent ? C.lime.withValues(alpha: 0.14) : C.glass2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: it.accent ? C.lime.withValues(alpha: 0.35) : C.glass),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            if (it.icon != null) ...[Icon(it.icon, size: 13, color: C.muted), const SizedBox(width: 4)],
            Expanded(child: Text(it.label, style: T.tiny, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(it.value, style: T.title.copyWith(fontSize: 19, color: it.color ?? C.text, fontWeight: FontWeight.w700)),
          ),
          if (it.sub != null) ...[
            const SizedBox(height: 2),
            Text(it.sub!, style: T.tiny.copyWith(color: it.subColor ?? C.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      );
}

class StatItem {
  final String label, value;
  final String? sub;
  final Color? color, subColor;
  final IconData? icon;
  final bool accent;
  const StatItem(this.label, this.value, {this.sub, this.color, this.subColor, this.icon, this.accent = false});
}

Text valueText(String s, {Color? color}) => Text(s, style: T.small.copyWith(color: color ?? C.text));

String signed(num v) => v > 0 ? '+${v.round()}' : '${v.round()}';

Color deltaColor(num v) => v > 0 ? C.lime : (v < 0 ? C.red : C.muted);

class DeltaText extends StatelessWidget {
  final num value;
  final String suffix;
  final TextStyle? style;
  const DeltaText(this.value, {super.key, this.suffix = '', this.style});
  @override
  Widget build(BuildContext context) =>
      Text('${signed(value)}$suffix', style: (style ?? T.small).copyWith(color: deltaColor(value), fontWeight: FontWeight.w700));
}

/// Последние игры квадратиками: лайм — победа, тёмно-красный — поражение.
class FormDots extends StatelessWidget {
  final List<bool> form;
  final double size;
  const FormDots(this.form, {super.key, this.size = 10});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final w in form)
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(color: w ? C.lime : C.red.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(3)),
          )
      ]);
}

/// Бар-метр из тонких вертикальных полосок (как «Monthly Sales Goal»), заполняется с анимацией.
class BarMeter extends StatelessWidget {
  final double fraction;
  final int bars;
  final double height;
  const BarMeter(this.fraction, {super.key, this.bars = 40, this.height = 44});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, f, __) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _BarMeterPainter(f, bars)),
        ),
      );
}

class _BarMeterPainter extends CustomPainter {
  final double f;
  final int n;
  _BarMeterPainter(this.f, this.n);
  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / n;
    final w = gap * 0.42;
    final exact = f * n;
    for (var i = 0; i < n; i++) {
      final part = (exact - i).clamp(0.0, 1.0);
      final x = i * gap + (gap - w) / 2;
      final r = RRect.fromLTRBR(x, 0, x + w, size.height, Radius.circular(w / 2));
      canvas.drawRRect(r, Paint()..color = C.faint.withValues(alpha: 0.5));
      if (part > 0) canvas.drawRRect(r, Paint()..color = C.lime.withValues(alpha: part));
    }
  }

  @override
  bool shouldRepaint(covariant _BarMeterPainter o) => o.f != f || o.n != n;
}

/// Кольцевая диаграмма с градиентом (как «Inventory Distribution»), раскрывается по кругу.
class Donut extends StatelessWidget {
  final List<(double, Color)> segments;
  final Widget center;
  final double size;
  final double stroke;
  const Donut({super.key, required this.segments, required this.center, this.size = 200, this.stroke = 22});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _DonutPainter(segments, stroke, t), child: Center(child: child)),
        ),
        child: center,
      );
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> seg;
  final double stroke;
  final double t;
  _DonutPainter(this.seg, this.stroke, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2 + 6);
    canvas.drawArc(
        r,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = C.surface3);
    final c = rect.center;
    final outer = size.width / 2;
    final ticks = Paint()
      ..color = C.faint.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * math.pi * 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (outer - 1), c + d * (outer - 4), ticks);
    }
    final total = seg.fold<double>(0, (a, b) => a + b.$1);
    if (total <= 0) return;
    var start = -math.pi / 2;
    final limit = -math.pi / 2 + math.pi * 2 * t;
    final gap = seg.where((s) => s.$1 > 0).length > 1 ? 0.06 : 0.0;
    for (final s in seg) {
      final sweep = s.$1 / total * math.pi * 2;
      if (sweep <= 0) continue;
      final end = math.min(start + sweep - gap, limit);
      if (end > start) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..shader = SweepGradient(
            colors: [s.$2.withValues(alpha: 0.45), s.$2],
            stops: const [0, 1],
            transform: GradientRotation(start),
            endAngle: math.max(0.01, sweep),
          ).createShader(r);
        canvas.drawArc(r, start, end - start, false, p);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter o) => o.t != t || o.seg != seg;
}

/// Столбики (как «Sales increase»): растут при появлении; выделенный столбик с плашкой.
class MiniBars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final int? highlight;
  final String? tag;
  final double height;
  const MiniBars({super.key, required this.values, required this.labels, this.highlight, this.tag, this.height = 120});

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : math.max(1.0, values.reduce(math.max));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) => SizedBox(
        height: height + 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (i == highlight && tag != null)
                  Opacity(
                    opacity: t,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: C.lime, borderRadius: BorderRadius.circular(8)),
                      child: Text(tag!, style: T.tiny.copyWith(color: C.onLime, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                _bars(values[i] / maxV * t, i == highlight),
                const SizedBox(height: 6),
                Text(labels[i], style: T.tiny.copyWith(fontSize: 10, color: i == highlight ? C.text : C.muted)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _bars(double f, bool hi) {
    final h = math.max(4.0, (height - 24) * f);
    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var k = 0; k < 3; k++)
        Container(
          width: 4,
          height: math.max(4.0, h * (k == 1 ? 1 : 0.62 + 0.1 * k)),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: hi ? C.lime : C.lime.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ]);
  }
}

/// Линейный график нескольких серий [(x, y)]; рисуется слева направо.
class LineChart extends StatelessWidget {
  final List<(String, Color, List<(double, double)>)> series;
  final double height;
  final String Function(double)? xLabel;
  const LineChart({super.key, required this.series, this.height = 220, this.xLabel});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(series, xLabel, t)),
        ),
      );
}

class _LinePainter extends CustomPainter {
  final List<(String, Color, List<(double, double)>)> series;
  final String Function(double)? xLabel;
  final double t;
  _LinePainter(this.series, this.xLabel, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final pts = series.expand((s) => s.$3).toList();
    if (pts.isEmpty) return;
    var minX = pts.map((p) => p.$1).reduce(math.min), maxX = pts.map((p) => p.$1).reduce(math.max);
    var minY = pts.map((p) => p.$2).reduce(math.min), maxY = pts.map((p) => p.$2).reduce(math.max);
    if (maxX == minX) maxX = minX + 1;
    if (maxY == minY) {
      maxY += 25;
      minY -= 25;
    }
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;
    const left = 44.0, bottom = 20.0;
    final w = size.width - left - 6, h = size.height - bottom - 6;
    Offset map(double x, double y) => Offset(left + (x - minX) / (maxX - minX) * w, 6 + h - (y - minY) / (maxY - minY) * h);
    final grid = Paint()
      ..color = C.stroke
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = minY + (maxY - minY) * i / 4;
      final o = map(minX, y);
      canvas.drawLine(Offset(left, o.dy), Offset(size.width, o.dy), grid);
      tp.text = TextSpan(text: y.round().toString(), style: T.tiny.copyWith(fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(0, o.dy - tp.height / 2));
    }
    if (xLabel != null) {
      for (var i = 0; i <= 3; i++) {
        final x = minX + (maxX - minX) * i / 3;
        tp.text = TextSpan(text: xLabel!(x), style: T.tiny.copyWith(fontSize: 9));
        tp.layout();
        final o = map(x, minY);
        tp.paint(canvas, Offset((o.dx - tp.width / 2).clamp(left, size.width - tp.width), size.height - bottom + 4));
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, left + w * t + 4, size.height));
    for (final s in series) {
      if (s.$3.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < s.$3.length; i++) {
        final o = map(s.$3[i].$1, s.$3[i].$2);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      if (series.length == 1) {
        final area = Path.from(path)
          ..lineTo(map(s.$3.last.$1, minY).dx, 6 + h)
          ..lineTo(map(s.$3.first.$1, minY).dx, 6 + h)
          ..close();
        canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.$2.withValues(alpha: 0.25), s.$2.withValues(alpha: 0)],
              ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = s.$2
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round);
      final last = map(s.$3.last.$1, s.$3.last.$2);
      canvas.drawCircle(last, 3.5, Paint()..color = s.$2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.t != t || o.series != series;
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Row(children: [Expanded(child: Text(text, style: T.title.copyWith(fontSize: 19, fontWeight: FontWeight.w700))), if (trailing != null) trailing!]),
      );
}

class EmptyState extends StatelessWidget {
  final String title;
  final String? text;
  final Widget? action;
  final IconData icon;
  const EmptyState({super.key, required this.title, this.text, this.action, this.icon = Icons.groups_2_outlined});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(26),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: C.surface2, shape: BoxShape.circle),
            child: Icon(icon, color: C.lime, size: 30),
          ),
          const SizedBox(height: 14),
          Text(title, style: T.title, textAlign: TextAlign.center),
          if (text != null) ...[const SizedBox(height: 6), Text(text!, style: T.small, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      );
}

/// Строка игрока с аватаром (для списков и топов).
class PlayerLine extends StatelessWidget {
  final Player? player;
  final String name;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? lead;
  const PlayerLine({super.key, this.player, required this.name, this.sub, this.trailing, this.onTap, this.lead});
  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        if (lead != null) ...[lead!, const SizedBox(width: 10)],
        Avatar(player?.avatar, size: 38, fallback: name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: T.body.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            if (sub != null) Text(sub!, style: T.small, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: 0.98, child: row);
  }
}

Widget placeBadge(int place) {
  final color = place == 1 ? C.gold : place == 2 ? C.silver : place == 3 ? C.bronze : C.surface3;
  return Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: place <= 3 ? color : C.surface3, shape: BoxShape.circle),
    child: Text('$place', style: T.tiny.copyWith(color: place <= 3 ? C.onLime : C.text, fontWeight: FontWeight.w800)),
  );
}

String fmtDuration(int? s) {
  if (s == null) return '—';
  final m = s ~/ 60, sec = s % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

const _months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
const monthsFull = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
String monthShort(int m) => _months[(m - 1) % 12];

String fmtDate(int ts, {bool time = true}) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final s = '${d.day} ${_months[d.month - 1]}';
  return time ? '$s, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}' : s;
}

String fmtAgo(int ts) {
  final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
  if (diff < 60) return 'только что';
  if (diff < 3600) return '${diff ~/ 60} мин назад';
  if (diff < 86400) return '${diff ~/ 3600} ч назад';
  if (diff < 7 * 86400) return '${diff ~/ 86400} дн назад';
  return fmtDate(ts, time: false);
}

String pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String text, {String ok = 'Да'}) async {
  final r = await showGlassSheet<bool>(
    context,
    (c) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: T.title),
        const SizedBox(height: 8),
        Text(text, style: T.body.copyWith(color: C.muted)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: LimeButton('Отмена', dark: true, onTap: () => Navigator.pop(c, false))),
          const SizedBox(width: 10),
          Expanded(child: LimeButton(ok, onTap: () => Navigator.pop(c, true))),
        ]),
      ]),
    ),
  );
  return r == true;
}

Future<String?> prompt(BuildContext context, String title,
    {String? initial, String? hint, TextInputType? keyboard, bool paste = false}) async {
  final ctl = TextEditingController(text: initial);
  return showGlassSheet<String>(
    context,
    (c) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: T.title),
        const SizedBox(height: 14),
        TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: paste
                ? IconButton(
                    icon: const Icon(Icons.content_paste_rounded, color: C.muted),
                    onPressed: () async {
                      final d = await Clipboard.getData('text/plain');
                      if (d?.text != null) ctl.text = d!.text!.trim();
                    },
                  )
                : null,
          ),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: LimeButton('Отмена', dark: true, onTap: () => Navigator.pop(c))),
          const SizedBox(width: 10),
          Expanded(child: LimeButton('Готово', onTap: () => Navigator.pop(c, ctl.text))),
        ]),
      ]),
    ),
  );
}

/// Экран со стеклянной шапкой поверх контента и «лесенкой» появления блоков.
class PageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final IconData? leading;
  final VoidCallback? onLeading;
  final bool animate;
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.onRefresh,
    this.leading,
    this.onLeading,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final barTop = top + 8;
    final listTop = barTop + TopBar.height + 14;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, listTop, 16, 120),
      children: [
        for (var i = 0; i < children.length; i++) animate ? FadeSlideIn(index: i, child: children[i]) : children[i],
      ],
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [C.glow, Color(0xFF1A1526), C.bg, C.bg],
                stops: [0, 0.25, 0.55, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: onRefresh == null
              ? list
              : RefreshIndicator(
                  color: C.onLime,
                  backgroundColor: C.lime,
                  edgeOffset: listTop - 10,
                  onRefresh: onRefresh!,
                  child: list,
                ),
        ),
        // лёгкое затемнение только под строкой состояния, чтобы часы и значки читались
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top + 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.45), Colors.black.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          top: barTop,
          child: TopBar(title: title, trailing: trailing, leading: leading, onLeading: onLeading),
        ),
      ]),
    );
  }
}
