import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'kyc_pending_screen.dart';

class KycUploadScreen extends StatefulWidget {
  const KycUploadScreen({super.key});

  @override
  State<KycUploadScreen> createState() => _KycUploadScreenState();
}

class _KycUploadScreenState extends State<KycUploadScreen> {
  bool _dlUploaded = false;
  bool _aadhaarUploaded = false;

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
                      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.close, color: ChaloColors.textSecondary, size: 18)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Verify Your Identity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify your identity to unlock community rides.',
                      style: TextStyle(fontSize: 14, color: ChaloColors.textSecondary.withOpacity(0.9)),
                    ),
                    const SizedBox(height: 24),
                    _UploadCard(
                      label: 'Driving Licence',
                      sublabel: 'Required',
                      uploaded: _dlUploaded,
                      onTap: () => setState(() => _dlUploaded = true),
                    ),
                    const SizedBox(height: 14),
                    _UploadCard(
                      label: 'Aadhaar Card',
                      sublabel: 'Optional',
                      uploaded: _aadhaarUploaded,
                      onTap: () => setState(() => _aadhaarUploaded = true),
                    ),
                    const SizedBox(height: 24),
                    MetallicCard(
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 16, color: ChaloColors.textSecondary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Your documents are encrypted and deleted permanently after review.',
                                style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ElevatedButton(
                  onPressed: _dlUploaded
                      ? () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const KycPendingScreen()),
                          )
                      : null,
                  child: const Text('Submit for Review'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool uploaded;
  final VoidCallback onTap;

  const _UploadCard({required this.label, required this.sublabel, required this.uploaded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MetallicCard(
        borderRadius: BorderRadius.circular(16),
        hasOrangeAccent: uploaded,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                uploaded ? Icons.check_circle : Icons.upload_file_outlined,
                color: uploaded ? Colors.greenAccent : ChaloColors.primary,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(uploaded ? 'Uploaded' : sublabel, style: TextStyle(color: uploaded ? Colors.greenAccent : ChaloColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (!uploaded) const Icon(Icons.camera_alt_outlined, color: ChaloColors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
