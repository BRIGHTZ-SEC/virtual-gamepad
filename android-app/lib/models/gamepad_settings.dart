import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Konfigurasi satu tombol: posisi (fraksi layar 0-1) dan ukuran (pixel).
class ButtonConfig {
  final String id;
  double xFrac; // fraksi lebar layar (0.0 - 1.0)
  double yFrac; // fraksi tinggi layar (0.0 - 1.0)
  double width; // lebar dalam pixel (referensi layar penuh)
  double height; // tinggi dalam pixel (referensi layar penuh)

  ButtonConfig({
    required this.id,
    required this.xFrac,
    required this.yFrac,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'xFrac': xFrac,
        'yFrac': yFrac,
        'width': width,
        'height': height,
      };

  factory ButtonConfig.fromJson(Map<String, dynamic> json) => ButtonConfig(
        id: json['id'] as String,
        xFrac: (json['xFrac'] as num).toDouble(),
        yFrac: (json['yFrac'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  ButtonConfig copyWith({
    double? xFrac,
    double? yFrac,
    double? width,
    double? height,
  }) {
    return ButtonConfig(
      id: id,
      xFrac: xFrac ?? this.xFrac,
      yFrac: yFrac ?? this.yFrac,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Default konfigurasi tombol yang cocok dengan layout asli gamepad screen.
class DefaultButtonConfigs {
  static const List<Map<String, dynamic>> all = [
    {'id': 'lt', 'xFrac': 0.078, 'yFrac': 0.182, 'width': 112.0, 'height': 112.0},
    {'id': 'lb', 'xFrac': 0.184, 'yFrac': 0.339, 'width': 70.0, 'height': 70.0},
    {'id': 'dpad', 'xFrac': 0.112, 'yFrac': 0.620, 'width': 180.0, 'height': 180.0},
    {'id': 'settings', 'xFrac': 0.530, 'yFrac': 0.068, 'width': 44.0, 'height': 44.0},
    {'id': 'disconnect', 'xFrac': 0.470, 'yFrac': 0.068, 'width': 50.0, 'height': 50.0},
    {'id': 'menu', 'xFrac': 0.371, 'yFrac': 0.242, 'width': 60.0, 'height': 60.0},
    {'id': 'guide', 'xFrac': 0.470, 'yFrac': 0.242, 'width': 68.0, 'height': 68.0},
    {'id': 'start', 'xFrac': 0.570, 'yFrac': 0.242, 'width': 60.0, 'height': 60.0},
    {'id': 'l3', 'xFrac': 0.416, 'yFrac': 0.475, 'width': 90.0, 'height': 56.0},
    {'id': 'r3', 'xFrac': 0.526, 'yFrac': 0.475, 'width': 90.0, 'height': 56.0},
    {'id': 'leftStick', 'xFrac': 0.310, 'yFrac': 0.751, 'width': 160.0, 'height': 160.0},
    {'id': 'rightStick', 'xFrac': 0.685, 'yFrac': 0.751, 'width': 160.0, 'height': 160.0},
    {'id': 'rb', 'xFrac': 0.815, 'yFrac': 0.346, 'width': 70.0, 'height': 70.0},
    {'id': 'rt', 'xFrac': 0.922, 'yFrac': 0.182, 'width': 112.0, 'height': 112.0},
    {'id': 'faceButtons', 'xFrac': 0.890, 'yFrac': 0.620, 'width': 150.0, 'height': 150.0},
  ];

  static String labelFor(String id) {
    switch (id) {
      case 'lt': return 'LT (Left Trigger)';
      case 'lb': return 'LB (Left Bumper)';
      case 'dpad': return 'D-pad';
      case 'disconnect': return 'Disconnect';
      case 'settings': return 'Pengaturan (Gear)';
      case 'menu': return 'Menu / Back';
      case 'guide': return 'Guide / Xbox';
      case 'start': return 'Start';
      case 'l3': return 'L3 (Left Stick Click)';
      case 'r3': return 'R3 (Right Stick Click)';
      case 'leftStick': return 'Joystick Kiri';
      case 'rightStick': return 'Joystick Kanan';
      case 'rb': return 'RB (Right Bumper)';
      case 'rt': return 'RT (Right Trigger)';
      case 'faceButtons': return 'Tombol A / B / X / Y';
      default: return id;
    }
  }

  /// Config default tanpa menyentuh SharedPreferences. Dipakai sebagai
  /// fallback supaya UI tetap menampilkan tombol walau prefs gagal dimuat.
  static Map<String, ButtonConfig> defaultConfigs() {
    final Map<String, ButtonConfig> configs = {};
    for (final d in all) {
      configs[d['id'] as String] = ButtonConfig(
        id: d['id'] as String,
        xFrac: (d['xFrac'] as num).toDouble(),
        yFrac: (d['yFrac'] as num).toDouble(),
        width: (d['width'] as num).toDouble(),
        height: (d['height'] as num).toDouble(),
      );
    }
    return configs;
  }
}

/// Manajemen penyimpanan pengaturan tombol lewat SharedPreferences.
class GamepadSettings {
  static const String _prefsKey = 'gamepad_button_configs';
  static const String _sizeMultiplierKey = 'gamepad_size_multiplier';

  final SharedPreferences _prefs;

  GamepadSettings._internal(this._prefs);

  static Future<GamepadSettings> create() async {
    final prefs = await SharedPreferences.getInstance();
    return GamepadSettings._internal(prefs);
  }

  /// Load semua config dari prefs, kalau belum ada pakai default.
  Map<String, ButtonConfig> loadConfigs() {
    final jsonStr = _prefs.getString(_prefsKey);
    if (jsonStr == null) {
      return _buildFromDefaults();
    }

    try {
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      final Map<String, ButtonConfig> configs = {};
      for (final item in list) {
        final cfg = ButtonConfig.fromJson(item as Map<String, dynamic>);
        configs[cfg.id] = cfg;
      }
      // Pastikan semua default ada (jika ada tombol baru di update versi depan)
      final defaults = _buildFromDefaults();
      for (final entry in defaults.entries) {
        if (!configs.containsKey(entry.key)) {
          configs[entry.key] = entry.value;
        }
      }
      return configs;
    } catch (_) {
      return _buildFromDefaults();
    }
  }

  /// Simpan semua config ke prefs.
  void saveConfigs(Map<String, ButtonConfig> configs) {
    final list = configs.values.map((c) => c.toJson()).toList();
    _prefs.setString(_prefsKey, jsonEncode(list));
  }

  /// Load size multiplier (1.0 = default).
  double loadSizeMultiplier() {
    return _prefs.getDouble(_sizeMultiplierKey) ?? 1.0;
  }

  /// Simpan size multiplier.
  void saveSizeMultiplier(double value) {
    _prefs.setDouble(_sizeMultiplierKey, value);
  }

  /// Config default tanpa menyentuh SharedPreferences. Dipakai sebagai
  /// fallback supaya UI tetap menampilkan tombol walau prefs gagal dimuat.
  static Map<String, ButtonConfig> defaultConfigs() => DefaultButtonConfigs.defaultConfigs();

  Map<String, ButtonConfig> _buildFromDefaults() => DefaultButtonConfigs.defaultConfigs();

  /// Reset semua config ke default.
  Map<String, ButtonConfig> resetToDefaults() {
    return _buildFromDefaults();
  }
}
