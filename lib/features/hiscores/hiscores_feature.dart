import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/feature_registry.dart';

const List<int> _xpTable = [
  0, 83, 174, 276, 388, 512, 650, 801, 969, 1154,
  1358, 1584, 1833, 2107, 2411, 2746, 3115, 3523, 3973, 4470,
  5018, 5624, 6291, 7028, 7842, 8740, 9730, 10824, 12031, 13363,
  14833, 16456, 18247, 20224, 22406, 24815, 27473, 30408, 33648, 37224,
  41171, 45529, 50339, 55649, 61512, 67983, 75127, 83014, 91721, 101333,
  111945, 123660, 136594, 150872, 166636, 184040, 203254, 224466, 247886, 273742,
  302288, 333804, 368599, 407015, 449428, 496254, 547953, 605032, 668051, 737627,
  814445, 899257, 992895, 1096278, 1210421, 1336443, 1475581, 1629200, 1798808, 1986068,
  2192818, 2421087, 2673114, 2951373, 3258594, 3597792, 3972294, 4385776, 4842295, 5346332,
  5902831, 6517253, 7195629, 7944614, 8771558, 9684577, 10692629, 11805606, 13034431,
];

double _xpProgress(int level, int xp) {
  if (level >= 99) return 1.0;
  if (level < 1) return 0.0;
  final curr = _xpTable[level - 1];
  final next = _xpTable[level];
  if (next <= curr) return 1.0;
  return ((xp - curr) / (next - curr)).clamp(0.0, 1.0);
}

int _xpToNext(int level, int xp) {
  if (level >= 99) return 0;
  return (_xpTable[level] - xp).clamp(0, 99999999);
}

Color _progressBg(double p) => Color.lerp(
      const Color(0xFF0D1F15),
      const Color(0xFF3A2800),
      p,
    )!;

Color _progressBorder(double p) => Color.lerp(
      const Color(0xFF2A2A2A),
      const Color(0xFF8B6914),
      p,
    )!;

class _Skill {
  final String name;
  final String icon;
  const _Skill(this.name, this.icon);
}

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

const _skillOrder = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 21];

class HiscoresFeature extends AppFeature {
  @override
  String get title => 'Hiscores';
  @override
  IconData get icon => Icons.leaderboard;
  @override
  String? get iconAsset => 'assets/hiscores.png';
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

  Future<void> _lookup() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _error = false;
      _searched = true;
      _stats = [];
    });
    try {
      final response = await http
          .get(Uri.parse(
              'https://2004.lostcity.rs/api/hiscores/player/${Uri.encodeComponent(name)}'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _stats = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        throw Exception();
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                      color: Color(0xFFE0D5A0),
                      fontSize: 12,
                      fontFamily: 'RuneScape'),
                  decoration: const InputDecoration(
                    hintText: 'Username',
                    hintStyle: TextStyle(
                        color: Color(0xFF555555), fontFamily: 'RuneScape'),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 7),
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
              const SizedBox(width: 5),
              GestureDetector(
                onTap: _lookup,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

        if (_searched && !_loading && !_error && _stats.isNotEmpty)
          Container(
            color: const Color(0xFF0A0A0A),
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
            child: Row(
              children: [
                const SizedBox(width: 21),
                const Expanded(
                  child: Text('Skill',
                      style: TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 9,
                          fontFamily: 'RuneScape')),
                ),
                _ColHeader('Lv'),
                _ColHeader('XP'),
                _ColHeader('#'),
                _ColHeader('%'),
              ],
            ),
          ),

        Expanded(
          child: !_searched
              ? const Center(
                  child: Text('Enter a username',
                      style: TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 11,
                          fontFamily: 'RuneScape')))
              : _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFCC0000)))
                  : _error
                      ? const Center(
                          child: Text(
                            'Player not found',
                            style: TextStyle(
                                color: Color(0xFFFF4444),
                                fontSize: 12,
                                fontFamily: 'RuneScape'),
                          ))
                      : _buildStats(),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final statsMap = <int, Map<String, dynamic>>{};
    for (final s in _stats) {
      statsMap[s['type'] as int] = s;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
          child: Text(
            _controller.text.trim(),
            style: const TextStyle(
                color: Color(0xFFCC0000),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'RuneScape'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _skillOrder.length,
            itemBuilder: (ctx, i) {
              final type = _skillOrder[i];
              final stat = statsMap[type];
              final skill = _skillMap[type];
              if (stat == null || skill == null) return const SizedBox.shrink();
              final level = stat['level'] as int;
              final xp = ((stat['value'] as int) / 10).floor();
              final rank = stat['rank'] as int;
              final isOverall = type == 0;
              final progress = isOverall ? 0.0 : _xpProgress(level, xp);
              final toNext = isOverall ? 0 : _xpToNext(level, xp);
              return _StatRow(
                iconFile: skill.icon,
                name: skill.name,
                level: level,
                xp: xp,
                rank: rank,
                progress: progress,
                toNext: toNext,
                isOverall: isOverall,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String label;
  const _ColHeader(this.label);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 38,
        child: Text(label,
            textAlign: TextAlign.right,
            style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 9,
                fontFamily: 'RuneScape')),
      );
}

class _StatRow extends StatelessWidget {
  final String iconFile;
  final String name;
  final int level;
  final int xp;
  final int rank;
  final double progress;
  final int toNext;
  final bool isOverall;

  const _StatRow({
    required this.iconFile,
    required this.name,
    required this.level,
    required this.xp,
    required this.rank,
    required this.progress,
    required this.toNext,
    required this.isOverall,
  });

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String get _pctLabel {
    if (isOverall) return '—';
    if (level >= 99) return 'MAX';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = isOverall
        ? 'Overall'
        : level >= 99
            ? 'Max level!'
            : '${_fmt(toNext)} XP to level ${level + 1}';

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 3),
        decoration: BoxDecoration(
          color: isOverall ? const Color(0xFF1A1A1A) : _progressBg(progress),
          border: Border.all(
            color: isOverall
                ? const Color(0xFF2A2A2A)
                : _progressBorder(progress),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            if (!isOverall)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    height: 2,
                    color: Color.lerp(
                      const Color(0xFF336644),
                      const Color(0xFFC8A450),
                      progress,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 7),
              child: Row(
                children: [
                  Image.asset(
                    'assets/skillicons/$iconFile',
                    width: 14,
                    height: 14,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 14),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: isOverall
                            ? const Color(0xFFC8A450)
                            : const Color(0xFFCCBB88),
                        fontSize: 11,
                        fontWeight: isOverall
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontFamily: 'RuneScape',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text('$level',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Color(0xFFE0D5A0),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'RuneScape')),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(_fmt(xp),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Color(0xFF88CC88),
                            fontSize: 11,
                            fontFamily: 'RuneScape')),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(_fmt(rank),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Color(0xFF8888CC),
                            fontSize: 11,
                            fontFamily: 'RuneScape')),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      _pctLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: isOverall
                            ? const Color(0xFF444444)
                            : Color.lerp(
                                const Color(0xFF557755),
                                const Color(0xFFC8A450),
                                progress,
                              ),
                        fontSize: 10,
                        fontFamily: 'RuneScape',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
