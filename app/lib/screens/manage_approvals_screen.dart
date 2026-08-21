import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import '../widgets/star_rating.dart';
import 'ride_chat_screen.dart';

class _MockRequest {
  final String name;
  final double rating;
  final int ridesCompleted;
  final bool isNewRider;
  final String joinPoint;
  final String requestedAt;

  const _MockRequest({
    required this.name,
    required this.rating,
    required this.ridesCompleted,
    required this.isNewRider,
    required this.joinPoint,
    required this.requestedAt,
  });
}

class ManageApprovalsScreen extends StatefulWidget {
  final String rideName;

  const ManageApprovalsScreen({super.key, this.rideName = 'Your Posted Ride'});

  @override
  State<ManageApprovalsScreen> createState() => _ManageApprovalsScreenState();
}

class _ManageApprovalsScreenState extends State<ManageApprovalsScreen> {
  final List<_MockRequest> _requests = const [
    _MockRequest(name: 'Vikram Singh', rating: 4.4, ridesCompleted: 6, isNewRider: false, joinPoint: 'Hebbal Flyover', requestedAt: '2h ago'),
    _MockRequest(name: 'Neha Kapoor', rating: 0, ridesCompleted: 0, isNewRider: true, joinPoint: 'Yelahanka Junction', requestedAt: '40m ago'),
  ];
  final Set<int> _resolved = {};

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Join Requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                        Text(widget.rideName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final r = _requests[i];
                  final isResolved = _resolved.contains(i);
                  return MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                              ),
                              if (r.isNewRider) const NewRiderBadge() else StarRatingDisplay(rating: r.rating, size: 13),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${r.ridesCompleted} public rides completed · joins at ${r.joinPoint}', style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                          const SizedBox(height: 4),
                          Text('Requested ${r.requestedAt}', style: const TextStyle(fontSize: 11, color: ChaloColors.textDisabled)),
                          const SizedBox(height: 14),
                          if (isResolved)
                            const Text('Resolved', style: TextStyle(fontSize: 13, color: ChaloColors.textSecondary))
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _resolved.add(i)),
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    child: const Text('Reject'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => setState(() => _resolved.add(i)),
                                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    child: const Text('Approve'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RideChatScreen(rideName: widget.rideName)),
                  ),
                  child: const Text('Open Ride Chat'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
