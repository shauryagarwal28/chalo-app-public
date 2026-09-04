import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'report_incident_screen.dart';
import 'ride_day_screen.dart';

/// Mock roster for this screen's "Report an Incident" entry point.
/// `ride_chat_screen.dart` currently carries no real rider/organiser data
/// (only `rideName` is passed in) and has no concept of which role the
/// current viewer holds — same mock-data-per-screen convention already
/// used elsewhere in this build (e.g. `ride_day_screen.dart`'s own
/// hardcoded `_riders`). The organiser name matches this screen's existing
/// mock chat sender ("Arjun Mehta"); rider names match `ride_day_screen.dart`'s
/// mock roster for consistency.
const String _kMockOrganiserName = 'Arjun Mehta';
const List<String> _kMockRiderNames = ['Vikram Singh', 'Neha Kapoor', 'Suresh Kumar'];

enum _MessageType { system, organiser, rider, me }

class _ChatMessage {
  final _MessageType type;
  final String sender;
  final String text;

  const _ChatMessage({required this.type, required this.sender, required this.text});
}

class RideChatScreen extends StatefulWidget {
  final String rideName;

  const RideChatScreen({super.key, required this.rideName});

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  final _controller = TextEditingController();
  final List<_ChatMessage> _messages = const [
    _ChatMessage(type: _MessageType.system, sender: '', text: 'Vikram Singh joined the ride'),
    _ChatMessage(type: _MessageType.organiser, sender: 'Arjun Mehta', text: 'Meeting at Hebbal Flyover, 6:30 AM sharp. Fuel up before you arrive.'),
    _ChatMessage(type: _MessageType.rider, sender: 'Vikram Singh', text: 'Got it, see you all there!'),
  ].toList();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(type: _MessageType.me, sender: 'You', text: text));
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(widget.rideName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportIncidentScreen(
                          rideName: widget.rideName,
                          riders: _kMockRiderNames,
                          organiserName: _kMockOrganiserName,
                        ),
                      ),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.flag_outlined, color: ChaloColors.textSecondary, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => RideDayScreen(rideName: widget.rideName)),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.event_outlined, color: ChaloColors.textSecondary, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  if (m.type == _MessageType.system) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(m.text, style: const TextStyle(fontSize: 11, color: ChaloColors.textDisabled, fontStyle: FontStyle.italic)),
                      ),
                    );
                  }
                  final isMe = m.type == _MessageType.me;
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      child: MetallicCard(
                        borderRadius: BorderRadius.circular(14),
                        hasOrangeAccent: isMe,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Row(
                                  children: [
                                    Text(m.sender, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary)),
                                    if (m.type == _MessageType.organiser) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(color: ChaloColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('ORGANISER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ChaloColors.primary)),
                                      ),
                                    ],
                                  ],
                                ),
                              if (!isMe) const SizedBox(height: 4),
                              Text(m.text, style: const TextStyle(fontSize: 14, color: ChaloColors.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: MetallicCard(
                        borderRadius: BorderRadius.circular(24),
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(color: ChaloColors.textDisabled),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: ChaloColors.primary),
                        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
