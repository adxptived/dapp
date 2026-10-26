// Общие виджеты в стиле макета: карточки, круглые кнопки, шапка, таблицы, бар-метр, кольцо, мини-графики.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/refdata.dart';
import '../logic/ranks.dart';
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
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: C.stroke.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: content)),
    );
  }
}

class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double size;
  final Color? color;
  final String? tooltip;
  const CircleBtn(this.icon, {super.key, this.onTap, this.filled = false, this.size = 46, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: filled ? C.lime : (color ?? C.surface2),
      shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: C.stroke)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.44, color: filled ? C.onLime : C.text),
        ),
      ),
    );
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
    final Widget img = (url != null && url!.isNotEmpty)
        ? Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)
        : placeholder;
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
    if (h == null) return ClipRRect(borderRadius: BorderRadius.circular(radius), child: ph);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(portrait ? h.image : h.icon,
          width: w, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
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
    if (it == null) return ClipRRect(borderRadius: BorderRadius.circular(4), child: ph);
    return Tooltip(
      message: it.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(it.image, width: w, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
      ),
    );
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
              Image.network(url, width: size, height: size, errorBuilder: (_, __, ___) => const SizedBox()),
              if (stars != null) Image.network(stars, width: size, height: size, errorBuilder: (_, __, ___) => const SizedBox()),
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
class TopBar extends StatelessWidget {
  final String title;
  final IconData? leading;
  final VoidCallback? onLeading;
  final Widget? trailing;
  const TopBar({super.key, required this.title, this.leading, this.onLeading, this.trailing});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        CircleBtn(leading ?? (canPop ? Icons.arrow_back_ios_new_rounded : Icons.calendar_today_outlined),
            onTap: onLeading ?? (canPop ? () => Navigator.of(context).pop() : null)),
        Expanded(child: Text(title, textAlign: TextAlign.center, style: T.sub, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 46, child: trailing ?? const SizedBox()),
      ]),
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: dark ? C.surface2 : (onTap == null ? C.limeDim : C.lime),
        shape: StadiumBorder(side: dark ? const BorderSide(color: C.stroke) : BorderSide.none),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
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
    return Material(
      color: lime ? C.lime : C.surface2,
      shape: StadiumBorder(side: lime ? BorderSide.none : const BorderSide(color: C.stroke)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(text, style: T.small.copyWith(color: lime ? C.onLime : C.text, fontWeight: FontWeight.w600)),
            if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 16, color: lime ? C.onLime : C.text)],
          ]),
        ),
      ),
    );
  }
}

/// Выпадающий фильтр-«чип» (как Movement Type ⌄ на макете).
class DropChip<V> extends StatelessWidget {
  final String label;
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;
  const DropChip({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<V>(
      color: C.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rInner)),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(children: [
              Expanded(child: Text(e.value, style: T.body)),
              if (e.key == value) const Icon(Icons.check_rounded, color: C.lime, size: 18),
            ]),
          )
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(rInner),
          border: Border.all(color: C.stroke),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: T.tiny),
          Text(options[value] ?? '', style: T.tiny.copyWith(color: C.text)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ]),
      ),
    );
  }
}

/// Сегментный переключатель (например, периоды).
class Segments<V> extends StatelessWidget {
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;
  const Segments({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(40), border: Border.all(color: C.stroke)),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: e.key == value ? C.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(40),
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: T.small.copyWith(
                        color: e.key == value ? C.onLime : C.muted, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]),
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
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(rInner)),
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
        decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: C.bg, width: 1.5)) : null),
        child: Row(children: [Expanded(flex: 5, child: l), Expanded(flex: 6, child: Align(alignment: Alignment.centerLeft, child: r))]),
      );
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

/// Бар-метр из тонких вертикальных полосок (как «Monthly Sales Goal»).
class BarMeter extends StatelessWidget {
  final double fraction;
  final int bars;
  final double height;
  const BarMeter(this.fraction, {super.key, this.bars = 40, this.height = 44});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _BarMeterPainter(fraction.clamp(0, 1).toDouble(), bars)),
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
    final lit = (f * n).round();
    for (var i = 0; i < n; i++) {
      final p = Paint()..color = i < lit ? C.lime : C.faint.withValues(alpha: 0.55);
      final x = i * gap + (gap - w) / 2;
      canvas.drawRRect(RRect.fromLTRBR(x, 0, x + w, size.height, Radius.circular(w / 2)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BarMeterPainter o) => o.f != f || o.n != n;
}

/// Кольцевая диаграмма с градиентом (как «Inventory Distribution»).
class Donut extends StatelessWidget {
  final List<(double, Color)> segments;
  final Widget center;
  final double size;
  final double stroke;
  const Donut({super.key, required this.segments, required this.center, this.size = 200, this.stroke = 22});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(segments, stroke),
          child: Center(child: center),
        ),
      );
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> seg;
  final double stroke;
  _DonutPainter(this.seg, this.stroke);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2 + 2);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = C.surface3;
    canvas.drawArc(r, 0, math.pi * 2, false, bg);
    final total = seg.fold<double>(0, (a, b) => a + b.$1);
    if (total <= 0) return;
    var start = -math.pi / 2;
    const gap = 0.05;
    for (final s in seg) {
      final sweep = s.$1 / total * math.pi * 2;
      if (sweep <= 0) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [s.$2.withValues(alpha: 0.55), s.$2],
          transform: const GradientRotation(0),
        ).createShader(r);
      canvas.drawArc(r, start + (seg.length > 1 ? gap / 2 : 0), math.max(0.001, sweep - (seg.length > 1 ? gap : 0)), false, p);
      start += sweep;
    }
    // внешнее тонкое кольцо-«тик»
    final ticks = Paint()
      ..color = C.faint.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final c = rect.center;
    final outer = size.width / 2;
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (outer - 1),
          c + Offset(math.cos(a), math.sin(a)) * (outer - 4), ticks);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter o) => true;
}

/// Столбики (как «Sales increase»): значения, подписи, выделенный столбик с плашкой.
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
    return SizedBox(
      height: height + 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (i == highlight && tag != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: C.lime, borderRadius: BorderRadius.circular(8)),
                  child: Text(tag!, style: T.tiny.copyWith(color: C.onLime, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              _bars(values[i] / maxV, i == highlight, i > (highlight ?? values.length)),
              const SizedBox(height: 6),
              Text(labels[i], style: T.tiny.copyWith(fontSize: 10, color: i == highlight ? C.text : C.muted)),
            ]),
          ),
      ]),
    );
  }

  Widget _bars(double f, bool hi, bool future) {
    final h = math.max(4.0, (height - 24) * f);
    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var k = 0; k < 3; k++)
        Container(
          width: 4,
          height: h * (k == 1 ? 1 : 0.62 + 0.1 * k),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: future ? C.faint.withValues(alpha: 0.4) : (hi ? C.lime : C.lime.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ]);
  }
}

/// Линейный график нескольких серий [(x, y)].
class LineChart extends StatelessWidget {
  final List<(String, Color, List<(double, double)>)> series;
  final double height;
  final String Function(double)? xLabel;
  const LineChart({super.key, required this.series, this.height = 220, this.xLabel});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(series, xLabel)),
      );
}

class _LinePainter extends CustomPainter {
  final List<(String, Color, List<(double, double)>)> series;
  final String Function(double)? xLabel;
  _LinePainter(this.series, this.xLabel);
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [Expanded(child: Text(text, style: T.title)), if (trailing != null) trailing!]),
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rInner),
        child: Padding(
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
        ),
      );
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String text, {String ok = 'Да'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: T.title),
      content: Text(text, style: T.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена', style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok, style: const TextStyle(color: C.lime))),
      ],
    ),
  );
  return r == true;
}

Future<String?> prompt(BuildContext context, String title,
    {String? initial, String? hint, TextInputType? keyboard}) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: T.title),
      content: TextField(controller: ctl, autofocus: true, keyboardType: keyboard, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена', style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Готово', style: TextStyle(color: C.lime))),
      ],
    ),
  );
  return r;
}

/// Скролл-экран с шапкой и отступом под нижнее меню.
class PageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final IconData? leading;
  final VoidCallback? onLeading;
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.onRefresh,
    this.leading,
    this.onLeading,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: children,
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          TopBar(title: title, trailing: trailing, leading: leading, onLeading: onLeading),
          Expanded(
            child: onRefresh == null
                ? list
                : RefreshIndicator(
                    color: C.onLime, backgroundColor: C.lime, onRefresh: onRefresh!, child: list),
          ),
        ]),
      ),
    );
  }
}
