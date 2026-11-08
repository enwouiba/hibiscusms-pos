import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';

/// Ekran splash HibiscusMS la — anime.
///
/// - Imaj la fonn antre (fade) epi li poze avèk yon ti zoom (settle).
/// - Li kontinye yon zoom dous k ap respire (efè Ken Burns), konsa ekran an
///   pa janm fiks pandan app la ap chaje.
/// - Yon bann limyè (shine) balize an dyagonal sou tèks gold la san rete.
/// - Yon ba chajman gold anime kole anba ekran an.
///
/// Splash la rete afiche yon **dire minimòm** pou animasyon an gen tan jwe,
/// menm si sesyon an chaje pi vit; answit li deplase moun nan sou `/` oswa
/// `/login` selon si gen yon sesyon.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  /// Dire minimòm splash la rete vizib (pou animasyon an jwe omwen yon fwa).
  static const _minVisible = Duration(milliseconds: 2800);

  /// Antre a: fonn + poze. Jwe yon sèl fwa.
  late final AnimationController _entry;

  /// Respirasyon an: zoom dous k ap monte-desann san rete.
  late final AnimationController _breathe;

  /// Briyans lan: yon bann limyè k ap balize sou tèks gold la san rete.
  late final AnimationController _shine;

  late final Animation<double> _fade;
  late final Animation<double> _settle;

  @override
  void initState() {
    super.initState();

    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _fade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
    _settle = Tween<double>(begin: 1.08, end: 1.0).animate(
      CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic),
    );

    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _leaveWhenReady();
  }

  /// Tann dire minimòm lan ELatriye sesyon an fin chaje, answit deplase.
  Future<void> _leaveWhenReady() async {
    await Future<void>.delayed(_minVisible);
    while (mounted && ref.read(authControllerProvider).isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) {
      return;
    }
    final session = ref.read(authControllerProvider).valueOrNull;
    context.go(session == null ? '/login' : '/');
  }

  @override
  void dispose() {
    _entry.dispose();
    _breathe.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF001B6E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Imaj la: fonn antre + poze + respirasyon dous.
          AnimatedBuilder(
            animation: Listenable.merge([_entry, _breathe]),
            builder: (context, child) {
              final breathe = 1.0 + 0.045 * _breathe.value; // 1.0 → 1.045
              return Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _settle.value * breathe,
                  child: child,
                ),
              );
            },
            child: const Image(
              image: AssetImage('assets/images/splash.png'),
              fit: BoxFit.cover,
            ),
          ),

          // Briyans: yon bann limyè ki balize an dyagonal sou tèks gold la.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    return AnimatedBuilder(
                      animation: Listenable.merge([_entry, _shine]),
                      builder: (context, child) {
                        final dx = -w * 0.6 + _shine.value * (w * 2.2);
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: Transform.rotate(angle: -0.35, child: child),
                        );
                      },
                      // Yon streak blan briyan (nwayo ~70%) ki balize sou
                      // imaj la epi fè tèks la ak lèt gold yo glint.
                      child: Opacity(
                        opacity: 0.9,
                        child: Container(
                          width: w * 0.3,
                          height: c.maxHeight * 1.8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0x00FFFFFF),
                                Color(0x40FFFFFF),
                                Color(0xF2FFFFFF),
                                Color(0x40FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                              stops: [0.0, 0.42, 0.5, 0.58, 1.0],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Ba chajman gold anime kole anba ekran an.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FadeTransition(
              opacity: _fade,
              child: const SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  backgroundColor: Color(0x22FFFFFF),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE5A21E)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
