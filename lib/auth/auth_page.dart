import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();

  final _userFocus = FocusNode();
  final _pwFocus = FocusNode();

  bool _register = false;
  bool _busy = false;
  bool _showPw = false;
  String? _err;

  late final AnimationController _bg;

  @override
  void initState() {
    super.initState();
    _bg = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _bg.dispose();
    _username.dispose();
    _password.dispose();
    _userFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final pw = _password.text;
      final u = _username.text.trim();
      if (_register) {
        await AuthApi.instance.register(username: u, password: pw);
      } else {
        await AuthApi.instance.login(username: u, password: pw);
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F4),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _bg,
              builder: (context, _) {
                final v = _bg.value;
                return CustomPaint(
                  painter: _AuthBackdropPainter(v: v),
                  child: const SizedBox.expand(),
                );
              },
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10)),
                                ],
                              ),
                              child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFFE04A3A)),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('JuheMusic', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                Text(
                                  _register ? '创建账号，开始同步喜欢与歌单' : '登录后继续你的收藏与最近',
                                  style: t.bodyMedium?.copyWith(color: Colors.black54, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          elevation: 12,
                          shadowColor: Colors.black.withOpacity(0.10),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _ModeTab(
                                      label: '登录',
                                      active: !_register,
                                      onTap: _busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _register = false;
                                                _err = null;
                                              });
                                              FocusScope.of(context).requestFocus(_userFocus);
                                            },
                                    ),
                                    const SizedBox(width: 8),
                                    _ModeTab(
                                      label: '注册',
                                      active: _register,
                                      onTap: _busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _register = true;
                                                _err = null;
                                              });
                                              FocusScope.of(context).requestFocus(_userFocus);
                                            },
                                    ),
                                    const Spacer(),
                                    AnimatedOpacity(
                                      duration: const Duration(milliseconds: 180),
                                      opacity: _busy ? 1 : 0,
                                      child: const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _username,
                                  focusNode: _userFocus,
                                  keyboardType: TextInputType.text,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_pwFocus),
                                  decoration: InputDecoration(
                                    labelText: '用户名',
                                    hintText: '例如：deoth5',
                                    prefixIcon: const Icon(Icons.person_outline_rounded),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _password,
                                  focusNode: _pwFocus,
                                  obscureText: !_showPw,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _busy ? null : _submit(),
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    hintText: '至少 10 位（建议更长）',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      onPressed: _busy ? null : () => setState(() => _showPw = !_showPw),
                                      icon: Icon(_showPw ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                    ),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                                if (_err != null) ...[
                                  const SizedBox(height: 10),
                                  Text(_err!, style: t.bodyMedium?.copyWith(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                                ],
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _busy ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE04A3A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Text(_register ? '创建并进入' : '登录并进入', style: const TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '提示：当前为 HTTP 连接时账号与 Token 可能被截获，建议尽快把后端切到 HTTPS。',
                                  style: t.bodySmall?.copyWith(color: Colors.black45, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFE6E2) : Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? const Color(0x33E04A3A) : Colors.transparent),
        ),
        child: Text(
          label,
          style: t.labelLarge?.copyWith(
            color: active ? const Color(0xFFE04A3A) : Colors.black54,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AuthBackdropPainter extends CustomPainter {
  _AuthBackdropPainter({required this.v});

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFF2F3F4);
    canvas.drawRect(Offset.zero & size, bg);

    final cx = size.width * (0.35 + 0.12 * math.sin(v * 2 * math.pi));
    final cy = size.height * (0.22 + 0.06 * math.cos(v * 2 * math.pi));
    final cx2 = size.width * (0.78 + 0.10 * math.cos(v * 2 * math.pi));
    final cy2 = size.height * (0.80 + 0.08 * math.sin(v * 2 * math.pi));

    final p1 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x33E04A3A), Color(0x1AE04A3A), Color(0x00E04A3A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: size.shortestSide * 0.62));
    canvas.drawCircle(Offset(cx, cy), size.shortestSide * 0.62, p1);

    final p2 = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x1A2A9D8F), Color(0x002A9D8F)],
      ).createShader(Rect.fromCircle(center: Offset(cx2, cy2), radius: size.shortestSide * 0.60));
    canvas.drawCircle(Offset(cx2, cy2), size.shortestSide * 0.60, p2);
  }

  @override
  bool shouldRepaint(covariant _AuthBackdropPainter oldDelegate) => oldDelegate.v != v;
}
