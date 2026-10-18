import 'dart:async'; // Added to handle stream subscriptions
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gamepad_settings.dart';
import '../models/gamepad_state.dart';
import '../models/macro.dart';
import '../network/gamepad_socket.dart';
import '../network/protocol.dart';
import '../theme.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/gamepad_button_widget.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/trigger_widget.dart';

class GamepadScreen extends StatefulWidget {
  final GamepadSocket socket;

  /// Instance penyimpanan yang sudah dibuat oleh ConnectScreen. Kalau null,
  /// layar akan membuat sendiri lewat fallback in-memory.
  final GamepadSettings? settings;

  /// Layout yang dipilih pengguna di layar pemilihan layout. Null berarti
  /// pakai layout yang tersimpan terakhir.
  final ButtonLayout? layout;

  const GamepadScreen({
    super.key,
    required this.socket,
    this.settings,
    this.layout,
  });

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  late final GamepadState _state;
  StreamSubscription? _connectionSubscription; // Handles the socket listener state

  // Layout aktif. Di-resolve di initState dari argumen, lalu dari storage.
  late ButtonLayout _layout;

  // Selalu non-null: mulai dari instance in-memory supaya ikon pengaturan
  // selalu bisa dibuka, walau SharedPreferences gagal dimuat belakangan.
  GamepadSettings _settings = GamepadSettings.fallback();
  // Mulai dari default sinkron supaya tombol langsung tampil walau
  // SharedPreferences belum selesai dimuat atau gagal dimuat.
  Map<String, ButtonConfig> _configs =
      DefaultButtonConfigs.defaultConfigs(ButtonLayout.xbox);
  bool _editMode = false;

  // State gesture untuk mode edit: ukuran awal saat pinch dimulai.
  final Map<String, (double, double)> _gestureStartSizes = {};

  // ---------------- Macro ----------------
  // Tidak ada tombol macro secara default; muncul setelah user membuatnya
  // lewat ikon "Tambah Macro" di mode edit.
  final Map<String, ButtonConfig> _macroConfigs = {};
  MacroManager? _macros;
  List<Macro> _macroList = [];

  bool _recording = false;
  final List<MacroEvent> _recorded = [];
  Stopwatch? _recordClock;

  final List<Timer> _playbackTimers = [];
  bool _playingBack = false;

  /// Bit yang sedang ditahan saat playback, agar bisa dilepas dengan aman
  /// ketika playback dihentikan di tengah jalan.
  final Set<int> _playbackHeld = {};

  /// Rasio ukuran tombol saat ini dibanding ukuran default-nya (1.0 = default).
  /// Dipakai agar isi tombol (bukan cuma kotak luarnya) ikut membesar/perkecil
  /// ketika pengguna melakukan pinch di mode edit.
  double _scaleOf(String id) {
    final cfg = _configs[id];
    if (cfg == null) return 1.0;
    final def = DefaultButtonConfigs.defaultConfigs(_layout)[id];
    if (def == null || def.width <= 0) return 1.0;
    return cfg.width / def.width;
  }

  /// Ukuran inner widget untuk tombol [id], mengikuti skala config.
  double _innerSize(String id, double base) => base * _scaleOf(id);

  // Track D-pad states to only vibrate when a direction is freshly clicked down
  bool _upPressed = false;
  bool _downPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;

  // Track Trigger steps locally so they click at distinct thresholds (e.g., 10%, 50%, 90%)
  int _leftTriggerStep = 0;
  int _rightTriggerStep = 0;

  // Track Joystick center deadzones locally to tick right when exiting the middle
  bool _leftStickActive = false;
  bool _rightStickActive = false;

  @override
  void initState() {
    super.initState();
    _state = GamepadState(widget.socket);
    _state.start();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Resolve layout: pakai argumen, kalau tidak ambil dari storage.
    _layout = widget.layout ??
        widget.settings?.loadLayout() ??
        ButtonLayout.xbox;

    // Pakai instance settings dari ConnectScreen bila tersedia, supaya
    // perubahan layout langsung konsisten tanpa membaca storage dua kali.
    if (widget.settings != null) {
      _settings = widget.settings!;
    }

    // Muat config tombol untuk layout aktif.
    _configs = DefaultButtonConfigs.defaultConfigs(_layout);
    if (widget.settings != null) {
      _configs = _settings.loadConfigs(_layout);
    } else {
      _loadSettings();
    }

    // Listen for disconnections automatically from the socket network manager
    _connectionSubscription = widget.socket.connectionStream.listen((isConnected) {
      if (!isConnected) {
        _handleConnectionLoss();
      }
    });

    // Muat macro yang tersimpan (tidak ada tombol macro secara default).
    _loadMacros();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await GamepadSettings.create();
      if (!mounted) return;
      final loaded = settings.loadConfigs(_layout);
      setState(() {
        _settings = settings;
        _configs = loaded;
      });
    } catch (e, st) {
      // Tetap pakai fallback in-memory; hanya catat errornya.
      debugPrint('Gagal memuat pengaturan tombol: $e\n$st');
    }
  }

  /// Toggle mode edit: saat aktif, tiap tombol bisa digeser (drag) dan
  /// diperbesar/diperkecil (pinch 2 jari) langsung di layar gamepad.
  void _toggleEditMode() {
    HapticFeedback.mediumImpact();
    setState(() => _editMode = !_editMode);
    if (!_editMode) {
      // Keluar dari edit mode = simpan hasil editan.
      _saveLayout();
    } else {
      _banner(
        'Mode Edit: geser tombol untuk pindah, cubit 2 jari untuk ubah ukuran.',
        AppColors.accentLight,
      );
    }
  }

  /// Simpan layout saat ini ke penyimpanan.
  void _saveLayout() {
    try {
      _settings.saveConfigs(_layout, _configs);
      _settings.saveSizeMultiplier(1.0);
    } catch (e) {
      debugPrint('Gagal menyimpan layout: $e');
    }
    _banner('Layout tersimpan.', AppColors.buttonA);
  }

  /// Reset semua tombol ke posisi & ukuran default.
  void _resetLayout() {
    HapticFeedback.heavyImpact();
    _stopPlayback();
    if (_recording) {
      _recording = false;
      _recorded.clear();
    }
    setState(() {
      _configs = DefaultButtonConfigs.defaultConfigs(_layout);
      // Tombol macro ikut dikembalikan ke posisi default.
      _macroConfigs.remove('macro0');
    });
    _saveLayout();
  }

  void _banner(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color.withOpacity(0.9),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  // ------------------------- Macro -------------------------

  /// Muat daftar macro yang tersimpan.
  Future<void> _loadMacros() async {
    try {
      MacroManager.usePrefs(_settings.prefs);
      final mgr = await MacroManager.create();
      if (!mounted) return;
      setState(() {
        _macros = mgr;
        _macroList = mgr.loadMacros();
      });
    } catch (e) {
      debugPrint('Gagal memuat macro: $e');
    }
  }

  /// Tambah satu tombol macro baru di area tengah bawah layar.
  void _addMacro() {
    if (_macroConfigs.isNotEmpty) {
      _banner('Tombol macro sudah ada. Reset dulu sebelum menambah.',
          Colors.orange);
      return;
    }

    // Placeholder 'macro0' dibuat dulu supaya user bisa menaruhnya di posisi
    // yang diinginkan lewat mode edit. Nama asli diminta setelah rekaman.
    setState(() {
      _macroConfigs['macro0'] = ButtonConfig(
        id: 'macro0',
        xFrac: 0.470,
        yFrac: 0.470,
        width: 104,
        height: 46,
      );
    });
    _banner('Tombol macro ditambahkan. Geser posisinya, lalu tekan untuk merekam.',
        AppColors.buttonA);
  }

  /// Dialog sederhana untuk memberi nama macro.
  Future<String?> _showMacroNameDialog() async {
    final controller = TextEditingController(text: 'Macro 1');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.gamepadTop,
        title: const Text('Nama Macro', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Contoh: Kombo Burst',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: AppColors.accentLight)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// Mulai rekaman. Semua tombol yang bisa direkam akan mencatat kejadiannya.
  void _startRecording() {
    if (_recording) return;
    setState(() {
      _recording = true;
      _recorded.clear();
    });
    _recordClock = Stopwatch()..start();
    _banner('Merekam... tekan tombol yang ingin dimasukkan.', AppColors.buttonB);
  }

  /// Hentikan rekaman dan simpan sebagai macro baru.
  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordClock?.stop();

    final events = List<MacroEvent>.from(_recorded);
    setState(() => _recording = false);

    if (events.isEmpty) {
      _recorded.clear();
      _banner('Rekaman kosong, tidak disimpan.', Colors.orange);
      return;
    }

    final name = await _showMacroNameDialog();
    if (name == null || !mounted) {
      _recorded.clear();
      return;
    }

    final mgr = _macros;
    if (mgr == null) {
      _banner('Macro belum siap, coba lagi.', Colors.orange);
      return;
    }

    final id = 'macro${DateTime.now().millisecondsSinceEpoch}';
    final macro = Macro(id: id, name: name, events: events);

    // Ganti id tombol yang di layar agar tidak bentrok dengan macro lama.
    final newConfigs = <String, ButtonConfig>{
      for (final e in _macroConfigs.entries)
        if (e.key != 'macro0') e.key: e.value,
    };
    newConfigs[id] = ButtonConfig(
      id: id,
      xFrac: _macroConfigs['macro0']?.xFrac ?? 0.5,
      yFrac: _macroConfigs['macro0']?.yFrac ?? 0.47,
      width: _macroConfigs['macro0']?.width ?? 104,
      height: _macroConfigs['macro0']?.height ?? 46,
    );

    final updated = [..._macroList, macro];
    await mgr.saveMacros(updated);
    if (!mounted) return;
    setState(() {
      _macroList = updated;
      _macroConfigs = newConfigs;
      _recorded.clear();
    });
    _banner('Macro "$name" tersimpan (${events.length} kejadian).', AppColors.buttonA);
  }

  /// Putar ulang sebuah macro dengan menjaga urutan waktu kejadian.
  void _playMacro(Macro macro) {
    if (_playingBack || macro.events.isEmpty) return;
    _stopPlayback();

    setState(() => _playingBack = true);
    HapticFeedback.mediumImpact();

    for (final event in macro.events) {
      final delay = Duration(milliseconds: event.timeMs);
      // Setiap kejadian memakai timer sendiri; satu variabel timer tunggal
      // akan saling menimpa dan hanya kejadian terakhir yang berjalan.
      _playbackTimers.add(
        Timer(delay, () {
          if (!mounted) return;
          if (event.pressed) {
            _playbackHeld.add(event.bit);
          } else {
            _playbackHeld.remove(event.bit);
          }
          _state.setButton(event.bit, event.pressed);
        }),
      );
    }

    // Pastikan semua tombol yang masih tertahan dilepas setelah selesai.
    _playbackTimers.add(
      Timer(
        Duration(milliseconds: macro.durationMs + 120),
        () => _stopPlayback(),
      ),
    );
  }

  /// Hentikan playback dan lepaskan semua tombol yang masih tertahan,
  /// supaya tidak ada tombol yang "nyangkut" tertekan.
  void _stopPlayback() {
    for (final t in _playbackTimers) {
      t.cancel();
    }
    _playbackTimers.clear();
    if (_playbackHeld.isNotEmpty) {
      for (final bit in _playbackHeld) {
        _state.setButton(bit, false);
      }
      _playbackHeld.clear();
    }
    if (_playingBack && mounted) {
      setState(() => _playingBack = false);
    } else {
      _playingBack = false;
    }
  }

  @override
  void dispose() {
    _stopPlayback();
    _recordClock?.stop();
    _connectionSubscription?.cancel(); // Cancel network listeners to prevent memory leaks
    _state.stop();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// Automatically safely updates UI state and resets navigation back to the connection layout
  void _handleConnectionLoss() {
    if (!mounted) return;

    // Fire an aggressive vibration alert so the user notices the drop immediately
    HapticFeedback.heavyImpact();

    // Notify the user via a quick temporary banner notification overlay
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connection lost! Returning to menu...'),
        duration: Duration(seconds: 2),
      ),
    );

    // Clears any active popups or dialogs and steps cleanly back to the absolute base view
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _disconnect() {
    HapticFeedback.lightImpact();
    widget.socket.disconnect();
    // No explicit call to pop() is needed here anymore! 
    // widget.socket.disconnect() will push a value to 'connectionStream', 
    // triggering _handleConnectionLoss() naturally.
  }

  /// Handles standard button haptics cleanly — fires only on down-press
  void _handleButtonPress(int buttonBit, bool isPressed) {
    if (isPressed) {
      HapticFeedback.lightImpact();
    }
    // Rekam kejadian ini bila sedang merekam macro dan tombolnya masuk daftar.
    if (_recording && MacroManager.recordableBits.contains(buttonBit)) {
      final elapsed = _recordClock?.elapsedMilliseconds ?? 0;
      _recorded.add(MacroEvent(
        bit: buttonBit,
        pressed: isPressed,
        timeMs: elapsed,
      ));
      // Batasi durasi rekaman supaya tidak berjalan tanpa henti.
      if (elapsed >= MacroManager.maxLength.inMilliseconds) {
        _stopRecording();
      }
    }
    _state.setButton(buttonBit, isPressed);
  }

  /// Handles analog triggers: vibrates dynamically at progressive pull thresholds
  void _handleTriggerHaptic(double value, bool isLeft) {
    // Determine a step integer from 0 to 3 based on pressure deepness
    int currentStep = 0;
    if (value > 0.9) {
      currentStep = 3;
    } else if (value > 0.5) {
      currentStep = 2;
    } else if (value > 0.1) {
      currentStep = 1;
    }

    final oldStep = isLeft ? _leftTriggerStep : _rightTriggerStep;
    if (currentStep != oldStep) {
      // Tick on both pulling further down and popping all the way back out
      if (currentStep > oldStep || currentStep == 0) {
        HapticFeedback.lightImpact();
      }
      if (isLeft) {
        _leftTriggerStep = currentStep;
      } else {
        _rightTriggerStep = currentStep;
      }
    }
  }

  /// Handles joystick deadzones: vibrates exactly when the stick breaks out of center rest
  void _handleJoystickHaptic(double x, double y, bool isLeft) {
    // Check vector distance from center point (0,0)
    final bool isMoving = (x * x + y * y) > 0.04; // ~20% tilt radius threshold
    final oldActive = isLeft ? _leftStickActive : _rightStickActive;

    if (isMoving && !oldActive) {
      HapticFeedback.lightImpact(); // Click when passing out of deadzone range
    }

    if (isLeft) {
      _leftStickActive = isMoving;
    } else {
      _rightStickActive = isMoving;
    }
  }

  /// Membangun daftar widget untuk setiap tombol macro yang sudah dibuat user.
  ///
  /// Macro tidak punya entry di [_configs] (yang hanya berisi tombol gamepad),
  /// jadi posisinya diambil dari [_macroConfigs] dan ikut bisa digeser serta
  /// diperbesar saat mode edit aktif.
  List<Widget> _buildMacroButtons(BoxConstraints c) {
    final widgets = <Widget>[];

    for (final entry in _macroConfigs.entries) {
      final id = entry.key;
      final cfg = entry.value;

      Macro? found;
      for (final m in _macroList) {
        if (m.id == id) {
          found = m;
          break;
        }
      }
      final Macro? macro = found;

      final isPlaceholder = macro == null;
      final label = isPlaceholder ? 'MACRO' : macro!.name;

      final w = cfg.width;
      final h = cfg.height;
      final left = c.maxWidth * cfg.xFrac - w / 2;
      final top = c.maxHeight * cfg.yFrac - h / 2;

      Widget button = GamepadButtonWidget(
        label: label,
        size: h,
        fontSize: 13,
        color: _recording ? AppColors.buttonB : AppColors.iconBg,
        onChanged: (pressed) {
          if (!pressed) return;
          if (_recording) {
            // Ketuk lagi untuk berhenti dan menyimpan rekaman.
            _stopRecording();
          } else if (macro == null) {
            _startRecording();
          } else {
            _playMacro(macro);
          }
        },
      );

      if (_editMode) {
        final startW = _gestureStartSizes[id]?.$1 ?? w;
        final startH = _gestureStartSizes[id]?.$2 ?? h;

        button = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) {
            final cur = _macroConfigs[id];
            if (cur == null) return;
            _gestureStartSizes[id] = (cur.width, cur.height);
            HapticFeedback.selectionClick();
          },
          onScaleUpdate: (d) {
            final cur = _macroConfigs[id];
            if (cur == null) return;
            setState(() {
              if (d.pointerCount >= 2) {
                final nw = (startW * d.scale).clamp(60.0, 300.0);
                final nh = (startH * d.scale).clamp(36.0, 200.0);
                _macroConfigs[id] = cur.copyWith(width: nw, height: nh);
              } else {
                _macroConfigs[id] = cur.copyWith(
                  xFrac: (cur.xFrac + d.focalPointDelta.dx / c.maxWidth)
                      .clamp(0.0, 1.0),
                  yFrac: (cur.yFrac + d.focalPointDelta.dy / c.maxHeight)
                      .clamp(0.0, 1.0),
                );
              }
            });
          },
          onScaleEnd: (_) => _gestureStartSizes.remove(id),
          child: button,
        );
      }

      widgets.add(
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: Center(child: button),
        ),
      );
    }

    return widgets;
  }

  /// Membangun widget tombol pada posisi dari config.
  ///
  /// Saat [_editMode] aktif, tombol bisa digeser satu jari dan diubah
  /// ukurannya dengan cubitan dua jari. Editan hanya berlaku di config
  /// in-memory dan disimpan ke [_saveLayout] saat mode edit dimatikan.
  Widget _atc(BoxConstraints c, String id, Widget child, {double? wOverride, double? hOverride}) {
    final cfg = _configs[id] ?? DefaultButtonConfigs.defaultConfigs(_layout)[id];
    if (cfg == null) {
      debugPrint('Unknown button id: $id');
      return const SizedBox.shrink();
    }

    final w = (wOverride ?? cfg.width);
    final h = (hOverride ?? cfg.height);

    if (!_editMode) {
      return Positioned(
        left: c.maxWidth * cfg.xFrac - w / 2,
        top: c.maxHeight * cfg.yFrac - h / 2,
        width: w,
        height: h,
        child: Center(child: child),
      );
    }

    // --- Mode edit: drag untuk pindah, pinch untuk ubah ukuran. ---
    // Semua state gesture disimpan di field agar tidak hilang saat rebuild
    // dan tidak saling menimpa antara drag dan pinch.
    final startW = _gestureStartSizes[id]?.$1 ?? w;
    final startH = _gestureStartSizes[id]?.$2 ?? h;

    Widget interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        final cur = _configs[id] ?? cfg;
        _gestureStartSizes[id] = (cur.width, cur.height);
        HapticFeedback.selectionClick();
      },
      onScaleUpdate: (d) {
        final cur = _configs[id] ?? cfg;
        setState(() {
          if (d.pointerCount >= 2) {
            // Dua jari: ubah ukuran, posisi tidak berubah.
            final nw = (startW * d.scale).clamp(36.0, 360.0);
            final nh = (startH * d.scale).clamp(36.0, 360.0);
            _configs[id] = cur.copyWith(width: nw, height: nh);
          } else {
            // Satu jari: geser posisi mengikuti delta focal point (piksel
            // logikal global), lalu dinormalisasi ke fraksi 0..1.
            final dx = d.focalPointDelta.dx / c.maxWidth;
            final dy = d.focalPointDelta.dy / c.maxHeight;
            _configs[id] = cur.copyWith(
              xFrac: (cur.xFrac + dx).clamp(0.0, 1.0),
              yFrac: (cur.yFrac + dy).clamp(0.0, 1.0),
            );
          }
        });
      },
      onScaleEnd: (_) {
        _gestureStartSizes.remove(id);
      },
      child: Center(child: child),
    );

    return Positioned(
      left: c.maxWidth * cfg.xFrac - w / 2,
      top: c.maxHeight * cfg.yFrac - h / 2,
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: interactive),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${w.toInt()}×${h.toInt()}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gamepadBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.4,
            colors: [AppColors.gamepadTop, AppColors.gamepadBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final c = constraints;
              return Stack(
                children: [
                  // LT - Left Trigger
                  _atc(c, 'lt',
                      TriggerWidget(
                        label: _layout == ButtonLayout.playstation ? 'L2' : 'LT',
                        size: _innerSize('lt', 112), 
                        onChanged: (v) {
                          _handleTriggerHaptic(v, true);
                          _state.setLeftTrigger(v);
                        },
                      )),

                  // LB - Left Bumper
                  _atc(c, 'lb',
                      GamepadButtonWidget(
                        label: _layout == ButtonLayout.playstation ? 'L1' : 'LB',
                        size: _innerSize('lb', 70),
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitLb, p),
                      )),

                  // D-pad - Lower Left
                  _atc(c, 'dpad',
                      DpadWidget(
                        size: _innerSize('dpad', 150),
                        onChanged: ({required up, required down, required left, required right}) {
                          if ((up && !_upPressed) || 
                              (down && !_downPressed) || 
                              (left && !_leftPressed) || 
                              (right && !_rightPressed)) {
                            HapticFeedback.lightImpact(); 
                          }
                          _upPressed = up;
                          _downPressed = down;
                          _leftPressed = left;
                          _rightPressed = right;

                          _state.setDpad(up: up, down: down, left: left, right: right);
                        },
                      )),

                  // Disconnect - Top Center
                  _atc(c, 'disconnect',
                      GestureDetector(
                        onTap: _disconnect,
                        child: Container(
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.stickFill, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 22),
                        ),
                      )),

                  // Settings / Gear - toggles edit mode
                  _atc(c, 'settings',
                      GestureDetector(
                        onTap: _toggleEditMode,
                        child: Container(
                          width: _innerSize('settings', 44),
                          height: _innerSize('settings', 44),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _editMode ? AppColors.accent : AppColors.stickFill,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _editMode ? Icons.check : Icons.settings,
                            color: _editMode ? Colors.black : Colors.white,
                            size: 22,
                          ),
                        ),
                      )),

                  // Save button - only while editing
                  if (_editMode)
                    _atc(c, 'saveLayout',
                        GestureDetector(
                          onTap: () {
                            setState(() => _editMode = false);
                            _saveLayout();
                          },
                          child: Container(
                            width: _innerSize('saveLayout', 44),
                            height: _innerSize('saveLayout', 44),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.buttonA,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.save,
                                color: Colors.black, size: 22),
                          ),
                        )),

                  // Reset button - only while editing
                  if (_editMode)
                    _atc(c, 'resetLayout',
                        GestureDetector(
                          onTap: _resetLayout,
                          child: Container(
                            width: _innerSize('resetLayout', 44),
                            height: _innerSize('resetLayout', 44),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.buttonB,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.restart_alt,
                                color: Colors.white, size: 22),
                          ),
                        )),

                  // Add Macro button - only while editing
                  if (_editMode)
                    _atc(c, 'addMacro',
                        GestureDetector(
                          onTap: _addMacro,
                          child: Container(
                            width: _innerSize('addMacro', 44),
                            height: _innerSize('addMacro', 44),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.accentLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add,
                                color: Colors.black, size: 24),
                          ),
                        )),

                  // Macro buttons - created by the user, not present by default
                  ..._buildMacroButtons(c),

                  // Menu / Guide / Start Row
                  _atc(c, 'menu',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.menu,
                        size: _innerSize('menu', 60),
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitBack, p),
                      )),
                  _atc(c, 'guide',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.sports_esports,
                        size: _innerSize('guide', 68),
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitGuide, p),
                      )),
                  _atc(c, 'start',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.tune,
                        size: _innerSize('start', 60),
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitStart, p),
                      )),

                  // L3 / R3 Stick Clicks
                  // Hanya digambar pada layout Classic. Pada layout Xbox dan
                  // PlayStation, L3/R3 adalah tombol tekan pada analog stick
                  // itu sendiri, sehinggahandled olehJoystickWidget di bawah.
                  if (_layout == ButtonLayout.classic) ...[
                    _atc(c, 'l3',
                        GamepadButtonWidget(
                          label: 'LEFT',
                          pill: true,
                          size: _innerSize('l3', 40),
                          color: AppColors.stickFill,
                          onChanged: (p) =>
                              _handleButtonPress(Protocol.bitLsClick, p),
                        )),
                    _atc(c, 'r3',
                        GamepadButtonWidget(
                          label: 'RIGHT',
                          pill: true,
                          size: _innerSize('r3', 40),
                          color: AppColors.stickFill,
                          onChanged: (p) =>
                              _handleButtonPress(Protocol.bitRsClick, p),
                        )),
                  ],

                  // Left stick
                  _atc(c, 'leftStick',
                      JoystickWidget(
                        size: _innerSize('leftStick', 160),
                        onClick: _layout == ButtonLayout.classic
                            ? null
                            : (pressed) =>
                                _handleButtonPress(Protocol.bitLsClick, pressed),
                        onChanged: (x, y) {
                          _handleJoystickHaptic(x, y, true);
                          _state.setLeftStick(x, y);
                        },
                      )),

                  // Right stick
                  _atc(c, 'rightStick',
                      JoystickWidget(
                        size: _innerSize('rightStick', 160),
                        onClick: _layout == ButtonLayout.classic
                            ? null
                            : (pressed) =>
                                _handleButtonPress(Protocol.bitRsClick, pressed),
                        onChanged: (x, y) {
                          _handleJoystickHaptic(x, y, false);
                          _state.setRightStick(x, y);
                        },
                      )),

                  // RB - Upper Right
                  _atc(c, 'rb',
                      GamepadButtonWidget(
                        label: _layout == ButtonLayout.playstation ? 'R1' : 'RB',
                        size: _innerSize('rb', 70),
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitRb, p),
                      )),

                  // RT - Right Trigger
                  _atc(c, 'rt',
                      TriggerWidget(
                        label: _layout == ButtonLayout.playstation ? 'R2' : 'RT',
                        size: _innerSize('rt', 112),
                        onChanged: (v) {
                          _handleTriggerHaptic(v, false);
                          _state.setRightTrigger(v);
                        },
                      )),

                  // ABXY Diamond Layout
                  _atc(c, 'faceButtons', 
                      _FaceButtons(
                        onButtonPressed: _handleButtonPress,
                        size: _innerSize('faceButtons', 150),
                        layout: _layout,
                        buttonSize: _innerSize('faceButtons', 56))),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Empat tombol aksi (atas/bawah/kiri/kanan).
///
/// Pemetaan ke protocol bit selalu mengikuti Xbox (Y/A/X/B) supaya game di PC
/// tidak perlu tahu layout mana yang dipakai. Yang berubah hanya tampilan:
/// pada layout PlayStation simbol segitiga/bulat/kotak/silang dipakai, pada
/// layout Xbox/Classic memakai huruf A/B/X/Y berwarna.
class _FaceButtons extends StatelessWidget {
  final void Function(int buttonBit, bool isPressed) onButtonPressed;
  final double size;
  final double buttonSize;
  final ButtonLayout layout;

  const _FaceButtons({
    required this.onButtonPressed,
    required this.size,
    required this.layout,
    this.buttonSize = 56,
  });

  bool get _isPs => layout == ButtonLayout.playstation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Atas: Xbox Y / PS Triangle
          Positioned(
            top: 0,
            child: _face(
              bit: Protocol.bitY,
              color: AppColors.buttonY,
              psGlyph: _PsGlyph.triangle,
            ),
          ),
          // Bawah: Xbox A / PS Cross
          Positioned(
            bottom: 0,
            child: _face(
              bit: Protocol.bitA,
              color: AppColors.buttonA,
              psGlyph: _PsGlyph.cross,
            ),
          ),
          // Kiri: Xbox X / PS Square
          Positioned(
            left: 0,
            child: _face(
              bit: Protocol.bitX,
              color: AppColors.buttonX,
              psGlyph: _PsGlyph.square,
            ),
          ),
          // Kanan: Xbox B / PS Circle
          Positioned(
            right: 0,
            child: _face(
              bit: Protocol.bitB,
              color: AppColors.buttonB,
              psGlyph: _PsGlyph.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _face({
    required int bit,
    required Color color,
    required _PsGlyph psGlyph,
  }) {
    if (_isPs) {
      // Tombol PlayStation: bodies gelap dengan simbol berwarna dan border.
      return GamepadButtonWidget(
        label: '',
        size: buttonSize,
        solid: false,
        color: color,
        borderWidth: 2.5,
        borderColor: color,
        onChanged: (p) => onButtonPressed(bit, p),
        child: CustomPaint(
          size: Size.square(buttonSize * 0.52),
          painter: _PsGlyphPainter(psGlyph, color),
        ),
      );
    }

    // Xbox / Classic: huruf penuh warna.
    final labels = DefaultButtonConfigs.faceLabels(layout);
    String text;
    if (bit == Protocol.bitY) {
      text = labels[0];
    } else if (bit == Protocol.bitB) {
      text = labels[1];
    } else if (bit == Protocol.bitX) {
      text = labels[2];
    } else {
      text = labels[3];
    }

    return GamepadButtonWidget(
      label: text,
      size: buttonSize,
      color: color,
      onChanged: (p) => onButtonPressed(bit, p),
    );
  }
}

/// Bentuk simbol khas PlayStation.
enum _PsGlyph { triangle, circle, square, cross }

/// Menggambar simbol PlayStation dengan stroke, supaya tetap tajam di
/// semua ukuran dan tidak bergantung pada aset gambar eksternal.
class _PsGlyphPainter extends CustomPainter {
  final _PsGlyph glyph;
  final Color color;

  _PsGlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final path = Path();

    switch (glyph) {
      case _PsGlyph.triangle:
        path.moveTo(w / 2, h * 0.10);
        path.lineTo(w * 0.94, h * 0.88);
        path.lineTo(w * 0.06, h * 0.88);
        path.close();
        canvas.drawPath(path, stroke);

      case _PsGlyph.circle:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.38, stroke);

      case _PsGlyph.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.14, h * 0.14, w * 0.72, h * 0.72),
            Radius.circular(w * 0.10),
          ),
          stroke,
        );

      case _PsGlyph.cross:
        path.moveTo(w * 0.12, h * 0.12);
        path.lineTo(w * 0.88, h * 0.88);
        path.moveTo(w * 0.88, h * 0.12);
        path.lineTo(w * 0.12, h * 0.88);
        canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _PsGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}