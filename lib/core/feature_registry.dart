import 'package:flutter/material.dart';

abstract class AppFeature {
  String get title;
  IconData get icon;

  // Optional PNG asset path — if set, the menu uses this instead of icon
  // e.g. 'assets/hiscores.png' or 'assets/worldswitch.png'
  String? get iconAsset => null;

  Widget buildPanel(BuildContext context, VoidCallback onClose);
}

class FeatureRegistry {
  static final List<AppFeature> features = [];

  static void registerAll(List<AppFeature> list) {
    features.addAll(list);
  }
}
