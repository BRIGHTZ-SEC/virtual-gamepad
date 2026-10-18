import 'dart:async'; // Added to handle stream subscriptions
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gamepad_settings.dart';
import '../models/gamepad_state.dart';
import '../network/gamepad_socket.dart';
import '../network/protocol.dart';
import '../theme.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/gamepad_button_widget.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/trigger_widget.dart';

class GamepadScreen extends StatefulWidget {
  final GamepadSocket socket;
  const GamepadScreen({super.key, required this.socket});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  late final GamepadState _state;
  StreamSubscription? _connectionSubscription; // Handles the socket listener state
  // Selalu non-null: mulai dari instance in-memory supaya ikon pengaturan
  // selalu bisa dibuka, walau SharedPreferences gagal dimuat belakangan.
  GamepadSettings _settings = GamepadSettings.fallback();
  // Mulai dari default sinkron supaya tombol langsung tampil walau
  // SharedPreferences belum selesai dimuat atau gagal dimuat.
  Map<String, ButtonConfig> _configs = DefaultButtonConfigs.defaultConfigs();
  bool _editMode = false;

  // State gesture untuk mode edit: ukuran awal saat pinch dimulai.
  final Map<String, (double, double)> _gestureStartSizes = {};

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

    // Load pengaturan tombol dari SharedPreferences. Kegagalan di sini
    // tidak boleh membuat layar kosong, jadi default sudah terpasang di atas.
    _loadSettings();

    // Listen for disconnections automatically from the socket network manager
    _connectionSubscription = widget.socket.connectionStream.listen((isConnected) {
      if (!isConnected) {
        _handleConnectionLoss();
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await GamepadSettings.create();
      if (!mounted) return;
      final loaded = settings.loadConfigs();
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
      _settings.saveConfigs(_configs);
      _settings.saveSizeMultiplier(1.0);
    } catch (e) {
      debugPrint('Gagal menyimpan layout: $e');
    }
    _banner('Layout tersimpan.', AppColors.buttonA);
  }

  /// Reset semua tombol ke posisi & ukuran default.
  void _resetLayout() {
    HapticFeedback.heavyImpact();
    setState(() => _configs = DefaultButtonConfigs.defaultConfigs());
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

  @override
  void dispose() {
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

  /// Buat widget berposisi berdasarkan config tombol. Saat _editMode aktif,
  /// tombol bisa di-drag untuk mengganti posisinya secara visual.
  /// Membangun widget tombol pada posisi dari config.
  ///
  /// Saat [_editMode] aktif, tombol bisa digeser satu jari dan diubah
  /// ukurannya dengan cubitan dua jari. Editan hanya berlaku di config
  /// in-memory dan disimpan ke [_saveLayout] saat mode edit dimatikan.
  Widget _atc(BoxConstraints c, String id, Widget child, {double? wOverride, double? hOverride}) {
    final cfg = _configs[id] ?? DefaultButtonConfigs.defaultConfigs()[id];
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
                        label: 'LT', 
                        size: 112, 
                        onChanged: (v) {
                          _handleTriggerHaptic(v, true);
                          _state.setLeftTrigger(v);
                        },
                      )),

                  // LB - Left Bumper
                  _atc(c, 'lb',
                      GamepadButtonWidget(
                        label: 'LB',
                        size: 70,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitLb, p),
                      )),

                  // D-pad - Lower Left
                  _atc(c, 'dpad',
                      DpadWidget(
                        size: 150,
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
                          width: 44,
                          height: 44,
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
                            width: 44,
                            height: 44,
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
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.buttonB,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.restart_alt,
                                color: Colors.white, size: 22),
                          ),
                        )),

                  // Menu / Guide / Start Row
                  _atc(c, 'menu',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.menu,
                        size: 60,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitBack, p),
                      )),
                  _atc(c, 'guide',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.sports_esports,
                        size: 68,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitGuide, p),
                      )),
                  _atc(c, 'start',
                      GamepadButtonWidget(
                        label: '',
                        icon: Icons.tune,
                        size: 60,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitStart, p),
                      )),

                  // L3 / R3 Stick Clicks
                  _atc(c, 'l3',
                      GamepadButtonWidget(
                        label: 'LEFT',
                        pill: true,
                        size: 40,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitLsClick, p),
                      )),
                  _atc(c, 'r3',
                      GamepadButtonWidget(
                        label: 'RIGHT',
                        pill: true,
                        size: 40,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitRsClick, p),
                      )),

                  // Left stick
                  _atc(c, 'leftStick',
                      JoystickWidget(
                        size: 160, 
                        onChanged: (x, y) {
                          _handleJoystickHaptic(x, y, true);
                          _state.setLeftStick(x, y);
                        },
                      )),

                  // Right stick
                  _atc(c, 'rightStick',
                      JoystickWidget(
                        size: 160, 
                        onChanged: (x, y) {
                          _handleJoystickHaptic(x, y, false);
                          _state.setRightStick(x, y);
                        },
                      )),

                  // RB - Upper Right
                  _atc(c, 'rb',
                      GamepadButtonWidget(
                        label: 'RB',
                        size: 70,
                        color: AppColors.stickFill,
                        onChanged: (p) => _handleButtonPress(Protocol.bitRb, p),
                      )),

                  // RT - Right Trigger
                  _atc(c, 'rt',
                      TriggerWidget(
                        label: 'RT',
                        size: 112,
                        onChanged: (v) {
                          _handleTriggerHaptic(v, false);
                          _state.setRightTrigger(v);
                        },
                      )),

                  // ABXY Diamond Layout
                  _atc(c, 'faceButtons', 
                      _FaceButtons(onButtonPressed: _handleButtonPress, size: 150)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FaceButtons extends StatelessWidget {
  final void Function(int buttonBit, bool isPressed) onButtonPressed;
  final double size;
  const _FaceButtons({required this.onButtonPressed, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: GamepadButtonWidget(
              label: 'Y',
              color: AppColors.buttonY,
              onChanged: (p) => onButtonPressed(Protocol.bitY, p),
            ),
          ),
          Positioned(
            bottom: 0,
            child: GamepadButtonWidget(
              label: 'A',
              color: AppColors.buttonA,
              onChanged: (p) => onButtonPressed(Protocol.bitA, p),
            ),
          ),
          Positioned(
            left: 0,
            child: GamepadButtonWidget(
              label: 'X',
              color: AppColors.buttonX,
              onChanged: (p) => onButtonPressed(Protocol.bitX, p),
            ),
          ),
          Positioned(
            right: 0,
            child: GamepadButtonWidget(
              label: 'B',
              color: AppColors.buttonB,
              onChanged: (p) => onButtonPressed(Protocol.bitB, p),
            ),
          ),
        ],
      ),
    );
  }
}