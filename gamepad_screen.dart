import 'dart:async'; // Added to handle stream subscriptions
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gamepad_settings.dart';
import '../models/gamepad_state.dart';
import '../network/gamepad_socket.dart';
import '../network/protocol.dart';
import '../screens/settings_screen.dart';
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
  GamepadSettings? _settings;
  Map<String, ButtonConfig> _configs = {};
  bool _editMode = false;

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

    // Load pengaturan tombol dari SharedPreferences
    GamepadSettings.create().then((settings) {
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _configs = settings.loadConfigs();
      });
    });

    // Listen for disconnections automatically from the socket network manager
    _connectionSubscription = widget.socket.connectionStream.listen((isConnected) {
      if (!isConnected) {
        _handleConnectionLoss();
      }
    });
  }

  /// Buka layar pengaturan tombol.
  Future<void> _openSettings() async {
    if (_settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings!,
          configs: Map<String, ButtonConfig>.from(_configs),
          onSave: (newConfigs) {
            setState(() => _configs = newConfigs);
          },
        ),
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
  Widget _atc(BoxConstraints c, String id, Widget child, {double? wOverride, double? hOverride}) {
    final cfg = _configs[id];
    if (cfg == null) return const SizedBox.shrink();

    final w = (wOverride ?? cfg.width);
    final h = (hOverride ?? cfg.height);

    Widget content = Positioned(
      left: c.maxWidth * cfg.xFrac - w / 2,
      top: c.maxHeight * cfg.yFrac - h / 2,
      width: w,
      height: h,
      child: Center(child: child),
    );

    if (_editMode) {
      content = GestureDetector(
        onPanUpdate: (d) {
          final current = _configs[id];
          if (current == null) return;
          final curLeft = c.maxWidth * current.xFrac - w / 2;
          final curTop = c.maxHeight * current.yFrac - h / 2;
          final newLeft = curLeft + d.delta.dx;
          final newTop = curTop + d.delta.dy;
          setState(() {
            _configs[id] = current.copyWith(
              xFrac: ((newLeft + w / 2) / c.maxWidth).clamp(0.0, 1.0),
              yFrac: ((newTop + h / 2) / c.maxHeight).clamp(0.0, 1.0),
            );
          });
        },
        child: content,
      );
    }

    return content;
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

                  // Settings / Gear - Top Center Right
                  _atc(c, 'settings',
                      GestureDetector(
                        onTap: _openSettings,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.stickFill,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.settings, color: Colors.white, size: 22),
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