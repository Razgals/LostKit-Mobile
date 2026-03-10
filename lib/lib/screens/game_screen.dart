import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/feature_registry.dart';
import '../features/world_switcher/world_switcher_feature.dart';
import '../features/hiscores/hiscores_feature.dart';
import '../features/zoom/zoom_feature.dart';
import '../widgets/side_panel_drawer.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webViewController;

  String _currentUrl        = 'https://2004.lostcity.rs/client?world=1&detail=high&method=0';
  String _currentWorldLabel = 'W1 HD';
  bool   _pageLoading       = true;
  bool   _screenshotFlash   = false;
  int    _loadGen           = 0;
  double _zoomLevel         = 1.0; // restored from prefs on init

  // ── Fullscreen JS — pin iframe, hide header only ─────────────────────
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
        'overflow:hidden!important;background:#000!important;';
      document.documentElement.style.cssText =
        'margin:0!important;padding:0!important;overflow:hidden!important;';

      window._lkReady = true;
    })();
  ''';

  // ── Zoom JS — applies CSS zoom to the whole page ──────────────────────
  // CSS zoom on the root element scales everything including the iframe.
  static String _zoomJS(double zoom) => '''
    document.documentElement.style.setProperty('zoom', '$zoom', 'important');
  ''';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _registerFeatures();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final url   = prefs.getString('last_world_url');
    final label = prefs.getString('last_world_label');
    final zoom  = prefs.getDouble('game_zoom') ?? 1.0;
    if (mounted) {
      setState(() {
        if (url != null && label != null) {
          _currentUrl        = url;
          _currentWorldLabel = label;
        }
        _zoomLevel = zoom;
      });
    }
  }

  Future<void> _saveLastWorld(String url, String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_world_url',   url);
    await prefs.setString('last_world_label', label);
  }

  void _registerFeatures() {
    FeatureRegistry.features.clear();
    FeatureRegistry.registerAll([
      WorldSwitcherFeature(onWorldSelected: _onWorldSelected),
      HiscoresFeature(),
      ZoomFeature(
        currentZoom: _zoomLevel,
        onZoomChanged: _onZoomChanged,
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
    // Re-register so the zoom panel shows the updated value next open
    _registerFeatures();
  }

  void _openPanel() {
    _registerFeatures();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _applyFullscreen(InAppWebViewController ctrl, int gen) async {
    const pollInterval = Duration(milliseconds: 400);
    const maxAttempts  = 30;

    for (int i = 0; i < maxAttempts; i++) {
      if (!mounted || _loadGen != gen) return;

      await ctrl.evaluateJavascript(source: _fullscreenJS);
      await Future.delayed(pollInterval);

      if (!mounted || _loadGen != gen) return;

      final ready = await ctrl.evaluateJavascript(
          source: 'window._lkReady === true;');
      if (ready == true || ready == 'true') {
        // Apply saved zoom right after fullscreen is set
        await ctrl.evaluateJavascript(source: _zoomJS(_zoomLevel));
        if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
        return;
      }
    }

    await ctrl.evaluateJavascript(source: _zoomJS(_zoomLevel));
    if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
  }

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
                style: TextStyle(
                    fontFamily: 'RuneScape', fontSize: 12, color: Colors.white)),
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
                style: TextStyle(
                    fontFamily: 'RuneScape', fontSize: 12, color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawer: const SidePanelDrawer(),
      body: Stack(
        children: [
          // ── GAME WEBVIEW ────────────────────────────────────────────
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useHybridComposition: true,
              supportZoom: false,
              builtInZoomControls: false,
              displayZoomControls: false,
              horizontalScrollBarEnabled: false,
              verticalScrollBarEnabled: false,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 11; Mobile) LostHQClient/1.0',
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              _loadGen++;
              controller.evaluateJavascript(
                  source: 'window._lkReady = false;');
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

          // ── LOADING OVERLAY ─────────────────────────────────────────
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
                        style: TextStyle(
                          fontFamily: 'RuneScape',
                          color: Color(0xFFC8A450),
                          fontSize: 14,
                          letterSpacing: 1,
                        )),
                    const SizedBox(height: 8),
                    Text(_currentWorldLabel,
                        style: const TextStyle(
                          fontFamily: 'RuneScape',
                          color: Color(0xFF666666),
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
            ),

          // ── SCREENSHOT FLASH ────────────────────────────────────────
          if (_screenshotFlash)
            IgnorePointer(
              child: Container(color: Colors.white.withOpacity(0.5)),
            ),

          // ── MENU BUTTON top-left ─────────────────────────────────────
          Positioned(
            top: 6,
            left: 6,
            child: GestureDetector(
              onTap: _openPanel,
              child: _FloatButton(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (_) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      width: 16,
                      height: 2,
                      color: const Color(0xFFC8A450),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── WORLD LABEL ──────────────────────────────────────────────
          Positioned(
            top: 10,
            left: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              color: const Color(0xAA000000),
              child: Text(
                _currentWorldLabel,
                style: const TextStyle(
                  fontFamily: 'RuneScape',
                  color: Color(0xFFC8A450),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // ── SCREENSHOT BUTTON top-right ──────────────────────────────
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: _takeScreenshot,
              child: _FloatButton(
                child: Image.asset(
                  'assets/capture.png',
                  width: 20,
                  height: 20,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.camera_alt,
                    color: Color(0xFFC8A450),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatButton extends StatelessWidget {
  final Widget child;
  const _FloatButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xBB000000),
        border: Border.all(color: const Color(0x558B6914)),
      ),
      child: Center(child: child),
    );
  }
}
