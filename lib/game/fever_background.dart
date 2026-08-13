import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

/// Sfondo animato in stile "Fever": un gradiente notturno viola-blu su
/// tutta l'area di gioco, con bolle traslucide che salgono lentamente e
/// qualche stella scintillante — l'ambientazione "da sogno" tipica delle
/// schermate di Puyo Pop Fever, al posto del nero piatto.
///
/// È un componente puro-rendering: nessuna logica di gioco, si limita a
/// riempire `size` (impostata da `PuyoGame` a ogni resize) e ad animare
/// gli elementi decorativi in `update`.
class FeverBackground extends PositionComponent {
  FeverBackground() : super(position: Vector2.zero(), anchor: Anchor.topLeft, priority: -10);

  static const int _bubbleCount = 18;
  static const int _starCount = 26;

  final Random _random = Random();

  /// Bolle: posizione normalizzata (0..1), raggio e velocità di salita.
  final List<_Bubble> _bubbles = [];

  /// Stelle: posizione normalizzata e fase dello scintillio.
  final List<_Star> _stars = [];

  double _time = 0;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    for (var i = 0; i < _bubbleCount; i++) {
      _bubbles.add(_Bubble(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 6 + _random.nextDouble() * 22,
        speed: 0.02 + _random.nextDouble() * 0.05,
        driftPhase: _random.nextDouble() * 2 * pi,
      ));
    }
    for (var i = 0; i < _starCount; i++) {
      _stars.add(_Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        phase: _random.nextDouble() * 2 * pi,
        size: 1 + _random.nextDouble() * 2,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    for (final bubble in _bubbles) {
      bubble.y -= bubble.speed * dt;
      if (bubble.y < -0.08) {
        // Rientra dal fondo, in una colonna diversa: la popolazione di
        // bolle resta costante senza mai creare/distruggere oggetti.
        bubble.y = 1.08;
        bubble.x = _random.nextDouble();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x <= 0 || size.y <= 0) return;

    final backgroundPaint = Paint()
      ..shader = Gradient.linear(
        Offset.zero,
        Offset(0, size.y),
        [
          const Color(0xFF2A1B54),
          const Color(0xFF1B1B3A),
          const Color(0xFF0B0B1E),
        ],
        [0.0, 0.55, 1.0],
      );
    canvas.drawRect(size.toRect(), backgroundPaint);

    for (final star in _stars) {
      final twinkle = (sin(_time * 2 + star.phase) + 1) / 2;
      final starPaint = Paint()..color = Color.fromRGBO(255, 255, 255, 0.15 + twinkle * 0.5);
      canvas.drawCircle(Offset(star.x * size.x, star.y * size.y), star.size, starPaint);
    }

    for (final bubble in _bubbles) {
      // Leggera deriva laterale sinusoidale, per una salita "galleggiante"
      // invece che perfettamente rettilinea.
      final drift = sin(_time * 0.8 + bubble.driftPhase) * 10;
      final center = Offset(bubble.x * size.x + drift, bubble.y * size.y);

      final bubblePaint = Paint()..color = const Color(0x14FFFFFF);
      canvas.drawCircle(center, bubble.radius, bubblePaint);

      final rimPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x22FFFFFF);
      canvas.drawCircle(center, bubble.radius, rimPaint);
    }
  }
}

class _Bubble {
  _Bubble({required this.x, required this.y, required this.radius, required this.speed, required this.driftPhase});

  double x;
  double y;
  final double radius;
  final double speed;
  final double driftPhase;
}

class _Star {
  _Star({required this.x, required this.y, required this.phase, required this.size});

  final double x;
  final double y;
  final double phase;
  final double size;
}
