import 'package:flutter/material.dart';


class GamepadButtonWidget extends StatefulWidget {
  final String label;
  final Color color;
  final double size;
  final void Function(bool pressed) onChanged;
  final bool pill;
  final bool solid;
  final IconData? icon;

  /// Konten kustom, menggantikan label/ikon. Dipakai untuk simbol khas
  /// PlayStation (segitiga, bulat, kotak, silang).
  final Widget? child;

  /// Ketebalan border; null berarti tanpa border.
  final double? borderWidth;

  /// Warna border bila [borderWidth] diberikan.
  final Color? borderColor;

  /// Ukuran font label.
  final double? fontSize;

  const GamepadButtonWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.color = Colors.white,
    this.size = 56,
    this.pill = false,
    this.solid = true,
    this.icon,
    this.child,
    this.borderWidth,
    this.borderColor,
    this.fontSize,
  });

  @override
  State<GamepadButtonWidget> createState() => _GamepadButtonWidgetState();
}

class _GamepadButtonWidgetState extends State<GamepadButtonWidget> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.solid ? widget.color : widget.color.withOpacity(0.18);
    final pressedColor = widget.solid ? Color.lerp(widget.color, Colors.white, 0.35)! : widget.color.withOpacity(0.9);

    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.pill ? widget.size * 1.8 : widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed ? pressedColor : baseColor,
          borderRadius: BorderRadius.circular(widget.size / 2),
          border: widget.borderWidth == null
              ? null
              : Border.all(
                  color: widget.borderColor ?? widget.color,
                  width: widget.borderWidth!,
                ),
          boxShadow: widget.solid && widget.borderWidth == null
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: widget.child ??
            (widget.icon != null
                ? Icon(widget.icon, color: Colors.white, size: widget.size * 0.5)
                : Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.solid
                          ? Colors.white
                          : (_pressed ? Colors.black : Colors.white.withOpacity(0.85)),
                      fontWeight: FontWeight.bold,
                      fontSize: widget.fontSize ?? (widget.pill ? 12 : 18),
                    ),
                  )),
      ),
    );
  }
}
