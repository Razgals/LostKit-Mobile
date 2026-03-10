import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/feature_registry.dart';

typedef OnZoomChanged = void Function(double zoom);

class ZoomFeature extends AppFeature {
  final OnZoomChanged onZoomChanged;
  final double currentZoom;

  ZoomFeature({required this.onZoomChanged, required this.currentZoom});

  @override
  String get title => 'Zoom';
  @override
  IconData get icon => Icons.zoom_in;
  @override
  String? get iconAsset => 'assets/zoom.png';

  @override
  Widget buildPanel(BuildContext context, VoidCallback onClose) {
    return ZoomPanel(
      currentZoom: currentZoom,
      onZoomChanged: onZoomChanged,
    );
  }
}

class ZoomPanel extends StatefulWidget {
  final double currentZoom;
  final OnZoomChanged onZoomChanged;
  const ZoomPanel({super.key, required this.currentZoom, required this.onZoomChanged});

  @override
  State<ZoomPanel> createState() => _ZoomPanelState();
}

class _ZoomPanelState extends State<ZoomPanel> {
  late double _zoom;

  static const double _min  = 0.50;
  static const double _max  = 2.00;
  static const double _step = 0.05;

  @override
  void initState() {
    super.initState();
    _zoom = widget.currentZoom;
  }

  Future<void> _setZoom(double zoom) async {
    final snapped = ((zoom.clamp(_min, _max)) / _step).round() * _step;
    setState(() => _zoom = snapped);
    widget.onZoomChanged(snapped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('game_zoom', snapped);
  }

  String get _zoomLabel => '${(_zoom * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    // FIX: SingleChildScrollView prevents the "bottom overflowed by N pixels"
    // stripe that appears when the Column's intrinsic height slightly exceeds
    // the Expanded slot given by SidePanelDrawer.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Game Zoom',
              style: TextStyle(
                fontFamily: 'RuneScape',
                color: Color(0xFFC8A450),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),

            // Big zoom % display
            Center(
              child: Text(
                _zoomLabel,
                style: const TextStyle(
                  fontFamily: 'RuneScape',
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // + / - buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ZoomBtn(
                  label: '−',
                  enabled: _zoom > _min,
                  onTap: () => _setZoom(_zoom - _step),
                ),
                const SizedBox(width: 16),
                _ZoomBtn(
                  label: '+',
                  enabled: _zoom < _max,
                  onTap: () => _setZoom(_zoom + _step),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preset quick-select
            const Text(
              'PRESETS',
              style: TextStyle(
                fontFamily: 'RuneScape',
                color: Color(0xFF555555),
                fontSize: 9,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [0.75, 1.00, 1.20, 1.50, 2.00].map((preset) {
                final active = (_zoom - preset).abs() < 0.01;
                return GestureDetector(
                  onTap: () => _setZoom(preset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFCC0000)
                          : const Color(0xFF2A2A2A),
                      border: Border.all(
                        color: active
                            ? const Color(0xFFCC0000)
                            : const Color(0xFF444444),
                      ),
                    ),
                    child: Text(
                      preset == 1.20 ? '120% ★' : '${(preset * 100).round()}%',
                      style: TextStyle(
                        fontFamily: 'RuneScape',
                        fontSize: 11,
                        color: active ? Colors.white : const Color(0xFF888888),
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Reset
            GestureDetector(
              onTap: () => _setZoom(1.0),
              child: const Text(
                'Reset to 100%',
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  color: Color(0xFF555555),
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF444444),
                ),
              ),
            ),

            // Bottom breathing room so the last item isn't flush against edge
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ZoomBtn({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFCC0000) : const Color(0xFF2A2A2A),
          border: Border.all(
            color: enabled ? const Color(0xFFCC0000) : const Color(0xFF333333),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: enabled ? Colors.white : const Color(0xFF444444),
            ),
          ),
        ),
      ),
    );
  }
}
