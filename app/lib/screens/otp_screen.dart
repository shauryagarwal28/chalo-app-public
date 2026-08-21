import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'profile_creation_screen.dart';

class OtpScreen extends StatefulWidget {
  /// Display-only, e.g. "+91 98765 43210" — unchanged from before this
  /// screen talked to a real backend.
  final String phone;

  /// E.164, e.g. "+919876543210" — what actually gets sent to
  /// POST /auth/verify-otp. Kept separate from [phone] rather than
  /// reformatting it, since the display string has a space and this
  /// doesn't.
  final String e164Phone;

  /// Dev-mode-only OTP the backend handed back from
  /// POST /auth/request-otp's `debugOtp` field (see api-design.md — omitted
  /// entirely in production). Used to auto-fill the boxes below instead of
  /// requiring a real SMS during testing; null if the backend ever runs in
  /// production mode, in which case the boxes are left blank as before.
  final String? debugOtp;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.e164Phone,
    this.debugOtp,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isComplete = false;
  bool _isVerifying = false;
  String? _errorMessage;
  int _resendSeconds = 30;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    final debugOtp = widget.debugOtp;
    if (debugOtp != null && debugOtp.length == 6) {
      // Dev-mode auto-fill — see [OtpScreen.debugOtp]'s doc comment. Still
      // requires a real tap on "Verify" below, so the on-screen flow is
      // unchanged; this just removes the need for a human to read the
      // backend's console log to find the code during testing.
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = debugOtp[i];
      }
      _isComplete = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startResendTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendSeconds > 0) {
        setState(() => _resendSeconds--);
        _startResendTimer();
      }
    });
  }

  void _onDigitEntered(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    // Check if all 6 digits filled
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

  Future<void> _verify() async {
    if (!_isComplete || _isVerifying) return;
    final code = _controllers.map((c) => c.text).join();

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // Real backend call — POST /auth/verify-otp. On success this also
      // populates AuthSession (auth_service.dart) with the real access/
      // refresh tokens every later screen needs.
      await AuthService.verifyOtp(widget.e164Phone, code);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileCreationScreen()),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = e.message;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF232B31), Color(0xFF1A1F23), Color(0xFF141920)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _BackButton(),
                const SizedBox(height: 32),
                const Text(
                  'Verify your\nnumber',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: ChaloColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: ChaloColors.textSecondary),
                    children: [
                      const TextSpan(text: 'Code sent to '),
                      TextSpan(
                        text: widget.phone,
                        style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // OTP boxes
                _OtpBoxes(
                  controllers: _controllers,
                  focusNodes: _focusNodes,
                  onChanged: _onDigitEntered,
                  onBackspace: _onBackspace,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
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
                const SizedBox(height: 32),

                // Verify button
                _VerifyButton(
                  isComplete: _isComplete && !_isVerifying,
                  isLoading: _isVerifying,
                  onTap: _verify,
                ),
                const SizedBox(height: 24),

                // Resend
                Center(
                  child: _resendSeconds > 0
                      ? Text(
                          'Resend code in ${_resendSeconds}s',
                          style: const TextStyle(color: ChaloColors.textSecondary, fontSize: 13),
                        )
                      : GestureDetector(
                          onTap: () => setState(() => _resendSeconds = 30),
                          child: const Text(
                            'Resend code',
                            style: TextStyle(
                              color: ChaloColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

class _OtpBoxes extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int, String) onChanged;
  final void Function(int) onBackspace;

  const _OtpBoxes({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => _OtpBox(
        controller: controllers[i],
        focusNode: focusNodes[i],
        onChanged: (v) => onChanged(i, v),
        onBackspace: () => onBackspace(i),
      )),
    );
  }
}

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() => setState(() => _isFocused = widget.focusNode.hasFocus));
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValue = widget.controller.text.isNotEmpty;

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
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // Found live 2026-08-18 QA pass, Android only: with the app's
          // default (orange) cursor theme and no override here, Android
          // renders its native text-selection drag handle — a large
          // teardrop — under the box on focus. Meaningless for a 1-digit
          // field anyway (nothing to select or drag a cursor within), so
          // disabling interactive selection removes the handle entirely
          // rather than fighting its color. iOS never showed this artifact
          // (it renders selection handles differently), confirmed via the
          // same QA pass.
          enableInteractiveSelection: false,
          style: const TextStyle(
            color: ChaloColors.textPrimary,
            fontSize: 22,
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


class _VerifyButton extends StatelessWidget {
  final bool isComplete;
  final bool isLoading;
  final VoidCallback onTap;

  const _VerifyButton({
    required this.isComplete,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isComplete
            ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 4))]
            : [],
      ),
      child: ElevatedButton(
        onPressed: isComplete ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isComplete ? ChaloColors.primary : ChaloColors.bgCard,
          disabledBackgroundColor: ChaloColors.bgCard,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                'Verify',
                style: TextStyle(color: isComplete ? Colors.white : ChaloColors.textDisabled),
              ),
      ),
    );
  }
}
