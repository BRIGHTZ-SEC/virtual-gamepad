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

/// Layout gamepad yang didukung.
enum ButtonLayout {
  classic('classic', 'Classic'),
  xbox('xbox', 'Xbox'),
  playstation('ps', 'PlayStation');

  final String key;
  final String label;

  const ButtonLayout(this.key, this.label);

  static ButtonLayout fromKey(String? key) {
    for (final l in ButtonLayout.values) {
      if (l.key == key) return l;
    }
    return ButtonLayout.xbox;
  }
}

/// Definisi default posisi/ukuran tombol untuk tiap layout.
///
/// Koordinat memakai fraksi terhadap lebar/tinggi area gamepad, sehingga
/// layout ikut menyesuaikan ukuran layar dan orientasi perangkat.
class DefaultButtonConfigs {
  // Ikon & label tombol aksi (kanan bawah) per layout.
  static const List<String> xboxFaceLabels = ['Y', 'B', 'X', 'A'];
  static const List<String> psFaceLabels = ['TRI', 'CIRC', 'SQU', 'X'];
  static const List<String> classicFaceLabels = ['Y', 'B', 'X', 'A'];

  /// Tombol kontrol umum (bisa dipakai di semua layout).
  static const Map<String, List<double>> _shared = {
    // id, xFrac, yFrac, width, height
    'settings': [0.530, 0.068, 44.0, 44.0],
    'saveLayout': [0.600, 0.068, 44.0, 44.0],
    'resetLayout': [0.670, 0.068, 44.0, 44.0],
    'addMacro': [0.740, 0.068, 44.0, 44.0],
    'disconnect': [0.460, 0.068, 44.0, 44.0],
  };

  /// Layout Classic — tombol A/B/X/Y, stick asimetris (mirip Xbox).
  static const List<List<double>> _classic = [
    ['lt', 0.078, 0.182, 112.0, 112.0],
    ['lb', 0.184, 0.339, 70.0, 70.0],
    ['dpad', 0.112, 0.620, 180.0, 180.0],
    ['menu', 0.371, 0.242, 60.0, 60.0],
    ['guide', 0.470, 0.242, 68.0, 68.0],
    ['start', 0.570, 0.242, 60.0, 60.0],
    ['l3', 0.416, 0.475, 90.0, 56.0],
    ['r3', 0.526, 0.475, 90.0, 56.0],
    ['leftStick', 0.310, 0.751, 160.0, 160.0],
    ['rightStick', 0.685, 0.751, 160.0, 160.0],
    ['rb', 0.815, 0.346, 70.0, 70.0],
    ['rt', 0.922, 0.182, 112.0, 112.0],
    ['faceButtons', 0.890, 0.620, 150.0, 150.0],
  ];

  /// Layout Xbox — D-pad kiri bawah, stick kiri atas, ABXY kanan tengah.
  ///
  /// Catatan: pada controller Xbox, L3/R3 adalah tombol tekan pada stick
  /// itu sendiri, jadi tidak lagi digambar sebagai tombol terpisah di sini.
  static const List<List<double>> _xbox = [
    ['lt', 0.105, 0.175, 116.0, 116.0],
    ['lb', 0.215, 0.250, 68.0, 68.0],
    ['leftStick', 0.160, 0.310, 168.0, 168.0],
    ['dpad', 0.135, 0.720, 190.0, 190.0],
    ['menu', 0.410, 0.365, 54.0, 54.0],
    ['guide', 0.500, 0.365, 62.0, 62.0],
    ['start', 0.590, 0.365, 54.0, 54.0],
    ['rb', 0.785, 0.250, 68.0, 68.0],
    ['rt', 0.895, 0.175, 116.0, 116.0],
    ['faceButtons', 0.855, 0.420, 168.0, 168.0],
    ['rightStick', 0.845, 0.770, 168.0, 168.0],
  ];

  /// Layout PlayStation — D-pad kiri atas, face buttons kanan atas,
  /// kedua analog stick simetris di sisi bawah.
  ///
  /// Sama seperti Xbox, L3/R3 adalah tekan stick sehingga tidak digambar
  /// sebagai tombol terpisah.
  static const List<List<double>> _ps = [
    ['lt', 0.100, 0.180, 110.0, 110.0],
    ['lb', 0.235, 0.245, 62.0, 62.0],
    ['dpad', 0.120, 0.330, 168.0, 168.0],
    ['leftStick', 0.310, 0.770, 168.0, 168.0],
    ['rightStick', 0.690, 0.770, 168.0, 168.0],
    ['menu', 0.405, 0.330, 52.0, 52.0],
    ['guide', 0.500, 0.330, 60.0, 60.0],
    ['start', 0.595, 0.330, 52.0, 52.0],
    ['rb', 0.765, 0.245, 62.0, 62.0],
    ['rt', 0.900, 0.180, 110.0, 110.0],
    ['faceButtons', 0.885, 0.320, 168.0, 168.0],
  ];

  static List<List<double>> _rowsFor(ButtonLayout layout) {
    switch (layout) {
      case ButtonLayout.classic:
        return _classic;
      case ButtonLayout.xbox:
        return _xbox;
      case ButtonLayout.playstation:
        return _ps;
    }
    // Cadangan bila enum bertambah di masa depan.
    return _xbox;
  }

  /// Config default untuk sebuah layout, sudah termasuk tombol kontrol umum.
  static Map<String, ButtonConfig> defaultConfigs(ButtonLayout layout) {
    final Map<String, ButtonConfig> configs = {};
    for (final r in _rowsFor(layout)) {
      configs[r[0] as String] = ButtonConfig(
        id: r[0] as String,
        xFrac: (r[1] as num).toDouble(),
        yFrac: (r[2] as num).toDouble(),
        width: (r[3] as num).toDouble(),
        height: (r[4] as num).toDouble(),
      );
    }
    for (final e in _shared.entries) {
      final r = e.value;
      configs[e.key] = ButtonConfig(
        id: e.key,
        xFrac: r[0],
        yFrac: r[1],
        width: r[2],
        height: r[3],
      );
    }
    return configs;
  }

  /// Label tombol aksi sesuai layout.
  static List<String> faceLabels(ButtonLayout layout) {
    switch (layout) {
      case ButtonLayout.classic:
        return classicFaceLabels;
      case ButtonLayout.xbox:
        return xboxFaceLabels;
      case ButtonLayout.playstation:
        return psFaceLabels;
    }
    return xboxFaceLabels;
  }

  static String labelFor(String id) {
    switch (id) {
      case 'lt':
        return 'LT / L2';
      case 'lb':
        return 'LB / L1';
      case 'dpad':
        return 'D-pad';
      case 'disconnect':
        return 'Disconnect';
      case 'settings':
        return 'Pengaturan (Gear)';
      case 'saveLayout':
        return 'Simpan Layout';
      case 'resetLayout':
        return 'Reset Layout';
      case 'addMacro':
        return 'Tambah Macro';
      case 'menu':
        return 'Menu / Share';
      case 'guide':
        return 'Guide';
      case 'start':
        return 'Start / Options';
      case 'l3':
        return 'L3 (Left Stick Click)';
      case 'r3':
        return 'R3 (Right Stick Click)';
      case 'leftStick':
        return 'Joystick Kiri';
      case 'rightStick':
        return 'Joystick Kanan';
      case 'rb':
        return 'RB / R1';
      case 'rt':
        return 'RT / R2';
      case 'faceButtons':
        return 'Tombol Aksi';
      default:
        return id;
    }
  }
}

/// Manajemen penyimpanan pengaturan tombol lewat SharedPreferences.
///
/// Kalau SharedPreferences tidak tersedia (mis. plugin belum terdaftar atau
/// gagal diinisialisasi), objek ini otomatis jatuh ke penyimpanan in-memory
/// supaya fitur pengaturan tetap bisa dipakai albeit tidak persisten.
class GamepadSettings {
  static const String _legacyPrefsKey = 'gamepad_button_configs';
  static const String _legacyMultiplierKey = 'gamepad_size_multiplier';
  static const String _layoutKey = 'gamepad_selected_layout';

  final SharedPreferences? _prefs;
  final Map<String, dynamic> _memory = <String, dynamic>{};

  GamepadSettings._internal(this._prefs);

  /// Instance yang langsung tersedia tanpa menunggu plugin, memakai
  /// penyimpanan in-memory. Dipakai supaya UI tidak pernah terblokir.
  static GamepadSettings fallback() => GamepadSettings._internal(null);

  /// Selalu mengembalikan instance yang valid; tidak pernah melempar error.
  static Future<GamepadSettings> create() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return GamepadSettings._internal(prefs);
    } catch (e) {
      // Fallback ke penyimpanan in-memory.
      return GamepadSettings._internal(null);
    }
  }

  String _keyFor(ButtonLayout layout) => 'gamepad_button_configs_${layout.key}';

  String? _getString(String key) => _prefs?.getString(key) ?? _memory[key] as String?;

  double? _getDouble(String key) => _prefs?.getDouble(key) ?? _memory[key] as double?;

  void _setString(String key, String value) {
    if (_prefs != null) {
      _prefs!.setString(key, value);
    } else {
      _memory[key] = value;
    }
  }

  void _setDouble(String key, double value) {
    if (_prefs != null) {
      _prefs!.setDouble(key, value);
    } else {
      _memory[key] = value;
    }
  }

  /// True bila pengaturan tersimpan permanen (bukan fallback in-memory).
  bool get isPersistent => _prefs != null;

  /// Akses mentah SharedPreferences, dipakai MacroManager agar memakai
  /// koneksi storage yang sama. Null saat memakai fallback in-memory.
  SharedPreferences? get prefs => _prefs;

  /// Layout yang terakhir dipilih pengguna.
  ButtonLayout loadLayout() => ButtonLayout.fromKey(_getString(_layoutKey));

  void saveLayout(ButtonLayout layout) => _setString(_layoutKey, layout.key);

  /// Load config untuk sebuah layout, fallback ke default bila belum pernah
  /// disimpan atau datanya rusak.
  Map<String, ButtonConfig> loadConfigs(ButtonLayout layout) {
    var jsonStr = _getString(_keyFor(layout));

    // Migrasi: layout Classic pernah disimpan tanpa suffix layout.
    if (jsonStr == null && layout == ButtonLayout.classic) {
      jsonStr = _getString(_legacyPrefsKey);
    }

    final defaults = DefaultButtonConfigs.defaultConfigs(layout);
    if (jsonStr == null) return defaults;

    try {
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      final Map<String, ButtonConfig> configs = {};
      for (final item in list) {
        final cfg = ButtonConfig.fromJson(item as Map<String, dynamic>);
        configs[cfg.id] = cfg;
      }
      // Pastikan semua default ada (jika ada tombol baru di update versi depan)
      for (final entry in defaults.entries) {
        configs.putIfAbsent(entry.key, () => entry.value);
      }
      return configs;
    } catch (_) {
      return defaults;
    }
  }

  /// Simpan config untuk sebuah layout.
  void saveConfigs(ButtonLayout layout, Map<String, ButtonConfig> configs) {
    final list = configs.values.map((c) => c.toJson()).toList();
    _setString(_keyFor(layout), jsonEncode(list));
    // Simpan juga ke key lama supaya tetap kompatibel bila user-nya Classic.
    if (layout == ButtonLayout.classic) {
      _setString(_legacyPrefsKey, jsonEncode(list));
      _setDouble(_legacyMultiplierKey, 1.0);
    }
  }

  /// Load size multiplier (1.0 = default).
  double loadSizeMultiplier() => _getDouble(_legacyMultiplierKey) ?? 1.0;

  /// Simpan size multiplier.
  void saveSizeMultiplier(double value) => _setDouble(_legacyMultiplierKey, value);
}