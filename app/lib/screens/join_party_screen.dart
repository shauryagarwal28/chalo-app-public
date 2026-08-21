import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_exception.dart';
import '../services/party_service.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'waiting_room_screen.dart';

class _RecentParty {
  final String rideName;
  final String code;
  final String meetPoint;
  final String lastActive;
  final String hostName;

  const _RecentParty({
    required this.rideName,
    required this.code,
    required this.meetPoint,
    required this.lastActive,
    required this.hostName,
  });
}

const _recentParties = [
  _RecentParty(rideName: 'Lonavala Sunday Run', code: 'MK4P9T', meetPoint: 'Bandra Toll Plaza', lastActive: 'Yesterday', hostName: 'Rahul'),
  _RecentParty(rideName: 'Weekend Warriors', code: 'XJ2R7L', meetPoint: 'Powai Lake', lastActive: '3 days ago', hostName: 'Priya'),
  _RecentParty(rideName: 'Airport Run', code: 'QW8N3B', meetPoint: 'Andheri Subway', lastActive: '1 week ago', hostName: 'Arjun'),
];

class JoinPartyScreen extends StatefulWidget {
  const JoinPartyScreen({super.key});

  @override
  State<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends State<JoinPartyScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isComplete = false;
  bool _isJoining = false;

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _onCharEntered(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    final filled = _controllers.every((c) => c.text.isNotEmpty);
    setState(() => _isComplete = filled);
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() => _isComplete = false);
    }
  }

  void _fillCode(String code) {
    for (var i = 0; i < 6; i++) {
      _controllers[i].text = i < code.length ? code[i] : '';
    }
    setState(() => _isComplete = code.length == 6);
  }

  /// Real backend call — POST /parties/join, per api-design.md. Replaces
  /// the old `_recentParties` lookup-or-generic-placeholder logic: every
  /// code now either resolves to a real party (Redis-backed) or fails with
  /// a real, typed error (404 PARTY_NOT_FOUND / 409 PARTY_FULL) shown
  /// inline instead of silently faking a party. `_recentParties` below is
  /// still shown as a UI convenience (tap-to-fill-code), but no longer
  /// supplies any ride details itself — those always come from the real
  /// join response now.
  Future<void> _joinWithCode(String code) async {
    if (_isJoining) return;
    setState(() => _isJoining = true);

    try {
      final result = await PartyService.joinParty(code);
      if (!mounted) return;
      setState(() => _isJoining = false);

      final dateParts = result.date.split('-').map(int.parse).toList();
      final timeParts = result.time.split(':').map(int.parse).toList();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingRoomScreen(
            partyId: result.partyId,
            rideName: result.rideName,
            meetPoint: result.meetPoint,
            date: DateTime(dateParts[0], dateParts[1], dateParts[2]),
            time: TimeOfDay(hour: timeParts[0], minute: timeParts[1]),
            maxRiders: result.maxRiders,
            partyCode: code,
            hostName: result.hostName,
            initialMemberNames: {
              for (final m in result.members) m.userId: m.name,
            },
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.code == 'PARTY_NOT_FOUND'
            ? 'No party found with code $code'
            : e.code == 'PARTY_FULL'
                ? 'That party is already full'
                : 'Could not join party: ${e.message}')),
      );
    }
  }

  Future<void> _joinViaLink() async {
    final controller = TextEditingController();
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          decoration: const BoxDecoration(
            color: ChaloColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste Invite Link',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
              ),
              const SizedBox(height: 16),
              MetallicCard(
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'https://chalo.app/join/ABC123',
                    hintStyle: TextStyle(color: ChaloColors.textDisabled, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final extracted = _extractCode(controller.text);
                  Navigator.pop(context, extracted);
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );

    if (code != null && code.length == 6) {
      _fillCode(code);
      await _joinWithCode(code);
    } else if (code != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That doesn't look like a valid party link")),
        );
      }
    }
  }

  String? _extractCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split('/').where((s) => s.isNotEmpty).toList();
    final segment = parts.isNotEmpty ? parts.last : trimmed;
    final cleaned = segment.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.5, -1.5),
                    end: Alignment(1.5, 1.5),
                    colors: [Color(0xFF2A3540), Color(0xFF1A1F23), Color(0xFF1E2428), Color(0xFF1A1F23)],
                    stops: [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: MetallicCard(
                          borderRadius: BorderRadius.circular(12),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Join Party',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        const Text(
                          'Enter Party Code',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textSecondary, letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 12),

                        _CodeBoxes(
                          controllers: _controllers,
                          focusNodes: _focusNodes,
                          onChanged: _onCharEntered,
                          onBackspace: _onBackspace,
                        ),
                        const SizedBox(height: 24),

                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _isComplete
                                ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 4))]
                                : [],
                          ),
                          child: ElevatedButton(
                            onPressed: _isComplete && !_isJoining
                                ? () => _joinWithCode(_controllers.map((c) => c.text).join())
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isComplete ? ChaloColors.primary : ChaloColors.bgCard,
                              disabledBackgroundColor: ChaloColors.bgCard,
                            ),
                            child: _isJoining
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    'Join Party',
                                    style: TextStyle(color: _isComplete ? Colors.white : ChaloColors.textDisabled),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Divider
                        Row(
                          children: [
                            Expanded(child: Container(height: 1, color: ChaloColors.borderDim)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ChaloColors.textDisabled)),
                            ),
                            Expanded(child: Container(height: 1, color: ChaloColors.borderDim)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        OutlinedButton(
                          onPressed: _joinViaLink,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link, size: 18, color: ChaloColors.textPrimary),
                              SizedBox(width: 8),
                              Text('Join via Link'),
                            ],
                          ),
                        ),

                        if (_recentParties.isNotEmpty) ...[
                          const SizedBox(height: 36),
                          const Text(
                            'RECENT PARTIES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 12),
                          ..._recentParties.take(3).map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _RecentPartyTile(
                                    party: p,
                                    onTap: () {
                                      _fillCode(p.code);
                                      _joinWithCode(p.code);
                                    },
                                  ),
                                ),
                              ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseAlphanumericFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int, String) onChanged;
  final void Function(int) onBackspace;

  const _CodeBoxes({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => _CodeBox(
        controller: controllers[i],
        focusNode: focusNodes[i],
        onChanged: (v) => onChanged(i, v),
        onBackspace: () => onBackspace(i),
      )),
    );
  }
}

class _CodeBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  State<_CodeBox> createState() => _CodeBoxState();
}

class _CodeBoxState extends State<_CodeBox> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() => setState(() => _isFocused = widget.focusNode.hasFocus));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: MetallicCard(
        borderRadius: BorderRadius.circular(12),
        hasOrangeAccent: _isFocused,
        shadows: _isFocused
            ? [
                BoxShadow(color: ChaloColors.primary.withOpacity(0.3), blurRadius: 12),
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3)),
              ]
            : null,
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
              widget.onBackspace();
            }
          },
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            textAlign: TextAlign.center,
            maxLength: 1,
            inputFormatters: [_UpperCaseAlphanumericFormatter()],
            style: const TextStyle(
              color: ChaloColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

class _RecentPartyTile extends StatelessWidget {
  final _RecentParty party;
  final VoidCallback onTap;

  const _RecentPartyTile({required this.party, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MetallicCard(
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ChaloColors.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ChaloColors.borderShine.withOpacity(0.5)),
                ),
                child: const Icon(Icons.two_wheeler, size: 20, color: ChaloColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.rideName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${party.code} · ${party.lastActive}',
                      style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: ChaloColors.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
