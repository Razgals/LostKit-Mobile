import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/feature_registry.dart';
import 'world_model.dart';

typedef OnWorldSelected = void Function(String url, String title);

class WorldSwitcherFeature extends AppFeature {
  final OnWorldSelected onWorldSelected;
  WorldSwitcherFeature({required this.onWorldSelected});

  @override
  String get title => 'World Switcher';
  @override
  IconData get icon => Icons.public;
  @override
  Widget buildPanel(BuildContext context, VoidCallback onClose) {
    return WorldSwitcherPanel(
      onWorldSelected: (url, title) {
        onWorldSelected(url, title);
        onClose();
      },
    );
  }
}

class WorldSwitcherPanel extends StatefulWidget {
  final OnWorldSelected onWorldSelected;
  const WorldSwitcherPanel({super.key, required this.onWorldSelected});

  @override
  State<WorldSwitcherPanel> createState() => _WorldSwitcherPanelState();
}

class _WorldSwitcherPanelState extends State<WorldSwitcherPanel> {
  List<World> _worlds = [];
  bool _loading = true;
  bool _error = false;
  bool _membersOnly = true;
  bool _highDetail = true;

  @override
  void initState() {
    super.initState();
    _loadWorlds();
  }

  Future<void> _loadWorlds() async {
    setState(() { _loading = true; _error = false; });
    try {
      final response = await http
          .get(Uri.parse('https://2004.losthq.rs/pages/api/worlds.php'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _worlds = data.map((j) => World.fromJson(j)).toList();
          _loading = false;
        });
        for (final world in _worlds) { _measureLatency(world); }
      } else { throw Exception(); }
    } catch (_) {
      setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _measureLatency(World world) async {
    try {
      final start = DateTime.now().millisecondsSinceEpoch;
      await http.head(Uri.parse(world.hd)).timeout(const Duration(seconds: 5));
      final lat = DateTime.now().millisecondsSinceEpoch - start;
      if (mounted) setState(() => world.latency = lat);
    } catch (_) {
      if (mounted) setState(() => world.latency = -1);
    }
  }

  List<World> get _filtered =>
      _worlds.where((w) => _membersOnly ? w.p2p : !w.p2p).toList();

  int get _totalPlayers =>
      _filtered.fold(0, (sum, w) => sum + w.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Controls row ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Free / Members row
              Row(
                children: [
                  _SquareBtn(
                    label: 'Free',
                    active: !_membersOnly,
                    onTap: () => setState(() => _membersOnly = false),
                  ),
                  const SizedBox(width: 4),
                  _SquareBtn(
                    label: 'Members',
                    active: _membersOnly,
                    onTap: () => setState(() => _membersOnly = true),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadWorlds,
                    child: const Icon(Icons.refresh,
                        color: Color(0xFFCC0000), size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // HD / LD row — separate line so nothing overlaps
              Row(
                children: [
                  const Text('Detail:',
                      style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontFamily: 'RuneScape')),
                  const SizedBox(width: 6),
                  _SquareBtn(
                    label: 'HD',
                    active: _highDetail,
                    onTap: () => setState(() => _highDetail = true),
                  ),
                  const SizedBox(width: 4),
                  _SquareBtn(
                    label: 'LD',
                    active: !_highDetail,
                    onTap: () => setState(() => _highDetail = false),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Total players
        if (!_loading && !_error)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Total: $_totalPlayers online',
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF666666),
                    fontFamily: 'RuneScape'),
              ),
            ),
          ),

        // World list
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFCC0000)))
              : _error
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFFF4444), size: 26),
                      const SizedBox(height: 8),
                      const Text('Failed to load worlds',
                          style: TextStyle(
                              color: Color(0xFFFF4444),
                              fontSize: 11,
                              fontFamily: 'RuneScape')),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _loadWorlds,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          color: const Color(0xFFCC0000),
                          child: const Text('Retry',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'RuneScape')),
                        ),
                      ),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final world = _filtered[i];
                        return _WorldTile(
                          world: world,
                          onTap: () => widget.onWorldSelected(
                            _highDetail ? world.hd : world.ld,
                            'W${world.id} ${_highDetail ? 'HD' : 'LD'}',
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// Square toggle button
class _SquareBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SquareBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFCC0000) : const Color(0xFF2A2A2A),
          border: Border.all(
              color: active
                  ? const Color(0xFFCC0000)
                  : const Color(0xFF444444)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'RuneScape',
            fontSize: 11,
            color: active ? Colors.white : const Color(0xFF888888),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _WorldTile extends StatelessWidget {
  final World world;
  final VoidCallback onTap;
  const _WorldTile({required this.world, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Text('W${world.id}',
                style: const TextStyle(
                    fontFamily: 'RuneScape',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE0D5A0),
                    fontSize: 12)),
            const SizedBox(width: 8),
            Text('${world.count}',
                style: const TextStyle(
                    fontFamily: 'RuneScape',
                    color: Color(0xFF888888),
                    fontSize: 11)),
            const Spacer(),
            Text(world.latencyLabel,
                style: TextStyle(
                    fontFamily: 'RuneScape',
                    color: world.latencyColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
