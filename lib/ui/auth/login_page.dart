import "dart:async";
import "dart:ui";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:connectivity_plus/connectivity_plus.dart";

import "../../app_providers.dart";
import "../shell/shell.dart";

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isObscured = true;
  String? _errorMessage;
  bool _isOnline = false;
  StreamSubscription<dynamic>? _connectivitySubscription;

  late AnimationController _mainController;
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _mainController.forward();
  }

  void _initializeConnectivity() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    _applyConnectivity(initial);
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(_applyConnectivity);
  }

  void _applyConnectivity(dynamic result) {
    bool online = result is List<ConnectivityResult>
        ? (result.isNotEmpty && !result.contains(ConnectivityResult.none))
        : (result != ConnectivityResult.none);
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _mainController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Majestic Aurora Background
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return CustomPaint(
                painter: AuroraPainter(_bgController.value, cs.primaryContainer, cs.secondaryContainer),
                child: Container(),
              );
            },
          ),
          
          // Main Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    children: [
                      // _staggeredFade(0.0, 0.4, _buildLogo(cs)),
                      const SizedBox(height: 24),
                      _staggeredFade(0.2, 0.6, _buildTitle(cs)),
                      const SizedBox(height: 32),
                      _staggeredFade(0.4, 0.8, _buildGlassForm(cs)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staggeredFade(double start, double end, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _mainController,
        curve: Interval(start, end, curve: Curves.easeIn),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _mainController, curve: Interval(start, end, curve: Curves.easeOutCubic)),
        ),
        child: child,
      ),
    );
  }

  // Widget _buildLogo(ColorScheme cs) {
  //   return Hero(
  //     tag: 'logo',
  //     child: Container(
  //       height: 80,
  //       width: 80,
  //       decoration: BoxDecoration(
  //         color: Colors.white.withOpacity(0.9),
  //         shape: BoxShape.circle,
  //         boxShadow: [
  //           BoxShadow(color: cs.primary.withOpacity(0.2), blurRadius: 30, spreadRadius: 10),
  //         ],
  //       ),
  //       child: Icon(Icons.vignette_rounded, size: 40, color: cs.primary),
  //     ),
  //   );
  // }

  Widget _buildTitle(ColorScheme cs) {
    return Column(
      children: [
        Text(
          "VOS Mobile",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        _buildStatusBadge(cs),
      ],
    );
  }

  Widget _buildGlassForm(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildField(controller: _emailController, label: "Email", icon: Icons.mail_outline_rounded, cs: cs),
                const SizedBox(height: 16),
                _buildField(
                  controller: _passwordController,
                  label: "Password",
                  icon: Icons.lock_open_rounded,
                  cs: cs,
                  isPassword: true,
                ),
                if (_errorMessage != null) _buildError(cs),
                const SizedBox(height: 24),
                _buildSubmitButton(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({required TextEditingController controller, required String label, required IconData icon, required ColorScheme cs, bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _isObscured,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword ? IconButton(
          icon: Icon(_isObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          onPressed: () => setState(() => _isObscured = !_isObscured),
        ) : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildSubmitButton(ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          shadowColor: cs.primary.withOpacity(0.4),
        ),
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading 
          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) 
          : const Text("Continue", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatusBadge(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _isOnline ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2)),
      ),
      child: Text(
        _isOnline ? "• Connected" : "• Offline Mode",
        style: TextStyle(fontSize: 11, color: _isOnline ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(_errorMessage!, style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ref.read(authRepositoryProvider).login(email: _emailController.text, password: _passwordController.text);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Shell()));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class AuroraPainter extends CustomPainter {
  final double animationValue;
  final Color color1;
  final Color color2;

  AuroraPainter(this.animationValue, this.color1, this.color2);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    paint.color = color1.withOpacity(0.4);
    canvas.drawCircle(
      Offset(size.width * 0.2 + (animationValue * 50), size.height * 0.2 + (animationValue * 100)),
      size.width * 0.6,
      paint,
    );

    paint.color = color2.withOpacity(0.3);
    canvas.drawCircle(
      Offset(size.width * 0.8 - (animationValue * 50), size.height * 0.8 - (animationValue * 100)),
      size.width * 0.7,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant AuroraPainter oldDelegate) => true;
}