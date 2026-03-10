import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
// audioplayers is required for sound alerts.
// Add to pubspec.yaml:  audioplayers: ^6.1.0
// Add asset file:       assets/sounds/afk_alert.mp3  (any short beep ≤1 s)
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../core/feature_registry.dart';
import '../features/world_switcher/world_switcher_feature.dart';
import '../features/hiscores/hiscores_feature.dart';
import '../features/zoom/zoom_feature.dart';
import '../features/afk_timer/afk_timer_feature.dart';
import '../widgets/side_panel_drawer.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webViewController;

  String _currentUrl        = 'https://2004.lostcity.rs/client?world=2&detail=high&method=0';
  String _currentWorldLabel = 'W2 HD';
  bool   _pageLoading       = true;
  bool   _screenshotFlash   = false;
  int    _loadGen           = 0;
  double _zoomLevel         = 1.20;

  // ── Ping ──────────────────────────────────────────────────────────────────
  int?   _pingMs;
  Timer? _pingTimer;
  static const String _pingHost = 'https://2004.lostcity.rs/';

  // ── AFK Timer ─────────────────────────────────────────────────────────────
  AfkTimerSettings _afkSettings = const AfkTimerSettings();
  int    _afkRemaining = 90;
  bool   _afkAlerted   = false;
  Timer? _afkTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _afkAlertFlash = false; // red screen flash when alert fires

  // ── JS ────────────────────────────────────────────────────────────────────
  static const String _fullscreenJS = r'''
    (function makeFullscreen() {
      var iframe = document.querySelector('iframe.gameframe');
      if (!iframe) { setTimeout(makeFullscreen, 300); return; }

      iframe.style.cssText =
        'position:fixed!important;top:0!important;left:0!important;' +
        'width:100%!important;height:100%!important;' +
        'border:none!important;margin:0!important;padding:0!important;' +
        'z-index:1!important;display:block!important;';

      var header = document.querySelector('.gameframe-top');
      if (header) header.style.setProperty('display', 'none', 'important');

      document.body.style.cssText =
        'margin:0!important;padding:0!important;' +
        'overflow:hidden!important;background:#000!important;' +
        'touch-action:none!important;';
      document.documentElement.style.cssText =
        'margin:0!important;padding:0!important;' +
        'overflow:hidden!important;touch-action:none!important;';

      if (!window._lkScrollLocked) {
        window._lkScrollLocked = true;
        document.addEventListener('touchmove', function(e) {
          var node = e.target;
          while (node) {
            if (node.tagName === 'IFRAME') return;
            node = node.parentElement;
          }
          e.preventDefault();
        }, { passive: false });
      }

      window._lkReady = true;
    })();
  ''';

  static String _zoomJS(double zoom) =>
      "document.documentElement.style.setProperty('zoom', '$zoom', 'important');";

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _registerFeatures();
    _startPing();
    _initAudio();
  }

  Future<void> _initAudio() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    // Pre-load the asset so first play has no delay and no missing-source error.
    await _audioPlayer.setSource(AssetSource('sounds/afk_alert.mp3'));
    debugPrint('AFK audio pre-loaded OK');
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _afkTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Prefs ─────────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final url   = prefs.getString('last_world_url');
    final label = prefs.getString('last_world_label');
    final zoom  = prefs.getDouble('game_zoom') ?? 1.20;

    // AFK settings — enabled is always false on startup
    final afkThreshold  = prefs.getInt('afk_threshold')  ?? 10;
    final afkSound      = prefs.getBool('afk_sound')      ?? true;
    final afkVibration  = prefs.getBool('afk_vibration')  ?? true;

    if (mounted) {
      setState(() {
        if (url != null && label != null) {
          _currentUrl        = url;
          _currentWorldLabel = label;
        }
        _zoomLevel = zoom;
        _afkSettings = AfkTimerSettings(
          enabled          : false, // always off on startup
          soundEnabled     : afkSound,
          vibrationEnabled : afkVibration,
          thresholdSeconds : afkThreshold,
          durationSeconds  : 90,
        );
        _afkRemaining = _afkSettings.durationSeconds;
      });
      _registerFeatures();
    }
  }

  Future<void> _saveLastWorld(String url, String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_world_url',   url);
    await prefs.setString('last_world_label', label);
  }

  Future<void> _saveAfkSettings(AfkTimerSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    // Never persist 'enabled' — it always starts false
    await prefs.setInt ('afk_threshold',  s.thresholdSeconds);
    await prefs.setBool('afk_sound',      s.soundEnabled);
    await prefs.setBool('afk_vibration',  s.vibrationEnabled);
  }

  // ── Features ──────────────────────────────────────────────────────────────

  void _registerFeatures() {
    FeatureRegistry.features.clear();
    FeatureRegistry.registerAll([
      WorldSwitcherFeature(onWorldSelected: _onWorldSelected),
      HiscoresFeature(),
      ZoomFeature(
        currentZoom   : _zoomLevel,
        onZoomChanged : _onZoomChanged,
      ),
      AfkTimerFeature(
        settings         : _afkSettings,
        onSettingsChanged: _onAfkSettingsChanged,
      ),
    ]);
  }

  void _onWorldSelected(String url, String label) {
    _saveLastWorld(url, label);
    setState(() {
      _currentUrl        = url;
      _currentWorldLabel = label;
      _pageLoading       = true;
    });
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _onZoomChanged(double zoom) {
    setState(() => _zoomLevel = zoom);
    _webViewController?.evaluateJavascript(source: _zoomJS(zoom));
    _registerFeatures();
  }

  void _onAfkSettingsChanged(AfkTimerSettings next) {
    setState(() => _afkSettings = next);
    _saveAfkSettings(next);
    if (next.enabled) {
      _resetAfkTimer();
    } else {
      _afkTimer?.cancel();
      setState(() {
        _afkRemaining = next.durationSeconds;
        _afkAlerted   = false;
      });
    }
    _registerFeatures();
  }

  void _openPanel() {
    _registerFeatures();
    _scaffoldKey.currentState?.openDrawer();
  }

  // ── AFK Timer ─────────────────────────────────────────────────────────────

  /// Called on every pointer-down that lands on the game WebView area.
  /// The Listener uses HitTestBehavior.translucent so this fires without
  /// consuming the touch — the game receives it normally.
  void _onGameTouch() {
    if (!_afkSettings.enabled) return;
    _resetAfkTimer();
  }

  void _resetAfkTimer() {
    _afkTimer?.cancel();
    _afkAlerted = false;
    if (mounted) setState(() => _afkRemaining = _afkSettings.durationSeconds);
    debugPrint('AFK timer reset → ${_afkSettings.durationSeconds}s  threshold=${_afkSettings.thresholdSeconds}s');

    _afkTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }

      setState(() => _afkRemaining--);

      debugPrint('AFK tick: $_afkRemaining  alerted=$_afkAlerted');

      if (!_afkAlerted && _afkRemaining <= _afkSettings.thresholdSeconds) {
        _afkAlerted = true;
        debugPrint('AFK ALERT FIRING — sound=${_afkSettings.soundEnabled}  vib=${_afkSettings.vibrationEnabled}');
        _triggerAfkAlert();
      }
      // Timer intentionally never cancelled — continues into negative territory
      // so the badge turns blue and shows -MM:SS until user touches the screen.
    });
  }

  Future<void> _triggerAfkAlert() async {
    debugPrint('_triggerAfkAlert() entered');

    // ── Visual flash — always works regardless of sound/vibration ──
    if (mounted) {
      setState(() => _afkAlertFlash = true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _afkAlertFlash = false);
    }

    // ── Sound — resume pre-loaded asset ────────────────────────────
    if (_afkSettings.soundEnabled) {
      try {
        await _audioPlayer.resume();
        debugPrint('AFK sound resume() OK');
      } catch (e) {
        debugPrint('AFK sound error: $e');
        // Fallback: reload and play from scratch.
        try {
          await _audioPlayer.play(AssetSource('sounds/afk_alert.mp3'));
          debugPrint('AFK sound fallback play() OK');
        } catch (e2) {
          debugPrint('AFK sound fallback error: $e2');
        }
      }
    }

    // ── Vibration — uses `vibration` package for reliable Android motor ──
    if (_afkSettings.vibrationEnabled) {
      try {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          // Pattern: wait 0ms, buzz 400ms, pause 150ms, buzz 400ms, pause 150ms, buzz 400ms
          await Vibration.vibrate(
            pattern  : [0, 400, 150, 400, 150, 400],
            intensities: [0, 255, 0, 255, 0, 255],
          );
          debugPrint('AFK vibration fired');
        } else {
          debugPrint('AFK vibration: no vibrator found on device');
        }
      } catch (e) {
        debugPrint('AFK vibration error: $e');
      }
    }

    debugPrint('_triggerAfkAlert() complete');
  }

  // ── Ping ──────────────────────────────────────────────────────────────────

  void _startPing() {
    _measurePing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _measurePing());
  }

  Future<void> _measurePing() async {
    try {
      final sw     = Stopwatch()..start();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.headUrl(Uri.parse(_pingHost));
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      client.close(force: false);
      if (mounted) setState(() => _pingMs = sw.elapsedMilliseconds);
    } catch (_) {
      if (mounted) setState(() => _pingMs = null);
    }
  }

  Color _pingColor(int ms) {
    if (ms <= 80)  return const Color(0xFF44CC44);
    if (ms <= 150) return const Color(0xFFCCAA00);
    return const Color(0xFFCC0000);
  }

  // ── WebView helpers ───────────────────────────────────────────────────────

  Future<void> _applyFullscreen(InAppWebViewController ctrl, int gen) async {
    const pollInterval = Duration(milliseconds: 400);
    const maxAttempts  = 30;

    for (int i = 0; i < maxAttempts; i++) {
      if (!mounted || _loadGen != gen) return;
      await ctrl.evaluateJavascript(source: _fullscreenJS);
      await Future.delayed(pollInterval);
      if (!mounted || _loadGen != gen) return;

      final ready = await ctrl.evaluateJavascript(source: 'window._lkReady === true;');
      if (ready == true || ready == 'true') {
        await ctrl.evaluateJavascript(source: _zoomJS(_zoomLevel));
        if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
        return;
      }
    }
    await ctrl.evaluateJavascript(source: _zoomJS(_zoomLevel));
    if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
  }

  // ── Screenshot ────────────────────────────────────────────────────────────

  Future<void> _takeScreenshot() async {
    try {
      setState(() => _screenshotFlash = true);
      await Future.delayed(const Duration(milliseconds: 120));
      setState(() => _screenshotFlash = false);

      final Uint8List? screenshot = await _webViewController?.takeScreenshot();
      if (screenshot == null || !mounted) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await Gal.putImageBytes(screenshot, name: 'lostkit_$timestamp');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 Screenshot saved to gallery',
                style: TextStyle(fontFamily: 'RuneScape', fontSize: 12, color: Colors.white)),
            backgroundColor: Color(0xFF1A1A1A),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 20, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        );
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠ Screenshot failed',
                style: TextStyle(fontFamily: 'RuneScape', fontSize: 12, color: Colors.white)),
            backgroundColor: Color(0xFF8B0000),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 20, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawerScrimColor: Colors.transparent,
      drawer: const SidePanelDrawer(),
      body: Stack(
        children: [

          // ── WebView wrapped in Listener for AFK touch detection ────
          // HitTestBehavior.translucent means the Listener fires for
          // every pointer-down but does NOT consume the event —
          // the WebView (and therefore the game) receives it normally.
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onGameTouch(),
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled               : true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback       : true,
                useHybridComposition            : true,
                supportZoom                     : false,
                builtInZoomControls             : false,
                displayZoomControls             : false,
                horizontalScrollBarEnabled      : false,
                verticalScrollBarEnabled        : false,
                userAgent: 'Mozilla/5.0 (Linux; Android 11; Mobile) LostHQClient/1.0',
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                _loadGen++;
                controller.evaluateJavascript(source: 'window._lkReady = false;');
                if (mounted) setState(() => _pageLoading = true);
              },
              onLoadStop: (controller, url) async {
                final gen = _loadGen;
                await _applyFullscreen(controller, gen);
              },
              onReceivedError: (controller, request, error) {
                debugPrint('WebView error: ${error.description}');
                if (mounted) setState(() => _pageLoading = false);
              },
            ),
          ),

          // Loading overlay
          if (_pageLoading)
            Container(
              color: const Color(0xFF000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFCC0000)),
                    const SizedBox(height: 16),
                    const Text('Loading game...',
                        style: TextStyle(fontFamily: 'RuneScape',
                            color: Color(0xFFC8A450), fontSize: 14, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(_currentWorldLabel,
                        style: const TextStyle(fontFamily: 'RuneScape',
                            color: Color(0xFF666666), fontSize: 11)),
                  ],
                ),
              ),
            ),

          // Screenshot flash
          if (_screenshotFlash)
            IgnorePointer(child: Container(color: Colors.white.withOpacity(0.5))),

          // AFK alert flash — red overlay fires when threshold is hit
          if (_afkAlertFlash)
            IgnorePointer(child: Container(color: const Color(0xFFCC0000).withOpacity(0.25))),

          // ── Top-left: menu button ──────────────────────────────────
          Positioned(
            top: 6, left: 6,
            child: GestureDetector(
              onTap: _openPanel,
              child: _FloatButton(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (_) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    width: 16, height: 2,
                    color: const Color(0xFFC8A450),
                  )),
                ),
              ),
            ),
          ),

          // ── World label with ping stacked below it ─────────────────
          Positioned(
            top: 8, left: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              color: const Color(0xAA000000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // World name
                  Text(
                    _currentWorldLabel,
                    style: const TextStyle(
                      fontFamily : 'RuneScape',
                      color      : Color(0xFFC8A450),
                      fontSize   : 11,
                      fontWeight : FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Ping dot + ms
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _pingMs != null
                              ? _pingColor(_pingMs!)
                              : const Color(0xFF444444),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _pingMs != null ? '${_pingMs}ms' : '---',
                        style: TextStyle(
                          fontFamily: 'RuneScape',
                          fontSize  : 9,
                          color     : _pingMs != null
                              ? _pingColor(_pingMs!)
                              : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Top-right: screenshot button ───────────────────────────
          Positioned(
            top: 6, right: 6,
            child: GestureDetector(
              onTap: _takeScreenshot,
              child: _FloatButton(
                child: Image.asset(
                  'assets/capture.png',
                  width: 20, height: 20,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.camera_alt, color: Color(0xFFC8A450), size: 18),
                ),
              ),
            ),
          ),

          // ── AFK badge below screenshot button (only when enabled) ──
          if (_afkSettings.enabled)
            Positioned(
              top: 44, right: 6,   // 6 (top) + 34 (button) + 4 (gap)
              child: _AfkBadge(
                remaining       : _afkRemaining,
                thresholdSeconds: _afkSettings.thresholdSeconds,
              ),
            ),
        ],
      ),
    );
  }
}

// ── AFK countdown badge ───────────────────────────────────────────────────────

class _AfkBadge extends StatelessWidget {
  final int remaining;
  final int thresholdSeconds;

  const _AfkBadge({
    required this.remaining,
    required this.thresholdSeconds,
  });

  Color get _color {
    if (remaining < 0)                       return const Color(0xFF4499FF); // blue — expired
    if (remaining <= thresholdSeconds)       return const Color(0xFFCC0000);
    if (remaining <= thresholdSeconds + 10)  return const Color(0xFFCCAA00);
    return const Color(0xFF44CC44);
  }

  String get _label {
    if (remaining >= 0) {
      final m = remaining ~/ 60;
      final s = remaining % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      final abs = remaining.abs();
      final m   = abs ~/ 60;
      final s   = abs % 60;
      return '-${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color : const Color(0xCC000000),
        border: Border.all(color: _color.withOpacity(0.6), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'AFK',
            style: TextStyle(
              fontFamily   : 'RuneScape',
              fontSize     : 9,
              color        : _color.withOpacity(0.8),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _label,
            style: TextStyle(
              fontFamily : 'RuneScape',
              fontSize   : 18,
              fontWeight : FontWeight.bold,
              color      : _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Float button (unchanged) ──────────────────────────────────────────────────

class _FloatButton extends StatelessWidget {
  final Widget child;
  const _FloatButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color : const Color(0xBB000000),
        border: Border.all(color: const Color(0x558B6914)),
      ),
      child: Center(child: child),
    );
  }
}
