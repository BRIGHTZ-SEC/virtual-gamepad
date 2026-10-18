import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/gamepad_settings.dart';
import '../network/gamepad_socket.dart';
import '../network/protocol.dart';
import '../theme.dart';
import 'gamepad_screen.dart';
import 'layout_selection_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final GamepadSocket _socket = GamepadSocket();
  final TextEditingController _ipController = TextEditingController();
  final Map<String, DiscoveredHost> _found = {}; 
  Timer? _discoverTimer;
  Timer? _searchClock;
  StreamSubscription? _discoverSub;
  StreamSubscription? _statusSub;
  bool _connecting = false;
  String? _error;
  int _secondsSearching = 0;
  List<String> _myAddresses = [];

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    setState(() => _connecting = false);

    _discoverSub = _socket.discoveredStream.listen((host) {
      setState(() => _found[host.address] = host);
    });
    _statusSub = _socket.statusStream.listen(_onStatus);
    _socket.localAddresses().then((addrs) {
      if (mounted) setState(() => _myAddresses = addrs);
    });
    _startDiscovery();
  }

  void _startDiscovery() {
    setState(() => _secondsSearching = 0);
    _socket.discover();
    _discoverTimer?.cancel();
    _discoverTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _socket.discover());
    _searchClock?.cancel();
    _searchClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsSearching++);
    });
  }

  void _onStatus(ConnectionStatus status) {
    if (!mounted) return;
    if (status == ConnectionStatus.connected) {
      setState(() => _connecting = false);
      _openLayoutSelection();
    } else if (status == ConnectionStatus.error) {
      setState(() {
        _connecting = false;
        _error = 'PC rejected the connection. Is ViGEmBus installed there?';
      });
    }
  }

  /// Setelah koneksi berhasil, tampilkan layar pilihan layout (Xbox / PS /
  /// Classic) sebelum masuk ke gamepad. Layar ini tidak bisa ditutup dengan
  /// tombol back, jadi pengguna selalu memilih salah satu layout.
  Future<void> _openLayoutSelection() async {
    if (!mounted) return;
    final settings = await GamepadSettings.create();
    if (!mounted) return;

    final chosen = await Navigator.of(context).push<ButtonLayout>(
      MaterialPageRoute(
        builder: (_) => LayoutSelectionScreen(
          settings: settings,
          onSelected: (layout) => Navigator.of(context).pop(layout),
        ),
      ),
    );

    // Guard: bila layar ditutup tanpa memilih (mis. context sudah tidak
    // valid), jangan coba lanjut ke gamepad.
    if (!mounted || chosen == null) return;

    await Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => GamepadScreen(
          socket: _socket,
          settings: settings,
          layout: chosen,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _error = null);
    _found.clear();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _startDiscovery();
  }

  Future<void> _connectTo(String ip) async {
    _discoverTimer?.cancel();
    _searchClock?.cancel();
    setState(() {
      _connecting = true;
      _error = null;
    });
    await _socket.connect(ip, deviceName: 'Phone');

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _connecting) {
        setState(() {
          _connecting = false;
          _error = 'No response from $ip.\n\n'
              '• Make sure VirtualGamepadHost.exe is running on the PC\n'
              '• Confirm both devices are on the same WiFi network\n'
              '• Check Windows Firewall allowed the app (all network types)\n'
              '• Port ${Protocol.port}/UDP must be reachable';
        });
      }
    });
  }

  @override
  void dispose() {
    _discoverTimer?.cancel();
    _searchClock?.cancel();
    _discoverSub?.cancel();
    _statusSub?.cancel();
    _socket.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  children: [
                    // Centered header, matching the design
                    Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.iconBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.sports_esports,
                              color: Colors.white, size: 50),
                        ),
                        const SizedBox(height: 12),
                        const Text('Virtual Gamepad',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('FREE FOREVER · WIFI CONTROLLER',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            )),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _SectionHeader(
                      title: 'Nearby PCs',
                      trailing: _found.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: () {
                                setState(() => _found.clear());
                                _startDiscovery();
                              },
                              icon: const Icon(Icons.refresh,
                                  size: 16, color: Colors.white70),
                              label: const Text('Refresh',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                    ),
                    const SizedBox(height: 10),
                    if (_found.isEmpty)
                      _SearchingCard(
                          seconds: _secondsSearching, onRetry: _startDiscovery),
                    ..._found.values.map((h) => _HostCard(
                          host: h,
                          connecting: _connecting,
                          onTap:
                              _connecting ? null : () => _connectTo(h.address),
                        )),
                    const SizedBox(height: 28),
                    const _SectionHeader(title: 'Enter PC IP manually'),
                    const SizedBox(height: 10),
                    _ManualEntryCard(
                      controller: _ipController,
                      connecting: _connecting,
                      onConnect: () => _connectTo(_ipController.text.trim()),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.redAccent.withOpacity(0.4)),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                height: 1.4)),
                      ),
                    ],
                    if (_myAddresses.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('This phone: ${_myAddresses.join(", ")}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18, top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        children: [
                          const TextSpan(text: 'Made with ❤️ by '),
                          TextSpan(
                            text: 'Mohammad Kaif',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final uri = Uri.parse(
                                    'https://kaif.atomprod.in');
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12.5,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Copyright © 2026 ',
                          ),
                          TextSpan(
                            text: 'Atomprod',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final uri = Uri.parse('https://atomprod.in');
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SearchingCard extends StatelessWidget {
  final int seconds;
  final VoidCallback onRetry;
  const _SearchingCard({required this.seconds, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final stuck = seconds >= 6;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Searching your WiFi network for PCs running Virtual Gamepad Host...',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 13),
                ),
              ),
            ],
          ),
          if (stuck) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withOpacity(0.2), height: 1),
            const SizedBox(height: 12),
            Text(
              "Not finding it? Some routers block automatic discovery (guest WiFi, "
              "mesh networks, or \"AP isolation\" settings). Enter the PC's IP shown "
              "in its window below instead - it always works.",
              style: TextStyle(
                  color: Colors.amber.shade100, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: const Text('Search again',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  final DiscoveredHost host;
  final bool connecting;
  final VoidCallback? onTap;
  const _HostCard(
      {required this.host, required this.connecting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.desktop_windows_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(host.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      Text(host.address,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 12.5)),
                    ],
                  ),
                ),
                connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.arrow_forward_ios,
                        size: 14, color: Colors.white.withOpacity(0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualEntryCard extends StatelessWidget {
  final TextEditingController controller;
  final bool connecting;
  final VoidCallback onConnect;
  const _ManualEntryCard(
      {required this.controller,
      required this.connecting,
      required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white70),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.dns_rounded,
                  color: Colors.white70, size: 20),
              hintText: '10.25.224.56',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: connecting || !hasText ? null : onConnect,
                  child: connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('CONNECT',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
