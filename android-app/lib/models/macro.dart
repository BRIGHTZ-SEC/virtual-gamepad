import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/protocol.dart';

/// Satu kejadian input yang tercatat saat merekam macro.
@immutable
class MacroEvent {
  /// Bit tombol/protocol yang terpengaruh.
  final int bit;

  /// True = tombol ditekan, false = tombol dilepas.
  final bool pressed;

  /// Waktu kejadian relatif terhadap mulai rekaman (milidetik).
  final int timeMs;

  const MacroEvent({
    required this.bit,
    required this.pressed,
    required this.timeMs,
  });

  Map<String, dynamic> toJson() => {
        'bit': bit,
        'pressed': pressed,
        'time': timeMs,
      };

  factory MacroEvent.fromJson(Map<String, dynamic> json) => MacroEvent(
        bit: (json['bit'] as num).toInt(),
        pressed: json['pressed'] as bool,
        timeMs: (json['time'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is MacroEvent &&
      other.bit == bit &&
      other.pressed == pressed &&
      other.timeMs == timeMs;

  @override
  int get hashCode => Object.hash(bit, pressed, timeMs);
}

/// Satu macro: daftar kejadian yang akan diputar ulang.
@immutable
class Macro {
  final String id;
  final String name;
  final List<MacroEvent> events;

  const Macro({
    required this.id,
    required this.name,
    required this.events,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory Macro.fromJson(Map<String, dynamic> json) => Macro(
        id: json['id'] as String,
        name: json['name'] as String,
        events: (json['events'] as List<dynamic>)
            .map((e) => MacroEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get durationMs {
    if (events.isEmpty) return 0;
    var max = 0;
    for (final e in events) {
      if (e.timeMs > max) max = e.timeMs;
    }
    return max;
  }
}

/// Penyimpanan dan perekaman macro.
class MacroManager {
  static const String _macrosKey = 'gamepad_macros';
  static const Duration _maxLength = Duration(seconds: 10);

  final SharedPreferences? _prefs;
  final Map<String, dynamic> _memory = <String, dynamic>{};

  MacroManager._internal(this._prefs);

  static MacroManager? _instance;

  /// Instance yang sudah punya akses SharedPreferences. Bila null, [create]
  /// akan menginisialisasinya sendiri.
  static void usePrefs(SharedPreferences? prefs) {
    _instance = MacroManager._internal(prefs);
  }

  static Future<MacroManager> create() async {
    if (_instance != null) return _instance!;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _instance = MacroManager._internal(prefs);
    } catch (_) {
      return _instance = MacroManager._internal(null);
    }
  }

  String? _getString(String key) => _prefs?.getString(key) ?? _memory[key] as String?;

  void _setString(String key, String value) {
    if (_prefs != null) {
      _prefs!.setString(key, value);
    } else {
      _memory[key] = value;
    }
  }

  List<Macro> loadMacros() {
    final raw = _getString(_macrosKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Macro.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMacros(List<Macro> macros) async {
    _setString(_macrosKey, jsonEncode(macros.map((m) => m.toJson()).toList()));
  }

  static Duration get maxLength => _maxLength;

  /// Bit tombol yang boleh direkam. Mencegah merekam tombol navigasi
  /// (guide/start) yang bisa membuat pengguna terjebak di layout.
  static const Set<int> recordableBits = {
    Protocol.bitA,
    Protocol.bitB,
    Protocol.bitX,
    Protocol.bitY,
    Protocol.bitLb,
    Protocol.bitRb,
    Protocol.bitDpadUp,
    Protocol.bitDpadDown,
    Protocol.bitDpadLeft,
    Protocol.bitDpadRight,
    Protocol.bitLsClick,
    Protocol.bitRsClick,
  };
}

