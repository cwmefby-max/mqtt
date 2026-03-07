import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'mqtt_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (context) => MQTTService(),
      child: const GemparaApp(),
    ),
  );
}

class GemparaApp extends StatefulWidget {
  const GemparaApp({super.key});

  @override
  State<GemparaApp> createState() => _GemparaAppStage();
}

class _GemparaAppStage extends State<GemparaApp> {
  bool isDarkMode = false;

  void toggleTheme() {
    setState(() => isDarkMode = !isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: isDarkMode ? const Color(0xFF1E272E) : const Color(0xFFF8F9FB),
      systemNavigationBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF8F9FB),
          useMaterial3: true),
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF1E272E),
          useMaterial3: true),
      home: MainNavigator(onThemeToggle: toggleTheme, isDark: isDarkMode),
    );
  }
}

class MainNavigator extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDark;
  const MainNavigator({super.key, required this.onThemeToggle, required this.isDark});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with TickerProviderStateMixin {
  bool isIotVisible = true;
  bool isLocked = true;
  bool isRelayOn = false;
  bool isAlarmOn = false;
  bool isAlarmAnimating = false;
  bool isRouteActive = false;
  bool isStartActive = false;
  bool isSeatActive = false;
  bool isFuelActive = false;
  bool isFocusActive = false;
  bool isCompassActive = false;

  String _currentAddress = "Mencari lokasi...";
  StreamSubscription<Position>? _positionStream;
  LatLng? _currentPosition;
  late MapController _mapController;
  bool _isMapFollowing = true;

  late AnimationController _scanController;
  late AnimationController _panelController;
  late Animation<Offset> _panelSlideAnimation;
  bool _showScanAnim = false;

  late PageController _infoPageController;
  late PageController _vehiclePageController;
  final int _currentVirtualPage = 10000;
  Timer? _vehicleInfoTimer;
  int _currentInfoPage = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _infoPageController = PageController(initialPage: _currentVirtualPage);
    _vehiclePageController = PageController(initialPage: _currentVirtualPage);

    _infoPageController.addListener(() {
      if (_infoPageController.hasClients && _infoPageController.page != null) {
        setState(() {
          _currentInfoPage = _infoPageController.page!.round() % 2;
        });
      }
    });

    _scanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _panelController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _panelSlideAnimation = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
        CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic));

    if (isIotVisible) _panelController.forward();

    _vehicleInfoTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_vehiclePageController.hasClients) {
        _vehiclePageController.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mqttService = Provider.of<MQTTService>(context, listen: false);
      if (!mqttService.isConnected) {
        mqttService.connect('test.mosquitto.org', 'flutter_gempara_client');
      }
      _initializeLocationStream();
    });
    _loadButtonStates();
  }

  Future<void> _initializeLocationStream() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _currentAddress = "Izin lokasi ditolak";
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _currentAddress = "Izin lokasi ditolak permanen";
      });
      return;
    }

    _positionStream = Geolocator.getPositionStream().listen((Position position) async {
      if (!mounted) return;

      final newPosition = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = newPosition;
      });

      if (_isMapFollowing) {
        _mapController.move(newPosition, 17.0);
      }

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          if (mounted) {
            setState(() {
              _currentAddress = "${placemark.subLocality}, ${placemark.locality}";
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _currentAddress = "Lokasi tidak ditemukan";
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentAddress = "Gagal mendapatkan lokasi";
          });
        }
      }
    });
  }


  Future<void> _loadButtonStates() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isRelayOn = prefs.getBool('isRelayOn') ?? false;
      isLocked = prefs.getBool('isLocked') ?? true;
    });
  }

  Future<void> _saveButtonState(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(key, value);
  }

  void _vibrateInstan() {
    HapticFeedback.lightImpact();
  }

  void _triggerScan() async {
    setState(() => _showScanAnim = true);
    await _scanController.forward();
    await _scanController.reverse();
    setState(() => _showScanAnim = false);
  }

  void _triggerAlarmAnimation() async {
    if (isAlarmAnimating) return;

    final mqttService = Provider.of<MQTTService>(context, listen: false);
    mqttService.publish('iot/alarm', 'TRIGGER');

    setState(() {
      isAlarmAnimating = true;
    });

    for (int i = 0; i < 30; i++) {
      if (!mounted) return;
      setState(() => isAlarmOn = true);
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() => isAlarmOn = false);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;
    setState(() {
      isAlarmAnimating = false;
    });
  }

  void _toggleIotPanel() {
    if (isIotVisible) {
      _panelController.reverse().then((_) => setState(() => isIotVisible = false));
    } else {
      setState(() => isIotVisible = true);
      _panelController.forward();
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _panelController.dispose();
    _infoPageController.dispose();
    _vehiclePageController.dispose();
    _vehicleInfoTimer?.cancel();
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  BoxDecoration neuBox({bool isPressed = false, double borderRadius = 20, bool isDisabled = false}) {
    bool isDark = widget.isDark;
    Color bg = isDark ? const Color(0xFF1E272E) : const Color(0xFFFDFDFD);
    if (isDisabled) bg = bg.withAlpha(128);
    Color shadowDark = isDark ? Colors.black.withAlpha(102) : const Color(0xFFD1D9E6).withAlpha(128);

    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: isDisabled
          ? []
          : [
              BoxShadow(
                color: shadowDark,
                offset: isPressed ? const Offset(2, 2) : const Offset(6, 6),
                blurRadius: isPressed ? 4 : 12,
                spreadRadius: 1,
              ),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = widget.isDark;
    final mqttService = Provider.of<MQTTService>(context);
    final bool isDeviceOffline = !mqttService.isDeviceOnline;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? LatLng(0, 0),
              initialZoom: 17.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _isMapFollowing = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: widget.isDark
                    ? "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
                    : "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
                subdomains: const ['a', 'b', 'c'],
              ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 80.0,
                      height: 80.0,
                      point: _currentPosition!,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                children: [
                  Container(
                    decoration: neuBox(),
                    padding: const EdgeInsets.only(top: 12, left: 18, right: 18, bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center, // This is the key fix
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildSignalBar("APP", mqttService.isConnected),
                                    const SizedBox(width: 12),
                                    _buildSignalBar("ESP", mqttService.isDeviceOnline),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text("SmartLock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: isDark ? Colors.white : const Color(0xFF2C3E50))),
                                Text(_currentAddress, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text("version 1.0.0 by Mefby", style: TextStyle(fontSize: 8, color: Colors.grey.withAlpha(178), fontWeight: FontWeight.bold)),
                                ),
                                Row(
                                  children: [
                                     _buildTopIcon(
                                      isAlarmOn ? Icons.notifications_active : Icons.notifications,
                                      isAlarmOn,
                                      () {
                                        _vibrateInstan();
                                        _triggerAlarmAnimation();
                                      },
                                      isDisabled: isAlarmAnimating || isDeviceOffline,
                                    ),
                                    const SizedBox(width: 10),
                                    _buildTopIcon(isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round, false, widget.onThemeToggle),
                                    const SizedBox(width: 10),
                                    _buildTopIcon(Icons.videogame_asset_rounded, isIotVisible, _toggleIotPanel),
                                  ],
                                ),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 15),
                        Divider(color: isDark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(13)),
                        SizedBox(
                          height: 60,
                          child: PageView.builder(
                            controller: _infoPageController,
                            itemBuilder: (context, index) => index % 2 == 0
                                ? Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStat("SPEED", "0 km/h"), _buildStat("JARAK", "1.2 km"), _buildStat("ETA", "4 m"), _buildStat("SUHU", "32°")])
                                : Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStat("BATTERY", "12.8V"), _buildStat("FUEL", "85%"), _buildStat("LAST", mqttService.statusPower), _buildStat("STATUS", "Aman")]),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDot(_currentInfoPage == 0),
                            const SizedBox(width: 6),
                            _buildDot(_currentInfoPage == 1),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Stack(
                        children: [
                          SlideTransition(
                            position: _panelSlideAnimation,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 15),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
                                decoration: neuBox(borderRadius: 30),
                                child: Column(
                                  children: [
                                    Text("KONTROL UNIT", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: isDark ? Colors.white70 : Colors.black54)),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 15,
                                      child: PageView.builder(
                                        controller: _vehiclePageController,
                                        scrollDirection: Axis.vertical,
                                        itemBuilder: (context, index) => Center(child: Text(index % 2 == 0 ? "Aerox 155 VVA" : "W 3601 QY", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                                      ),
                                    ),
                                    const Spacer(),
                                    _buildStartButton(mqttService, isDeviceOffline),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Expanded(child: _buildVerticalGridBtn(isRelayOn ? "ON" : "OFF", Icons.power_settings_new_rounded, isRelayOn, () {
                                          if (!isLocked) {
                                            _vibrateInstan();
                                            final newState = !isRelayOn;
                                            mqttService.publish('iot/power', newState ? 'ON' : 'OFF');
                                            setState(() => isRelayOn = newState);
                                            _saveButtonState('isRelayOn', newState);
                                            if (newState) _triggerScan();
                                          }
                                        }, isDisabled: isLocked || isDeviceOffline)),
                                        const SizedBox(width: 15),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              _buildHoldBtn("SEAT", Icons.archive_rounded, isSeatActive, isRelayOn || isDeviceOffline, (val) {
                                                if (!isRelayOn) {
                                                  if (val) { _vibrateInstan(); mqttService.publish('iot/seat', 'TRIGGER'); }
                                                  setState(() => isSeatActive = val);
                                                }
                                              }),
                                              const SizedBox(height: 15),
                                              _buildHoldBtn("FUEL", Icons.local_gas_station_rounded, isFuelActive, isRelayOn || isDeviceOffline, (val) {
                                                if (!isRelayOn) {
                                                  if (val) { _vibrateInstan(); mqttService.publish('iot/fuel', 'TRIGGER'); }
                                                  setState(() => isFuelActive = val);
                                                }
                                              }),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 15),
                                        Expanded(child: _buildVerticalGridBtn(isLocked ? "LOCKED" : "UNLOCK", isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, isLocked, () {
                                          if (!isRelayOn) {
                                            _vibrateInstan();
                                            final newState = !isLocked;
                                            mqttService.publish('iot/lock', newState ? 'LOCKED' : 'UNLOCK');
                                            setState(() => isLocked = newState);
                                            _saveButtonState('isLocked', newState);
                                          }
                                        }, isDisabled: isRelayOn || isDeviceOffline)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isIotVisible)
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFloatBtn(Icons.my_location_rounded, () {
                    setState(() {
                      isFocusActive = true;
                      _isMapFollowing = true;
                    });
                    if (_currentPosition != null) {
                      _mapController.move(_currentPosition!, 17.0);
                    }
                    Future.delayed(const Duration(milliseconds: 200), () => setState(() => isFocusActive = false));
                  }, isActive: isFocusActive),
                  const SizedBox(width: 25),
                  _buildFloatBtn(Icons.map_rounded, () { setState(() => isRouteActive = !isRouteActive); }, isActive: isRouteActive),
                  const SizedBox(width: 25),
                  _buildFloatBtn(Icons.explore_rounded, () {
                    setState(() => isCompassActive = true);
                    _mapController.rotate(0);
                    Future.delayed(const Duration(milliseconds: 200), () => setState(() => isCompassActive = false));
                  }, isActive: isCompassActive),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildStartButton(MQTTService mqttService, bool isDeviceOffline) {
    final bool isDisabled = !isRelayOn || isDeviceOffline;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_showScanAnim)
          AnimatedBuilder(
            animation: _scanController,
            builder: (context, child) => SizedBox(
              width: 175, height: 175,
              child: CustomPaint(painter: DottedCirclePainter(progress: _scanController.value)),
            ),
          ),
        GestureDetector(
          onTapDown: (_) async {
            if (!isDisabled) {
              Vibration.vibrate(duration: 500);
              mqttService.publish('iot/starter', 'TRIGGER');
              setState(() => isStartActive = true);
            }
          },
          onTapUp: (_) => setState(() => isStartActive = false),
          onTapCancel: () => setState(() => isStartActive = false),
          child: Opacity(
            opacity: isDisabled ? 0.4 : 1.0,
            child: Container(
              width: 140, height: 140,
              decoration: neuBox(isPressed: isStartActive, borderRadius: 80, isDisabled: isDisabled),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, color: isStartActive ? Colors.greenAccent : (widget.isDark ? Colors.white : Colors.black54), size: 60),
                  const Text("START ENGINE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalGridBtn(String label, IconData icon, bool isActive, VoidCallback onTap, {bool isDisabled = false}) {
    return GestureDetector(
      onTap: () { if(!isDisabled) onTap(); },
      child: Opacity(
        opacity: isDisabled ? 0.3 : 1.0,
        child: Container(
          height: 125,
          decoration: neuBox(isPressed: isActive, borderRadius: 20, isDisabled: isDisabled),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: isActive ? const Color(0xFFFF7675) : (widget.isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : const Color(0xFF2C3E50))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHoldBtn(String label, IconData icon, bool isActive, bool isDisabled, Function(bool) onChanged) {
    return GestureDetector(
      onTapDown: (_) { if (!isDisabled) onChanged(true); },
      onTapUp: (_) => onChanged(false),
      onTapCancel: () => onChanged(false),
      child: Opacity(
        opacity: isDisabled ? 0.3 : 1.0,
        child: Container(
          height: 55, width: double.infinity,
          decoration: neuBox(isPressed: isActive, borderRadius: 15, isDisabled: isDisabled),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isActive ? const Color(0xFFFF7675) : (widget.isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : const Color(0xFF2C3E50))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopIcon(IconData icon, bool active, VoidCallback onTap, {bool isDisabled = false}) =>
      GestureDetector(
        onTap: isDisabled ? null : onTap,
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Container(
              width: 42,
              height: 42,
              decoration: neuBox(isPressed: active, borderRadius: 12, isDisabled: isDisabled),
              child: Icon(icon,
                  size: 20,
                  color: active
                      ? const Color(0xFFFF7675)
                      : (widget.isDark ? Colors.white : const Color(0xFF2C3E50)))),
        ),
      );

  Widget _buildDot(bool active) => Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.greenAccent : Colors.grey.withAlpha(77)));
  
  Widget _buildStat(String label, String value) {
    final defaultColor = widget.isDark ? Colors.white : const Color(0xFF2C3E50);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: defaultColor)),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold))
      ]
    );
  }

  Widget _buildFloatBtn(IconData icon, VoidCallback onTap, {required bool isActive}) => GestureDetector(
    onTap: onTap,
    child: Container(width: 50, height: 50, decoration: neuBox(isPressed: isActive, borderRadius: 25), child: Icon(icon, size: 20, color: isActive ? Colors.blueAccent : (widget.isDark ? Colors.white : const Color(0xFF2C3E50)))),
  );

  Widget _buildSignalBar(String label, bool isConnected) {
    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        const SizedBox(width: 28, height: 16),
        Positioned(
          bottom: 0,
          left: 17, 
          child: SizedBox(
            width: 11, 
            height: 8, 
            child: CustomPaint(
              painter: SignalBarPainter(
                isConnected: isConnected,
                activeColor: Colors.greenAccent,
                inactiveColor: const Color(0xFFFF7675),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0, // Adjusted for alignment
          left: 0,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8, 
              fontWeight: FontWeight.bold,
              color: isConnected
                  ? (widget.isDark ? Colors.white70 : const Color(0xFF2C3E50))
                  : const Color(0xFFFF7675),
            ),
          ),
        ),
      ],
    );
  }
}

class DottedCirclePainter extends CustomPainter {
  final double progress;
  DottedCirclePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.greenAccent.withAlpha(153)
      ..style = PaintingStyle.fill;

    double radius = size.width / 2;
    int dotsCount = 45;
    double currentArc = 2 * math.pi * progress;

    for (int i = 0; i < dotsCount; i++) {
      double angle = (2 * math.pi / dotsCount) * i;
      if (angle <= currentArc) {
        double x = radius + radius * math.cos(angle + math.pi / 2);
        double y = radius + radius * math.sin(angle + math.pi / 2);
        canvas.drawCircle(Offset(x, y), 2.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DottedCirclePainter oldDelegate) => oldDelegate.progress != progress;
}

class SignalBarPainter extends CustomPainter {
  final bool isConnected;
  final Color activeColor;
  final Color inactiveColor;

  SignalBarPainter({
    required this.isConnected,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isConnected ? activeColor : inactiveColor;
    final double barWidth = size.width / 4.5;
    final double barSpacing = barWidth / 4;

    final heights = [size.height * 0.4, size.height * 0.6, size.height * 0.8, size.height * 1.0];

    for (int i = 0; i < 4; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  i * (barWidth + barSpacing),
                  size.height - heights[i],
                  barWidth,
                  heights[i]),
              const Radius.circular(1)),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignalBarPainter oldDelegate) =>
      oldDelegate.isConnected != isConnected;
}
