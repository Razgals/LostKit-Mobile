import 'package:flutter/material.dart';

class World {
  final int id;
  final int count;
  final bool p2p;
  final String hd;
  final String ld;
  int? latency; // ms, null = measuring

  World({
    required this.id,
    required this.count,
    required this.p2p,
    required this.hd,
    required this.ld,
    this.latency,
  });

  factory World.fromJson(Map<String, dynamic> json) {
    return World(
      id: json['world'] is int
          ? json['world']
          : int.tryParse(json['world'].toString()) ?? 0,
      count: json['count'] is int
          ? json['count']
          : int.tryParse(json['count'].toString()) ?? 0,
      p2p: json['p2p'] == true || json['p2p'] == 1 || json['p2p'] == '1',
      hd: json['hd'] ?? '',
      ld: json['ld'] ?? '',
    );
  }

  String get latencyLabel {
    if (latency == null) return 'measuring...';
    if (latency! < 0) return 'N/A';
    return '${latency}ms';
  }

  Color get latencyColor {
    if (latency == null) return const Color(0xFF888888);
    if (latency! < 0) return const Color(0xFF888888);
    if (latency! <= 50) return const Color(0xFF00FF00);
    if (latency! <= 80) return const Color(0xFFFFFF00);
    if (latency! <= 120) return const Color(0xFFFF8800);
    return const Color(0xFFFF0000);
  }
}
