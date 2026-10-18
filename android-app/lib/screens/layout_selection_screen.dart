import 'package:flutter/material.dart';

import '../models/gamepad_settings.dart';
import '../theme.dart';

/// Layar pemilihan layout gamepad yang muncul setelah koneksi berhasil.
///
/// Pengguna memilih Xbox atau PlayStation, lalu langsung masuk ke gamepad
/// dengan layout tersebut.
class LayoutSelectionScreen extends StatefulWidget {
  final GamepadSettings settings;
  final void Function(ButtonLayout layout) onSelected;

  const LayoutSelectionScreen({
    super.key,
    required this.settings,
    required this.onSelected,
  });

  @override
  State<LayoutSelectionScreen> createState() => _LayoutSelectionScreenState();
}

class _LayoutSelectionScreenState extends State<LayoutSelectionScreen> {
  ButtonLayout? _selected;

  void _choose(ButtonLayout layout) {
    setState(() => _selected = layout);
  }

  void _confirm() {
    final chosen = _selected;
    if (chosen == null) return;
    widget.settings.saveLayout(chosen);
    widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Pengguna harus memilih salah satu layout; cegah keluar tanpa memilih.
      canPop: false,
      child: Scaffold(
      backgroundColor: AppColors.gamepadBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.gradientTop, AppColors.gradientBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.sports_esports, color: Colors.white, size: 44),
              const SizedBox(height: 12),
              const Text(
                'Pilih Layout Gamepad',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Koneksi berhasil. Tentukan tampilan tombol yang kamu pakai.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _LayoutCard(
                      layout: ButtonLayout.xbox,
                      selected: _selected == ButtonLayout.xbox,
                      painter: _XboxPreviewPainter(),
                      subtitle: 'A / B / X / Y dengan warna khas Xbox',
                      onTap: () => _choose(ButtonLayout.xbox),
                    ),
                    const SizedBox(height: 14),
                    _LayoutCard(
                      layout: ButtonLayout.playstation,
                      selected: _selected == ButtonLayout.playstation,
                      painter: _PsPreviewPainter(),
                      subtitle: 'Segitiga / Bulat / Silang / Kotak ala DualSense',
                      onTap: () => _choose(ButtonLayout.playstation),
                    ),
                    const SizedBox(height: 14),
                    _LayoutCard(
                      layout: ButtonLayout.classic,
                      selected: _selected == ButtonLayout.classic,
                      painter: null,
                      subtitle: 'Layout asli aplikasi sebelum ada pilihan',
                      onTap: () => _choose(ButtonLayout.classic),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selected == null
                          ? Colors.white.withOpacity(0.10)
                          : AppColors.iconBg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _selected == null ? null : _confirm,
                    child: Text(
                      _selected == null
                          ? 'PILIH LAYOUT DULU'
                          : 'LANJUT KE GAMEPAD',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: _selected == null
                            ? Colors.white.withOpacity(0.5)
                            : Colors.white,
                      ),
                    ),
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

class _LayoutCard extends StatelessWidget {
  final ButtonLayout layout;
  final bool selected;
  final CustomPainter? painter;
  final String subtitle;
  final VoidCallback onTap;

  const _LayoutCard({
    required this.layout,
    required this.selected,
    required this.painter,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.iconBg.withOpacity(0.30)
              : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Row(
          children: [
            // Pratinjau layout (gambar vektor, bukan aset eksternal).
            SizedBox(
              width: 104,
              height: 60,
              child: painter != null
                  ? CustomPaint(painter: painter!)
                  : const Icon(Icons.gamepad, color: Colors.white70, size: 44),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layout.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.accent : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pratinjau umum: siluet controller + penanda khas tiap merek.
abstract class _BasePreviewPainter extends CustomPainter {
  Color get stroke;
  Color get accent;

  void paintBrandMark(Canvas canvas, Size size);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = stroke;

    // Badan controller: rounded rect dengan dua "genggaman" melengkung.
    final path = Path()
      ..moveTo(w * 0.08, h * 0.34)
      ..quadraticBezierTo(w * 0.5, h * 0.06, w * 0.92, h * 0.34)
      ..quadraticBezierTo(w * 1.00, h * 0.78, w * 0.74, h * 0.86)
      ..quadraticBezierTo(w * 0.58, h * 0.88, w * 0.5, h * 0.66)
      ..quadraticBezierTo(w * 0.42, h * 0.88, w * 0.26, h * 0.86)
      ..quadraticBezierTo(w * 0.00, h * 0.78, w * 0.08, h * 0.34)
      ..close();
    canvas.drawPath(path, body);

    // D-pad kiri dan sekumpulan tombol kanan sebagai isyarat umum.
    final dot = Paint()..color = stroke.withOpacity(0.75);
    canvas.drawCircle(Offset(w * 0.24, h * 0.52), 3.2, dot);
    for (final p in [
      Offset(w * 0.76, h * 0.44),
      Offset(w * 0.83, h * 0.52),
      Offset(w * 0.76, h * 0.60),
      Offset(w * 0.69, h * 0.52),
    ]) {
      canvas.drawCircle(p, 2.6, dot);
    }

    paintBrandMark(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _BasePreviewPainter oldDelegate) => false;
}

/// Xbox:Xbox "X" besar di tengah badan.
class _XboxPreviewPainter extends _BasePreviewPainter {
  @override
  Color get stroke => const Color(0xFF9CCC65);
  @override
  Color get accent => const Color(0xFF7CB342);

  @override
  void paintBrandMark(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = w * 0.50;
    final cy = h * 0.47;
    final r = h * 0.14;
    // Huruf X: dua garis berpotongan.
    canvas.drawLine(Offset(cx - r, cy - r), Offset(cx + r, cy + r), paint);
    canvas.drawLine(Offset(cx + r, cy - r), Offset(cx - r, cy + r), paint);
  }
}

/// PlayStation: DualSense khas dengan light bar biru di tengah.
class _PsPreviewPainter extends _BasePreviewPainter {
  @override
  Color get stroke => const Color(0xFF90CAF9);
  @override
  Color get accent => const Color(0xFF42A5F5);

  @override
  void paintBrandMark(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Light bar biru khas DualSense.
    final bar = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.455),
        width: w * 0.44,
        height: h * 0.055,
      ),
      Radius.circular(h * 0.03),
    );
    canvas.drawRRect(bar, Paint()..color = accent);

    // Dua titik kecil sebagai penanda touchpad.
    final dot = Paint()..color = accent.withOpacity(0.85);
    canvas.drawCircle(Offset(w * 0.50, h * 0.335), 1.8, dot);
    canvas.drawCircle(Offset(w * 0.50, h * 0.575), 1.8, dot);
  }
}