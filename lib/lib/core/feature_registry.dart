import 'package:flutter/material.dart';

/// Base class for all app features/panels.
/// Add new features by extending this and registering in FeatureRegistry.
abstract class AppFeature {
  /// Display name shown in the side panel
  String get title;

  /// Icon shown in the side panel menu
  IconData get icon;

  /// The widget rendered when this feature is active
  Widget buildPanel(BuildContext context, VoidCallback onClose);
}

/// Central registry - register all features here.
/// To add a new feature: create a class extending AppFeature, then add it to [features].
class FeatureRegistry {
  static final List<AppFeature> features = [];

  static void register(AppFeature feature) {
    features.add(feature);
  }

  static void registerAll(List<AppFeature> featureList) {
    features.addAll(featureList);
  }
}
