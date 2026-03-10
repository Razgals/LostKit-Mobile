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
    final double panelWidth = _activeFeature != null
        ? MediaQuery.of(context).size.width * 0.52
        : _menuWidth(context);

    return Drawer(
      width: panelWidth,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF0D0D0D),
                border:
                    Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeFeature != null) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _activeFeature = null),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFFCC0000), size: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _activeFeature!.title.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'RuneScape',
                        color: Color(0xFFCC0000),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'MENU',
                      style: TextStyle(
                        fontFamily: 'RuneScape',
                        color: Color(0xFFCC0000),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close,
                          color: Color(0xFF555555), size: 15),
                    ),
                  ],
                ],
              ),
            ),

            // Content
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

  double _menuWidth(BuildContext context) {
    if (FeatureRegistry.features.isEmpty) return 150.0;
    double maxW = 0;
    for (final f in FeatureRegistry.features) {
      final tp = TextPainter(
        text: TextSpan(
            text: f.title,
            style: const TextStyle(fontSize: 13, fontFamily: 'RuneScape')),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > maxW) maxW = tp.width;
    }
    // icon(18) + gap(10) + text + chevron(16) + padding(28)
    return (18 + 10 + maxW + 16 + 28).clamp(140.0, 230.0);
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
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(feature.icon,
                    color: const Color(0xFFCC0000), size: 16),
                const SizedBox(width: 10),
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontFamily: 'RuneScape',
                    color: Color(0xFFE0D5A0),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
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
