import 'package:flutter/material.dart';
import '../models/gamepad_settings.dart';
import '../theme.dart';

/// Layar pengaturan untuk mengatur ukuran dan posisi setiap tombol gamepad.
class SettingsScreen extends StatefulWidget {
  final GamepadSettings settings;
  final Map<String, ButtonConfig> configs;
  final void Function(Map<String, ButtonConfig> configs) onSave;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.configs,
    required this.onSave,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, ButtonConfig> _working;
  double _globalMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    // Selalu mulai dari default lengkap, lalu overlay config yang tersimpan
    // supaya tidak pernah ada tombol yang hilang dari daftar.
    _working = DefaultButtonConfigs.defaultConfigs();
    widget.configs.forEach((id, cfg) => _working[id] = cfg);
    try {
      _globalMultiplier = widget.settings.loadSizeMultiplier();
    } catch (_) {
      _globalMultiplier = 1.0;
    }
  }

  void _updateSize(String id, double value) {
    // Simpan nilai dasar (tanpa multiplier) supaya slider global dan slider
    // per-tombol tidak saling menimpa.
    setState(() {
      final current = _working[id];
      if (current == null) return;
      final ratio = current.height == 0 ? 1.0 : value / current.width;
      _working[id] = current.copyWith(width: value, height: value * ratio);
    });
  }

  void _updatePosition(String id, double xFrac, double yFrac) {
    setState(() {
      _working[id] = _working[id]!.copyWith(xFrac: xFrac, yFrac: yFrac);
    });
  }

  void _resetDefaults() {
    setState(() {
      _working = DefaultButtonConfigs.defaultConfigs();
      _globalMultiplier = 1.0;
    });
  }

  void _save() {
    // Simpan ke storage bila bisa; kalau gagal, tetap terapkan ke sesi ini.
    try {
      widget.settings.saveConfigs(_working);
      widget.settings.saveSizeMultiplier(_globalMultiplier);
    } catch (e) {
      debugPrint('Gagal menyimpan pengaturan: $e');
    }
    widget.onSave(_working);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gamepadBottom,
      appBar: AppBar(
        title: const Text('Pengaturan Tombol'),
        backgroundColor: AppColors.gradientTop,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Global size multiplier
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ukuran Semua Tombol',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Text(
                      '${(_globalMultiplier * 100).toInt()}%',
                      style: const TextStyle(
                        color: AppColors.accentLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: _globalMultiplier,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: '${(_globalMultiplier * 100).toInt()}%',
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => _globalMultiplier = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Per-button settings
          ...DefaultButtonConfigs.all.map((d) {
            final id = d['id'] as String;
            final cfg = _working[id]!;
            final label = DefaultButtonConfigs.labelFor(id);
            return _ButtonSettingItem(
              id: id,
              label: label,
              config: cfg,
              globalMultiplier: _globalMultiplier,
              onSizeChanged: (v) => _updateSize(id, v),
              onPositionChanged: (x, y) => _updatePosition(id, x, y),
            );
          }).toList(),

          const SizedBox(height: 30),

          // Reset & actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetDefaults,
                  icon: const Icon(Icons.restore, color: Colors.white70),
                  label: const Text(
                    'Reset ke Default',
                    style: TextStyle(color: Colors.white70),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Item pengaturan untuk satu tombol: slider ukuran + posisi X/Y.
class _ButtonSettingItem extends StatefulWidget {
  final String id;
  final String label;
  final ButtonConfig config;
  final double globalMultiplier;
  final void Function(double) onSizeChanged;
  final void Function(double, double) onPositionChanged;

  const _ButtonSettingItem({
    required this.id,
    required this.label,
    required this.config,
    required this.globalMultiplier,
    required this.onSizeChanged,
    required this.onPositionChanged,
  });

  @override
  State<_ButtonSettingItem> createState() => _ButtonSettingItemState();
}

class _ButtonSettingItemState extends State<_ButtonSettingItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final effWidth = widget.config.width * widget.globalMultiplier;
    final effHeight = widget.config.height * widget.globalMultiplier;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Header tap to expand
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.stickFill.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gamepad, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.accentLight,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // Ukuran slider
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      const Text('Ukuran', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      Text(
                        '${effWidth.toInt()} × ${effHeight.toInt()} px',
                        style: const TextStyle(color: AppColors.accentLight, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: effWidth.clamp(30.0, 300.0),
                    min: 30,
                    max: 300,
                    divisions: 54,
                    label: '${effWidth.toInt()} px',
                    activeColor: AppColors.accent,
                    onChanged: (v) {
                      final base = v / widget.globalMultiplier;
                      widget.onSizeChanged(base);
                    },
                  ),

                  const SizedBox(height: 18),

                  // Posisi X
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      const Text('Posisi X (%)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      Text('${(widget.config.xFrac * 100).toInt()}%',
                          style: const TextStyle(color: AppColors.accentLight, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: widget.config.xFrac * 100,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${(widget.config.xFrac * 100).toInt()}%',
                    activeColor: AppColors.accent,
                    onChanged: (v) {
                      widget.onPositionChanged(v / 100, widget.config.yFrac);
                    },
                  ),

                  const SizedBox(height: 14),

                  // Posisi Y
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      const Text('Posisi Y (%)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      Text('${(widget.config.yFrac * 100).toInt()}%',
                          style: const TextStyle(color: AppColors.accentLight, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: widget.config.yFrac * 100,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${(widget.config.yFrac * 100).toInt()}%',
                    activeColor: AppColors.accent,
                    onChanged: (v) {
                      widget.onPositionChanged(widget.config.xFrac, v / 100);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
