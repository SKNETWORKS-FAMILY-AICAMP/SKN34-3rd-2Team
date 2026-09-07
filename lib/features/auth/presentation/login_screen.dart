import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/demo/demo_accounts.dart';
import '../providers/auth_providers.dart';

/// 폐쇄형 로그인 화면 — 회원가입 버튼 없음
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _showQuickLogin = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _quickLogin(String email, String password) async {
    _emailController.text = email;
    _passwordController.text = password;
    await _handleLogin();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(signInProvider.notifier)
          .signIn(_emailController.text, _passwordController.text);
      // go_router redirect가 자동 처리
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 중 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _CubeBackground()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _BrandMark(),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 48 : 24,
                        vertical: 24,
                      ),
                      child: Align(
                        alignment: wide ? Alignment.centerLeft : Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: _LoginCard(
                            formKey: _formKey,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            obscurePassword: _obscurePassword,
                            isLoading: _isLoading,
                            showQuickLogin: _showQuickLogin,
                            onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            onToggleQuickLogin: () => setState(
                              () => _showQuickLogin = !_showQuickLogin,
                            ),
                            onLogin: _handleLogin,
                            onQuickLogin: _quickLogin,
                          ),
                        ),
                      ),
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

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          AppConstants.appName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoading,
    required this.showQuickLogin,
    required this.onToggleObscure,
    required this.onToggleQuickLogin,
    required this.onLogin,
    required this.onQuickLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoading;
  final bool showQuickLogin;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleQuickLogin;
  final VoidCallback onLogin;
  final Future<void> Function(String email, String password) onQuickLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Log in',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome to ${AppConstants.appName}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '사용자 아이디',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: '이메일을 입력하세요',
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: 18),
            const Text(
              '비밀번호',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                hintText: '비밀번호를 입력하세요',
                fillColor: AppColors.primaryLight.withValues(alpha: 0.45),
                filled: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textHint,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
              validator: Validators.password,
              onFieldSubmitted: (_) => onLogin(),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('계정은 관리자가 발급·재설정합니다.'),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textHint,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '아이디/비밀번호 찾기',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : onLogin,
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('로그인'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onToggleQuickLogin,
              child: Text(
                showQuickLogin ? '빠른 로그인 숨기기' : '빠른 로그인 (데모)',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (showQuickLogin) ...[
              const SizedBox(height: 8),
              _QuickLoginRow(
                label: '관리자',
                email: DemoAccounts.adminEmail,
                onTap: () => onQuickLogin(
                  DemoAccounts.adminEmail,
                  DemoAccounts.adminPassword,
                ),
              ),
              const SizedBox(height: 6),
              _QuickLoginRow(
                label: '강사',
                email: DemoAccounts.instructorEmail,
                onTap: () => onQuickLogin(
                  DemoAccounts.instructorEmail,
                  DemoAccounts.instructorPassword,
                ),
              ),
              const SizedBox(height: 6),
              _QuickLoginRow(
                label: '학생',
                email: DemoAccounts.studentEmail,
                onTap: () => onQuickLogin(
                  DemoAccounts.studentEmail,
                  DemoAccounts.studentPassword,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '계정은 관리자가 발급합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLoginRow extends StatelessWidget {
  const _QuickLoginRow({
    required this.label,
    required this.email,
    required this.onTap,
  });

  final String label;
  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(Icons.login, size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 레퍼런스 스타일 블루/화이트 큐브 장식 배경
class _CubeBackground extends StatelessWidget {
  const _CubeBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CubePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CubePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // soft gradient wash
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF8F9FB),
          AppColors.primaryLight.withValues(alpha: 0.55),
          const Color(0xFFEAF1FF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    void drawCube(Offset center, double s, Color color, double rotation) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);

      final rect = Rect.fromCenter(center: Offset.zero, width: s, height: s);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.12));

      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(rrect.shift(const Offset(4, 8)), shadow);

      final fill = Paint()..color = color;
      canvas.drawRRect(rrect, fill);

      // glass edge highlight
      final edge = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(rrect, edge);

      canvas.restore();
    }

    // right cluster
    drawCube(Offset(size.width * 0.72, size.height * 0.38), 110,
        AppColors.primary, -0.35);
    drawCube(Offset(size.width * 0.82, size.height * 0.52), 78,
        Colors.white.withValues(alpha: 0.92), 0.25);
    drawCube(Offset(size.width * 0.68, size.height * 0.58), 64,
        AppColors.primary.withValues(alpha: 0.55), 0.55);
    drawCube(Offset(size.width * 0.88, size.height * 0.32), 52,
        AppColors.primaryDark.withValues(alpha: 0.75), -0.7);
    drawCube(Offset(size.width * 0.78, size.height * 0.72), 44,
        Colors.white.withValues(alpha: 0.7), 0.1);

    // glass-like translucent cube
    drawCube(Offset(size.width * 0.62, size.height * 0.42), 90,
        Colors.white.withValues(alpha: 0.35), -0.2);

    // left scattered tiny cubes
    drawCube(Offset(size.width * 0.08, size.height * 0.55), 28,
        AppColors.primary.withValues(alpha: 0.35), 0.4);
    drawCube(Offset(size.width * 0.14, size.height * 0.72), 18,
        AppColors.textHint.withValues(alpha: 0.35), -0.3);
    drawCube(Offset(size.width * 0.05, size.height * 0.28), 22,
        AppColors.primaryLight, 0.6);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
