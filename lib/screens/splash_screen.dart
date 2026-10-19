import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colore di sfondo dello splash (uguale allo splash nativo Android).
const kSplashColor = Color(0xFF3949AB);

/// Animazione d'avvio: tre foto entrano a ventaglio, si impilano e
/// si trasformano in una pagina PDF; poi appare il titolo.
/// Un tocco salta l'animazione.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => widget.next,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  /// Valore 0..1 di [_c] ristretto all'intervallo [a, b] con una curva.
  double _iv(double a, double b, [Curve curve = Curves.easeOutCubic]) {
    final t = ((_c.value - a) / (b - a)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _goNext,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kSplashColor, Color(0xFF283593)],
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 260, height: 200, child: _stage()),
                  const SizedBox(height: 28),
                  _title(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage() {
    // Fase 2: il ventaglio si chiude.
    final collapse = _iv(0.38, 0.58, Curves.easeInOutCubic);
    // Fase 3: la pagina PDF appare.
    final pageIn = _iv(0.52, 0.74, Curves.easeOutBack);
    final pageOpacity = _iv(0.52, 0.62);
    final cardsOpacity = 1 - _iv(0.56, 0.66);

    const fanAngles = [-0.32, 0.0, 0.32];
    const fanX = [-62.0, 0.0, 62.0];
    const palettes = [
      [Color(0xFFFFB74D), Color(0xFFE57373)],
      [Color(0xFF4FC3F7), Color(0xFF7986CB)],
      [Color(0xFF81C784), Color(0xFF26A69A)],
    ];

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Ordine: laterali sotto, centrale sopra.
        for (final i in const [0, 2, 1])
          Builder(builder: (_) {
            // Fase 1: ingresso dal basso, sfalsato.
            final enter = _iv(i * 0.07, 0.26 + i * 0.07, Curves.easeOutBack);
            final enterFade = _iv(i * 0.07, 0.14 + i * 0.07);
            final angle = fanAngles[i] * (1 - collapse);
            final dx = fanX[i] * (1 - collapse);
            final dy = 140 * (1 - enter) - 6 * collapse * (i - 1).abs();
            return Opacity(
              opacity: (enterFade * cardsOpacity).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: 1 - 0.12 * collapse,
                    child: _PhotoCard(colors: palettes[i]),
                  ),
                ),
              ),
            );
          }),
        Opacity(
          opacity: pageOpacity,
          child: Transform.scale(
            scale: 0.55 + 0.45 * pageIn,
            child: Transform.rotate(
              angle: (1 - pageIn) * -0.15,
              child: const _PdfPage(),
            ),
          ),
        ),
        // Piccolo bagliore quando la pagina "atterra".
        IgnorePointer(
          child: Opacity(
            opacity: (math.sin(_iv(0.62, 0.86, Curves.linear) * math.pi) * 0.5)
                .clamp(0.0, 1.0),
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title() {
    final t = _iv(0.66, 0.88);
    final s = _iv(0.74, 0.96);
    return Column(children: [
      Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: const Text(
            'Immagini → PDF',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Opacity(
        opacity: s,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - s)),
          child: const Text(
            'Tutto sul tuo dispositivo',
            style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 15),
          ),
        ),
      ),
    ]);
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 120,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: const Center(
            child: Icon(Icons.landscape_rounded, color: Colors.white, size: 44),
          ),
        ),
      ),
    );
  }
}

class _PdfPage extends StatelessWidget {
  const _PdfPage();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 156,
      child: Stack(clipBehavior: Clip.none, children: [
        const Positioned.fill(child: CustomPaint(painter: _PagePainter())),
        Positioned(
          left: -14,
          bottom: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: const Text(
              'PDF',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PagePainter extends CustomPainter {
  const _PagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const fold = 28.0;
    final w = size.width, h = size.height;
    final page = Path()
      ..moveTo(6, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h - 6)
      ..quadraticBezierTo(w, h, w - 6, h)
      ..lineTo(6, h)
      ..quadraticBezierTo(0, h, 0, h - 6)
      ..lineTo(0, 6)
      ..quadraticBezierTo(0, 0, 6, 0)
      ..close();

    canvas.drawShadow(page, Colors.black, 10, false);
    canvas.drawPath(page, Paint()..color = Colors.white);

    // Angolo piegato
    final corner = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w - fold, fold - 4)
      ..quadraticBezierTo(w - fold, fold, w - fold + 4, fold)
      ..lineTo(w, fold)
      ..close();
    canvas.drawPath(corner, Paint()..color = const Color(0xFFD0D4E8));

    // Immagine nella pagina
    final imgRect = RRect.fromLTRBR(14, 36, w - 14, 92, const Radius.circular(4));
    canvas.drawRRect(
      imgRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4FC3F7), Color(0xFF7986CB)],
        ).createShader(imgRect.outerRect),
    );
    final mountains = Path()
      ..moveTo(14, 92)
      ..lineTo(40, 62)
      ..lineTo(58, 80)
      ..lineTo(74, 66)
      ..lineTo(w - 14, 92)
      ..close();
    canvas.save();
    canvas.clipRRect(imgRect);
    canvas.drawPath(mountains, Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawCircle(Offset(w - 32, 50), 6, Paint()..color = const Color(0xFFFFF59D));
    canvas.restore();

    // Righe di "testo"
    final line = Paint()
      ..color = const Color(0xFFDDE0EE)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(16, 18), Offset(w - fold - 10, 18), line);
    canvas.drawLine(const Offset(40, 108), Offset(w - 16, 108), line);
    canvas.drawLine(const Offset(48, 122), Offset(w - 26, 122), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
