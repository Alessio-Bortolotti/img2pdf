import 'package:flutter/material.dart';

import '../theme.dart';

/// Pulsante quadrato arrotondato con icona.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 20,
    this.color = AppColors.surface,
    this.iconColor = AppColors.textSoft,
    this.radius = 14,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;
  final double radius;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              size: iconSize,
              color: onTap == null ? iconColor.withAlpha(90) : iconColor),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Pulsante principale con gradiente indaco.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailing,
    this.height = 60,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x803443B8), blurRadius: 24, offset: Offset(0, 10)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17)),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    Text(trailing!,
                        style: const TextStyle(
                            color: Color(0xBFFFFFFF),
                            fontWeight: FontWeight.w500,
                            fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip selezionabile.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.selectedColor = AppColors.primaryDeep,
    this.selectedTextColor = Colors.white,
    this.color = AppColors.surface2,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color selectedColor;
  final Color selectedTextColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? selectedTextColor : AppColors.textSoft;
    return Material(
      color: selected ? selectedColor : color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 36,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      color: onTap == null ? fg.withAlpha(90) : fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Selettore a segmenti (stile pillola).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String, IconData)> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        for (final (v, label, icon) in options)
          Expanded(
            child: GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 36,
                decoration: BoxDecoration(
                  color: v == value ? AppColors.bg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: v == value ? AppColors.primary : AppColors.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: onChanged == null
                                ? AppColors.muted.withAlpha(90)
                                : (v == value
                                    ? AppColors.primary
                                    : AppColors.muted),
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Etichetta di sezione maiuscola.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          )),
    );
  }
}

/// Bordo tratteggiato arrotondato.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    this.color = const Color(0xFF3A3F5C),
    this.radius = 22,
    this.dash = 7,
    this.gap = 6,
    this.strokeWidth = 2,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) => old.color != color;
}
