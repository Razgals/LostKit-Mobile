import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/feature_registry.dart';

const _skillMap = {
  0:  _Skill('Overall',     'stats.webp'),
  1:  _Skill('Attack',      'attack.webp'),
  2:  _Skill('Defence',     'defence.webp'),
  3:  _Skill('Strength',    'strength.webp'),
  4:  _Skill('Hitpoints',   'hitpoints.webp'),
  5:  _Skill('Ranged',      'ranged.webp'),
  6:  _Skill('Prayer',      'prayer.webp'),
  7:  _Skill('Magic',       'magic.webp'),
  8:  _Skill('Cooking',     'cooking.webp'),
  9:  _Skill('Woodcutting', 'woodcutting.webp'),
  10: _Skill('Fletching',   'fletching.webp'),
  11: _Skill('Fishing',     'fishing.webp'),
  12: _Skill('Firemaking',  'firemaking.webp'),
  13: _Skill('Crafting',    'crafting.webp'),
  14: _Skill('Smithing',    'smithing.webp'),
  15: _Skill('Mining',      'mining.webp'),
  16: _Skill('Herblore',    'herblore.webp'),
  17: _Skill('Agility',     'agility.webp'),
  18: _Skill('Thieving',    'thieving.webp'),
  21: _Skill('Runecraft',   'runecraft.webp'),
};

const _skillOrder = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,21];

class _Skill {
  final String name;
  final String icon;
  const _Skill(this.name, this.icon);
}

class HiscoresFeature extends AppFeature {
  @override
  String get title => 'Hiscores';
  @override
  IconData get icon => Icons.leaderboard;
  @override
  Widget buildPanel(BuildContext context, VoidCallback onClose) =>
      const HiscoresPanel();
}

class HiscoresPanel extends StatefulWidget {
  const HiscoresPanel({super.key});
  @override
  State<HiscoresPanel> createState() => _HiscoresPanelState();
}

class _HiscoresPanelState extends State<HiscoresPanel> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _stats = [];
  bool _loading = false;
  bool _error = false;
  bool _searched = false;
  String _playerName = '';

  Future<void> _lookup() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true; _error = false;
      _searched = true; _playerName = name; _stats = [];
    });
    try {
      final response = await http
          .get(Uri.parse(
              'https://2004.lostcity.rs/api/hiscores/player/${Uri.encodeComponent(name)}'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() { _stats = data.cast<Map<String, dynamic>>(); _loading = false; });
      } else { throw Exception(); }
    } catch (_) {
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                      color: Color(0xFFE0D5A0),
                      fontSize: 13,
                      fontFamily: 'RuneScape'),
                  decoration: const InputDecoration(
                    hintText: 'Username',
                    hintStyle: TextStyle(
                        color: Color(0xFF555555), fontFamily: 'RuneScape'),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: Color(0xFF333333))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: Color(0xFF333333))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: Color(0xFFCC0000))),
                  ),
                  onSubmitted: (_) => _lookup(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _lookup,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  color: const Color(0xFFCC0000),
                  child: const Text('Go',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'RuneScape',
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: !_searched
              ? const Center(
                  child: Text('Enter a username',
                      style: TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 12,
                          fontFamily: 'RuneScape')))
              : _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFCC0000)))
                  : _error
                      ? Center(
                          child: Text(
                            'Player "$_playerName" not found',
                            style: const TextStyle(
                                color: Color(0xFFFF4444),
                                fontSize: 12,
                                fontFamily: 'RuneScape'),
                            textAlign: TextAlign.center,
                          ))
                      : _buildStats(),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final statsMap = <int, Map<String, dynamic>>{};
    for (final s in _stats) { statsMap[s['type'] as int] = s; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Text(_playerName,
              style: const TextStyle(
                  color: Color(0xFFCC0000),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'RuneScape')),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: _skillOrder.length,
            itemBuilder: (ctx, i) {
              final type = _skillOrder[i];
              final stat = statsMap[type];
              final skill = _skillMap[type];
              if (stat == null || skill == null) return const SizedBox.shrink();
              final xp = ((stat['value'] as int) / 10).floor();
              return _StatRow(
                iconFile: skill.icon,
                name: skill.name,
                level: stat['level'] as int,
                xp: xp,
                rank: stat['rank'] as int,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String iconFile;
  final String name;
  final int level;
  final int xp;
  final int rank;
  const _StatRow({required this.iconFile, required this.name,
      required this.level, required this.xp, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/skillicons/$iconFile',
            width: 18, height: 18,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.circle, size: 14, color: Color(0xFF444444)),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 66,
            child: Text(name,
                style: const TextStyle(
                    color: Color(0xFFBBB090),
                    fontSize: 11,
                    fontFamily: 'RuneScape')),
          ),
          const Spacer(),
          _Chip('Lv', _fmt(level), const Color(0xFFE0D5A0)),
          const SizedBox(width: 6),
          _Chip('XP', _fmt(xp), const Color(0xFF88CC88)),
          const SizedBox(width: 6),
          _Chip('#', _fmt(rank), const Color(0xFF8888CC)),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Chip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Color(0xFF555555),
              fontSize: 9,
              fontFamily: 'RuneScape')),
      Text(value,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'RuneScape')),
    ]);
  }
}
