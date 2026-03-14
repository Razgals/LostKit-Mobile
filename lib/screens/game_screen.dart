import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ── Game WebView ───────────────────────────────────────────────────────────
  InAppWebViewController? _webViewController;
  String _currentUrl        = 'https://2004.lostcity.rs/client?world=2&detail=high&method=0';
  String _currentWorldLabel = 'W2 HD';
  bool   _pageLoading       = true;
  bool   _screenshotFlash   = false;
  int    _loadGen           = 0;

  // ── Tabs ──────────────────────────────────────────────────────────────────
  int  _activeTab    = 0;
  bool _tabsVisible  = true;
  bool _rightVisible = true;

  // Per-tab zoom — index matches tab number
  final List<double> _tabZoom = [1.20, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
  static const List<String> _tabZoomKeys = [
    'zoom_game',
    'zoom_coords',
    'zoom_clues',
    'zoom_map',
    'zoom_markets',
    'zoom_quests',
    'zoom_calcs',
    'zoom_lclab',
  ];

  double get _currentZoom => _tabZoom[_activeTab];

  // Controllers for tabs 1–7
  InAppWebViewController? _coordsController;
  InAppWebViewController? _cluesController;
  InAppWebViewController? _mapController;
  InAppWebViewController? _marketsController;
  InAppWebViewController? _questsController;
  InAppWebViewController? _calcsController;
  InAppWebViewController? _lclabController;

  // Loading states for tabs 1–7
  bool _coordsLoading  = false;
  bool _cluesLoading   = false;
  bool _mapLoading     = false;
  bool _marketsLoading = false;
  bool _questsLoading  = false;
  bool _calcsLoading   = false;
  bool _lclabLoading   = false;

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

  // ── Pinch-to-wheel + single-finger pan JS (Coords tab — Leaflet map) ────────
  // Two fingers  → WheelEvent (zoom in/out)
  // One finger   → mousedown/mousemove/mouseup (pan the map)
  static const String _pinchToWheelJS = r'''
    (function() {
      if (window._pinchWheelActive) return;
      window._pinchWheelActive = true;

      var lastDist   = null;
      var rafPending = false;
      var pendingDelta = 0;
      var pendingCx = 0;
      var pendingCy = 0;

      // ── Single-finger pan ──────────────────────────────────────────
      var panning    = false;
      var panTarget  = null;

      function mouseEvt(type, touch) {
        return new MouseEvent(type, {
          bubbles: true, cancelable: true, view: window,
          clientX: touch.clientX, clientY: touch.clientY,
          screenX: touch.screenX, screenY: touch.screenY,
          buttons: type === 'mouseup' ? 0 : 1,
          button : 0,
        });
      }

      document.addEventListener('touchstart', function(e) {
        if (e.touches.length === 1) {
          // Single finger — start pan
          panning   = true;
          panTarget = document.elementFromPoint(
              e.touches[0].clientX, e.touches[0].clientY) || document.body;
          panTarget.dispatchEvent(mouseEvt('mousedown', e.touches[0]));
        } else if (e.touches.length === 2) {
          // Two fingers — cancel any pan, start pinch
          if (panning && panTarget) {
            panTarget.dispatchEvent(mouseEvt('mouseup', e.touches[0]));
            panning = false; panTarget = null;
          }
          lastDist = dist(e.touches);
          e.preventDefault();
        }
      }, { passive: false });

      document.addEventListener('touchmove', function(e) {
        if (e.touches.length === 1 && panning && panTarget) {
          e.preventDefault();
          panTarget.dispatchEvent(mouseEvt('mousemove', e.touches[0]));
        } else if (e.touches.length === 2) {
          e.preventDefault();
          if (lastDist === null) return;
          var newDist = dist(e.touches);
          var ratio   = newDist / lastDist;
          lastDist    = newDist;
          if (Math.abs(ratio - 1) < 0.005) return;
          pendingDelta = -(ratio - 1) * 80;
          pendingCx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
          pendingCy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
          if (!rafPending) {
            rafPending = true;
            requestAnimationFrame(fireWheel);
          }
        }
      }, { passive: false });

      document.addEventListener('touchend', function(e) {
        if (e.touches.length === 0 && panning && panTarget) {
          panTarget.dispatchEvent(mouseEvt('mouseup', e.changedTouches[0]));
          panning = false; panTarget = null;
        }
        if (e.touches.length < 2) lastDist = null;
      }, { passive: true });

      // ── Helpers ────────────────────────────────────────────────────
      function dist(t) {
        var dx = t[0].clientX - t[1].clientX;
        var dy = t[0].clientY - t[1].clientY;
        return Math.sqrt(dx * dx + dy * dy);
      }

      function fireWheel() {
        rafPending = false;
        var target = document.elementFromPoint(pendingCx, pendingCy) || document.body;
        target.dispatchEvent(new WheelEvent('wheel', {
          bubbles: true, cancelable: true,
          clientX: pendingCx, clientY: pendingCy,
          deltaY: pendingDelta, deltaMode: 0,
        }));
      }
    })();
  ''';

  // ── Touch-to-mouse JS (Clues tab — Treasure V2 puzzle) ───────────────────
  // The puzzle solver uses a Canvas with mousedown/mousemove/mouseup listeners.
  // We translate touch events to mouse events in canvas pixel space.
  //
  // KEY: use (canvas.width / rect.width) as the scale factor.
  // rect is in viewport pixels (affected by CSS zoom).
  // canvas.width is in canvas logical pixels (never changes).
  // Their ratio converts any viewport offset to canvas pixel space exactly,
  // regardless of what CSS zoom level is currently applied.
  // This fixes both the coordinate offset AND the disappearing tile issues.
  static const String _touchDragJS = r'''
    (function() {
      if (window._touchMouseActive) return;
      window._touchMouseActive = true;

      function canvasMouseEvt(type, touch, canvas) {
        var rect = canvas.getBoundingClientRect();
        // Scale factor: canvas logical pixels / rendered viewport pixels
        var sx = canvas.width  / rect.width;
        var sy = canvas.height / rect.height;
        // Convert touch viewport coords to canvas pixel coords,
        // then express as clientX so getMouseTile() computes correctly:
        //   getMouseTile: x = (e.clientX - rect.left) / tileSize
        //   mouseX:       e.clientX - rect.left  (for floating tile draw)
        // Both expect e.clientX - rect.left to be in canvas pixel space.
        var cx = rect.left + (touch.clientX - rect.left) * sx;
        var cy = rect.top  + (touch.clientY - rect.top)  * sy;
        return new MouseEvent(type, {
          bubbles: true, cancelable: true, view: window,
          clientX: cx, clientY: cy,
          screenX: touch.screenX, screenY: touch.screenY,
        });
      }

      function attachToCanvases() {
        document.querySelectorAll('canvas').forEach(function(canvas) {
          if (canvas._touchMouseBound) return;
          canvas._touchMouseBound = true;

          canvas.addEventListener('touchstart', function(e) {
            e.preventDefault();
            canvas.dispatchEvent(canvasMouseEvt('mousedown', e.touches[0], canvas));
          }, { passive: false });

          canvas.addEventListener('touchmove', function(e) {
            e.preventDefault();
            canvas.dispatchEvent(canvasMouseEvt('mousemove', e.touches[0], canvas));
          }, { passive: false });

          canvas.addEventListener('touchend', function(e) {
            e.preventDefault();
            canvas.dispatchEvent(canvasMouseEvt('mouseup', e.changedTouches[0], canvas));
          }, { passive: false });
        });
      }

      attachToCanvases();
      setTimeout(attachToCanvases, 800);
      setTimeout(attachToCanvases, 2000);
    })();
  ''';

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

    final afkThreshold  = prefs.getInt('afk_threshold')  ?? 10;
    final afkSound      = prefs.getBool('afk_sound')      ?? true;
    final afkVibration  = prefs.getBool('afk_vibration')  ?? true;

    if (mounted) {
      setState(() {
        if (url != null && label != null) {
          _currentUrl        = url;
          _currentWorldLabel = label;
        }
        // Load per-tab zoom values (keeps defaults if not yet saved)
        for (int i = 0; i < _tabZoomKeys.length; i++) {
          _tabZoom[i] = prefs.getDouble(_tabZoomKeys[i]) ?? _tabZoom[i];
        }
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
        currentZoom   : _currentZoom,
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

  void _onZoomChanged(double zoom) async {
    setState(() => _tabZoom[_activeTab] = zoom);
    _controllerForTab(_activeTab)?.evaluateJavascript(source: _zoomJS(zoom));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_tabZoomKeys[_activeTab], zoom);
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

  // ── Tab helpers ───────────────────────────────────────────────────────────

  InAppWebViewController? _controllerForTab(int tab) {
    switch (tab) {
      case 0: return _webViewController;
      case 1: return _coordsController;
      case 2: return _cluesController;
      case 3: return _mapController;
      case 4: return _marketsController;
      case 5: return _questsController;
      case 6: return _calcsController;
      case 7: return _lclabController;
      default: return null;
    }
  }

  void _switchTab(int index) {
    setState(() => _activeTab = index);
    // Re-apply saved zoom after frame so the WebView has had a chance to settle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerForTab(index)
          ?.evaluateJavascript(source: _zoomJS(_tabZoom[index]));
    });
    _registerFeatures();
  }

  // ── AFK Timer ─────────────────────────────────────────────────────────────

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

    if (_afkSettings.soundEnabled) {
      try {
        await _audioPlayer.resume();
        debugPrint('AFK sound resume() OK');
      } catch (e) {
        debugPrint('AFK sound error: $e');
        try {
          await _audioPlayer.play(AssetSource('sounds/afk_alert.mp3'));
          debugPrint('AFK sound fallback play() OK');
        } catch (e2) {
          debugPrint('AFK sound fallback error: $e2');
        }
      }
    }

    if (_afkSettings.vibrationEnabled) {
      try {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          await Vibration.vibrate(
            pattern    : [0, 400, 150, 400, 150, 400],
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
        await ctrl.evaluateJavascript(source: _zoomJS(_tabZoom[0]));
        if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
        return;
      }
    }
    await ctrl.evaluateJavascript(source: _zoomJS(_tabZoom[0]));
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

          // ── All tabs always mounted — game runs in background ──────
          IndexedStack(
            index: _activeTab,
            children: [

              // ── Tab 0: Game ────────────────────────────────────────
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
                  onWebViewCreated: (c) => _webViewController = c,
                  onLoadStart: (c, url) {
                    _loadGen++;
                    c.evaluateJavascript(source: 'window._lkReady = false;');
                    if (mounted) setState(() => _pageLoading = true);
                  },
                  onLoadStop: (c, url) async {
                    final gen = _loadGen;
                    await _applyFullscreen(c, gen);
                  },
                  onReceivedError: (c, request, error) {
                    debugPrint('WebView error: ${error.description}');
                    if (mounted) setState(() => _pageLoading = false);
                  },
                ),
              ),

              // ── Tab 1: Coordinates ─────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://tools.losthq.rs/cluecoordinator/')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : false,  // disable native pinch — our JS handles it
                  builtInZoomControls       : false,
                  displayZoomControls       : false,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _coordsController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _coordsLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _coordsLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[1]));
                  c.evaluateJavascript(source: _pinchToWheelJS);
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _coordsLoading = false);
                },
              ),

              // ── Tab 2: Clues ───────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://razgals.github.io/Treasure-V2/')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _cluesController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _cluesLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _cluesLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[2]));
                  c.evaluateJavascript(source: _touchDragJS);
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _cluesLoading = false);
                },
              ),

              // ── Tab 3: Map ─────────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://2004.lostcity.rs/worldmap')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _mapController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _mapLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _mapLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[3]));
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _mapLoading = false);
                },
              ),

              // ── Tab 4: Markets ─────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://markets.lostcity.rs')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _marketsController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _marketsLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _marketsLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[4]));
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _marketsLoading = false);
                },
              ),

              // ── Tab 5: Quests ──────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://2004.losthq.rs/?p=questguides')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _questsController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _questsLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _questsLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[5]));
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _questsLoading = false);
                },
              ),

              // ── Tab 6: Calcs ───────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://2004.losthq.rs/?p=calculators')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _calcsController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _calcsLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _calcsLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[6]));
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _calcsLoading = false);
                },
              ),

              // ── Tab 7: LC Lab ──────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                    url: WebUri('https://www.lostcitylabs.com')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (c) => _lclabController = c,
                onLoadStart: (c, _) {
                  if (mounted) setState(() => _lclabLoading = true);
                },
                onLoadStop: (c, _) {
                  if (mounted) setState(() => _lclabLoading = false);
                  c.evaluateJavascript(source: _zoomJS(_tabZoom[7]));
                },
                onReceivedError: (c, _, __) {
                  if (mounted) setState(() => _lclabLoading = false);
                },
              ),
            ],
          ),

          // ── Game loading overlay (tab 0 only) ─────────────────────
          if (_pageLoading && _activeTab == 0)
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

          // ── Screenshot flash overlay ───────────────────────────────
          if (_screenshotFlash)
            IgnorePointer(child: Container(color: Colors.white.withOpacity(0.5))),

          // ── Left column: hamburger → toggle → tabs ─────────────────
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Hamburger + ping on the same row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        color: const Color(0xAA000000),
                        height: 34,
                        child: Row(
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
                      ),
                    ],
                  ),

                  // Toggle chevron — collapses / expands tab list
                  GestureDetector(
                    onTap: () => setState(() => _tabsVisible = !_tabsVisible),
                    child: Container(
                      width: 34, height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xAA000000),
                        border: Border(
                          left  : BorderSide(color: Color(0x338B6914)),
                          right : BorderSide(color: Color(0x338B6914)),
                          bottom: BorderSide(color: Color(0x338B6914)),
                        ),
                      ),
                      child: Center(
                        child: AnimatedRotation(
                          turns: _tabsVisible ? 0.0 : 0.5,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Color(0xFF8B6914),
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Animated tab list
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topLeft,
                    child: _tabsVisible
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 2),

                                  _TabChip(
                                    label : _currentWorldLabel,
                                    icon  : Icons.sports_esports,
                                    active: _activeTab == 0,
                                    onTap : () => _switchTab(0),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/coordinates.png',
                                    active : _activeTab == 1,
                                    loading: _coordsLoading && _activeTab == 1,
                                    onTap  : () => _switchTab(1),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/cluehelp.png',
                                    active : _activeTab == 2,
                                    loading: _cluesLoading && _activeTab == 2,
                                    onTap  : () => _switchTab(2),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/worldmap.png',
                                    active : _activeTab == 3,
                                    loading: _mapLoading && _activeTab == 3,
                                    onTap  : () => _switchTab(3),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/market.png',
                                    active : _activeTab == 4,
                                    loading: _marketsLoading && _activeTab == 4,
                                    onTap  : () => _switchTab(4),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/quests.png',
                                    active : _activeTab == 5,
                                    loading: _questsLoading && _activeTab == 5,
                                    onTap  : () => _switchTab(5),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/skillscalculator.png',
                                    active : _activeTab == 6,
                                    loading: _calcsLoading && _activeTab == 6,
                                    onTap  : () => _switchTab(6),
                                  ),
                                  const SizedBox(height: 2),
                                  _IconTabBtn(
                                    asset  : 'assets/widgets/lcl.png',
                                    active : _activeTab == 7,
                                    loading: _lclabLoading && _activeTab == 7,
                                    onTap  : () => _switchTab(7),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // ── Right column: toggle → screenshot → mute → AFK badge ──
          Positioned(
            top: 0, right: 6,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Toggle chevron (mirrors left side)
                  GestureDetector(
                    onTap: () => setState(() => _rightVisible = !_rightVisible),
                    child: Container(
                      width: 34, height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xAA000000),
                        border: Border(
                          left  : BorderSide(color: Color(0x338B6914)),
                          right : BorderSide(color: Color(0x338B6914)),
                          bottom: BorderSide(color: Color(0x338B6914)),
                        ),
                      ),
                      child: Center(
                        child: AnimatedRotation(
                          turns: _rightVisible ? 0.0 : 0.5,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Color(0xFF8B6914),
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Animated button list
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topRight,
                    child: _rightVisible
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 2),

                              // Screenshot
                              GestureDetector(
                                onTap: _takeScreenshot,
                                child: _FloatButton(
                                  child: Image.asset(
                                    'assets/capture.png',
                                    width: 20, height: 20,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.camera_alt,
                                        color: Color(0xFFC8A450), size: 18),
                                  ),
                                ),
                              ),

                              // AFK badge (game tab only, when enabled)
                              if (_afkSettings.enabled && _activeTab == 0) ...[
                                const SizedBox(height: 2),
                                _AfkBadge(
                                  remaining       : _afkRemaining,
                                  thresholdSeconds: _afkSettings.thresholdSeconds,
                                ),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
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
    if (remaining < 0)                       return const Color(0xFF4499FF);
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

// ── Tab chip ──────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final bool      active;
  final bool      loading;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xCC000000) : const Color(0x88000000),
          border: Border.all(
            color: active ? const Color(0xFFCC0000) : const Color(0x44888888),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(
                        color: Color(0xFFC8A450), strokeWidth: 1.5),
                  )
                : Icon(icon,
                    size : 11,
                    color: active
                        ? const Color(0xFFC8A450)
                        : const Color(0xFF666666)),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize  : 10,
                  color     : active
                      ? const Color(0xFFC8A450)
                      : const Color(0xFF666666),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon-only tab button (34×34, asset image) ─────────────────────────────────

class _IconTabBtn extends StatelessWidget {
  final String       asset;
  final bool         active;
  final bool         loading;
  final VoidCallback onTap;

  const _IconTabBtn({
    required this.asset,
    required this.active,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: active ? const Color(0xCC000000) : const Color(0x88000000),
          border: Border.all(
            color: active ? const Color(0xFFCC0000) : const Color(0x44888888),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      color: Color(0xFFC8A450), strokeWidth: 1.5),
                )
              : Image.asset(
                  asset,
                  width : 22,
                  height: 22,
                  // Dim inactive, full brightness active
                  color : active ? null : const Color(0x88FFFFFF),
                  colorBlendMode: BlendMode.modulate,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.web,
                    size : 16,
                    color: active
                        ? const Color(0xFFC8A450)
                        : const Color(0xFF666666),
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Float button ──────────────────────────────────────────────────────────────

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
