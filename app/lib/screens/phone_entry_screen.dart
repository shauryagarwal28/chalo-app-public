import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'otp_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _controller = TextEditingController();
  bool _isValid = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isValid = _controller.text.replaceAll(' ', '').length == 10;
        _errorMessage = null; // clear error when user edits
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_isValid) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final number = _controller.text;
    final e164Phone = '+91$number';

    try {
      // Real backend call — POST /auth/request-otp, per api-design.md.
      // The dev backend (NODE_ENV != 'production') hands the OTP straight
      // back as `debugOtp` instead of sending a real SMS; otp_screen.dart
      // uses that to auto-fill the boxes rather than requiring a human to
      // read a text message during testing.
      final result = await AuthService.requestOtp(e164Phone);
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: '+91 $number',
            e164Phone: e164Phone,
            debugOtp: result.debugOtp,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    }
  }

  void _showNotSetUp(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider sign-in isn\'t set up yet — use phone number for now')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Static background, painted as a sibling of the keyboard-resizing
          // content below rather than as its parent — found live in the
          // 2026-08-18 QA pass (Android only): as this screen's parent, the
          // gradient Container had to repaint every frame of the on-screen
          // keyboard's open animation (Choreographer logged a ~800ms/32-frame
          // stutter on first focus), since a resizing child forces its
          // parent's whole subtree to relayout/repaint. Every newer screen in
          // this app (create_party_screen.dart, live_ride_screen.dart, etc.)
          // already avoids this by using this exact Positioned.fill +
          // IgnorePointer pattern — this screen just predates it (S2, one of
          // the earliest built). iOS never showed the stutter (confirmed same
          // QA pass), consistent with Android's compositor being more
          // sensitive to this than iOS's.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF232B31), Color(0xFF1A1F23), Color(0xFF141920)],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar — kept pinned outside the scroll area, same pattern
              // as party_ready_screen.dart's back chevron.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: _BackButton(),
              ),

              // Scrollable content — fixes the "BOTTOM OVERFLOWED" RenderFlex
              // error on Android when the keyboard opens (same short-screen
              // overflow pattern fixed in party_ready_screen.dart on
              // 2026-07-08: content wrapped in Expanded + SingleChildScrollView,
              // Spacer replaced with a fixed SizedBox since Spacer doesn't
              // work inside an unbounded-height scroll view).
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      const Text(
                        'Enter your\nphone number',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: ChaloColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We\'ll send you a verification code',
                        style: TextStyle(
                          fontSize: 14,
                          color: ChaloColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Phone input
                      _PhoneInput(controller: _controller, onSubmit: _continue),

                      // Inline error
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFFE05252), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFE05252), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Continue button
                      _ContinueButton(isValid: _isValid && !_isLoading, isLoading: _isLoading, onTap: _continue),
                      const SizedBox(height: 32),

                      // Divider
                      _OrDivider(),
                      const SizedBox(height: 24),

                      // Social sign-in
                      _SocialButton(
                        icon: _GoogleIcon(),
                        label: 'Continue with Google',
                        onTap: () => _showNotSetUp('Google'),
                      ),
                      const SizedBox(height: 12),
                      _SocialButton(
                        icon: const Icon(Icons.apple, color: ChaloColors.textPrimary, size: 22),
                        label: 'Continue with Apple',
                        onTap: () => _showNotSetUp('Apple'),
                      ),

                      const SizedBox(height: 32),
                      _PrivacyNote(),
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

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: MetallicCard(
        borderRadius: BorderRadius.circular(12),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16),
        ),
      ),
    );
  }
}

class _PhoneInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _PhoneInput({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: [
          // India flag + code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: ChaloColors.borderDim)),
            ),
            child: const Row(
              children: [
                Text('🇮🇳', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text(
                  '+91',
                  style: TextStyle(
                    color: ChaloColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, color: ChaloColors.textSecondary, size: 18),
              ],
            ),
          ),

          // Number input
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(
                color: ChaloColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
              decoration: const InputDecoration(
                hintText: '00000 00000',
                hintStyle: TextStyle(
                  color: ChaloColors.textDisabled,
                  letterSpacing: 2,
                  fontSize: 18,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback onTap;

  const _ContinueButton({required this.isValid, required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isValid
            ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 4))]
            : [],
      ),
      child: ElevatedButton(
        onPressed: isValid ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isValid ? ChaloColors.primary : ChaloColors.bgCard,
          disabledBackgroundColor: ChaloColors.bgCard,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                'Continue',
                style: TextStyle(color: isValid ? Colors.white : ChaloColors.textDisabled),
              ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: ChaloColors.borderDim)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('or', style: TextStyle(color: ChaloColors.textSecondary, fontSize: 13)),
        ),
        Expanded(child: Container(height: 1, color: ChaloColors.borderDim)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MetallicCard(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: ChaloColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF4285F4)));
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      'By continuing, you agree to our Terms of Service and Privacy Policy',
      textAlign: TextAlign.center,
      style: TextStyle(color: ChaloColors.textSecondary, fontSize: 11, height: 1.5),
    );
  }
}
