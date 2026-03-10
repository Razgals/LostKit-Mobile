import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/feature_registry.dart';

// ── Settings data-class ───────────────────────────────────────────────────────

class AfkTimerSettings {
  final bool enabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final int thresholdSeconds; // alert fires when this many seconds remain
  final int durationSeconds;  // always 90 for now

  const AfkTimerSettings({
    this.enabled          = false,
    this.soundEnabled     = true,
    this.vibrationEnabled = true,
    this.thresholdSeconds = 10,
    this.durationSeconds  = 90,
  });

  AfkTimerSettings copyWith({
    bool? enabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    int?  thresholdSeconds,
    int?  durationSeconds,
  }) {
    return AfkTimerSettings(
      enabled          : enabled          ?? this.enabled,
      soundEnabled     : soundEnabled     ?? this.soundEnabled,
      vibrationEnabled : vibrationEnabled ?? this.vibrationEnabled,
      thresholdSeconds : thresholdSeconds ?? this.thresholdSeconds,
      durationSeconds  : durationSeconds  ?? this.durationSeconds,
    );
  }
}

// ── AppFeature registration ───────────────────────────────────────────────────

class AfkTimerFeature extends AppFeature {
  final AfkTimerSettings settings;
  final ValueChanged<AfkTimerSettings> onSettingsChanged;

  AfkTimerFeature({
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  String get title => 'AFK Timer';
  @override
  IconData get icon => Icons.timer_outlined;
  @override
  String? get iconAsset => 'assets/afktimer.png';

  @override
  Widget buildPanel(BuildContext context, VoidCallback onClose) {
    return AfkTimerPanel(
      settings          : settings,
      onSettingsChanged : onSettingsChanged,
    );
  }
}

// ── Panel widget ──────────────────────────────────────────────────────────────

class AfkTimerPanel extends StatefulWidget {
  final AfkTimerSettings settings;
  final ValueChanged<AfkTimerSettings> onSettingsChanged;

  const AfkTimerPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<AfkTimerPanel> createState() => _AfkTimerPanelState();
}

class _AfkTimerPanelState extends State<AfkTimerPanel> {
  late AfkTimerSettings _s;
  late TextEditingController _thresholdController;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _thresholdController = TextEditingController(text: '${_s.thresholdSeconds}');
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  void _update(AfkTimerSettings next) {
    setState(() => _s = next);
    widget.onSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Enable toggle ───────────────────────────────────────
            _SectionTitle('AFK TIMER'),
            const SizedBox(height: 8),
            _ToggleRow(
              label   : 'Enable',
              subLabel: 'Touch game screen to reset',
              value   : _s.enabled,
              onChanged: (v) => _update(_s.copyWith(enabled: v)),
            ),
            const SizedBox(height: 16),

            // ── Threshold ───────────────────────────────────────────
            _SectionTitle('ALERT THRESHOLD'),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Alert when ',
                  style: TextStyle(
                    fontFamily: 'RuneScape',
                    color: Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
                SizedBox(
                  width: 46,
                  height: 28,
                  child: TextField(
                    controller: _thresholdController,
                    enabled: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontFamily: 'RuneScape',
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: Color(0xFF444444)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: Color(0xFFCC0000)),
                      ),
                    ),
                    onChanged: (val) {
                      // Allow empty/partial input while typing — only commit
                      // a valid value so the timer logic never gets junk data.
                      final n = int.tryParse(val);
                      if (n != null && n >= 1 && n <= _s.durationSeconds - 1) {
                        _update(_s.copyWith(thresholdSeconds: n));
                      }
                    },
                    onEditingComplete: () {
                      // On keyboard "done": snap back to last valid value
                      // if the field was left empty or out of range.
                      final n = int.tryParse(_thresholdController.text);
                      if (n == null || n < 1 || n > _s.durationSeconds - 1) {
                        _thresholdController.text = '${_s.thresholdSeconds}';
                      }
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                const Text(
                  ' s remain',
                  style: TextStyle(
                    fontFamily: 'RuneScape',
                    color: Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Notifications ───────────────────────────────────────
            _SectionTitle('NOTIFICATIONS'),
            const SizedBox(height: 8),
            _ToggleRow(
              label    : 'Sound',
              subLabel : 'Short beep when threshold hit',
              value    : _s.soundEnabled,
              onChanged: (v) => _update(_s.copyWith(soundEnabled: v)),
            ),
            const SizedBox(height: 8),
            _ToggleRow(
              label    : 'Vibration',
              subLabel : 'Haptic pulse when threshold hit',
              value    : _s.vibrationEnabled,
              onChanged: (v) => _update(_s.copyWith(vibrationEnabled: v)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily  : 'RuneScape',
        color       : Color(0xFF555555),
        fontSize    : 9,
        letterSpacing: 2,
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subLabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          // Custom checkbox
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: value ? const Color(0xFFCC0000) : const Color(0xFF2A2A2A),
              border: Border.all(
                color: value ? const Color(0xFFCC0000) : const Color(0xFF444444),
              ),
            ),
            child: value
                ? const Icon(Icons.check, color: Colors.white, size: 12)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontFamily: 'RuneScape',
                      fontSize: 11,
                      color: value ? const Color(0xFFE0D5A0) : const Color(0xFF666666),
                    )),
                Text(subLabel,
                    style: const TextStyle(
                      fontFamily: 'RuneScape',
                      fontSize: 9,
                      color: Color(0xFF555555),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
