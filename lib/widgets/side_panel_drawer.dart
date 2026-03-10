import 'package:flutter/material.dart';
import '../core/feature_registry.dart';

class SidePanelDrawer extends StatefulWidget {
  const SidePanelDrawer({super.key});

  @override
  State<SidePanelDrawer> createState() => _SidePanelDrawerState();
}

class _SidePanelDrawerState extends State<SidePanelDrawer> {
  AppFeature? _activeFeature;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: _activeFeature != null ? 260.0 : 170.0,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF0D0D0D),
                border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
              ),
              child: Row(
                children: [
                  if (_activeFeature != null) ...[
                    GestureDetector(
                      onTap: () => setState(() => _activeFeature = null),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFFCC0000), size: 13),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _activeFeature!.title.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'RuneScape',
                          color: Color(0xFFCC0000),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    const Text('MENU',
                        style: TextStyle(
                          fontFamily: 'RuneScape',
                          color: Color(0xFFC8A450),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        )),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close,
                          color: Color(0xFF555555), size: 14),
                    ),
                  ],
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────
            Expanded(
              child: _activeFeature != null
                  ? _activeFeature!.buildPanel(context, () {
                      Navigator.of(context).pop();
                    })
                  : _buildMenu(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: FeatureRegistry.features.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF222222), height: 1),
      itemBuilder: (ctx, i) {
        final feature = FeatureRegistry.features[i];
        return InkWell(
          onTap: () => setState(() => _activeFeature = feature),
          splashColor: const Color(0x22CC0000),
          highlightColor: const Color(0x11CC0000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            child: Row(
              children: [
                _FeatureIcon(feature: feature),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feature.title,
                    style: const TextStyle(
                      fontFamily: 'RuneScape',
                      color: Color(0xFFE0D5A0),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF444444), size: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  final AppFeature feature;
  const _FeatureIcon({required this.feature});

  @override
  Widget build(BuildContext context) {
    final asset = feature.iconAsset;
    if (asset != null) {
      // No color/tint — show the PNG exactly as designed
      return Image.asset(
        asset,
        width: 18,
        height: 18,
        errorBuilder: (_, __, ___) =>
            Icon(feature.icon, color: const Color(0xFFCC0000), size: 16),
      );
    }
    return Icon(feature.icon, color: const Color(0xFFCC0000), size: 16);
  }
}
