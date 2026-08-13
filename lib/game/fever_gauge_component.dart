import 'dart:ui';

import 'package:flame/components.dart';

/// Indicatore della modalità Fever, mostrato nella sidebar accanto alla
/// griglia:
/// - fuori dalla Fever: 8 pallini che si riempiono man mano che la barra
///   cresce (vedi `PuyoGame`: +1 per ogni anello di catena mentre c'è
///   spazzatura in sospeso contro di noi);
/// - durante la Fever: una barra del tempo che si svuota nei 45 secondi
///   della modalità, con la scritta "FEVER!".
///
/// È puro rendering: `PuyoGame` aggiorna i campi `charge`, `isActive` e
/// `timeFraction` e questo componente si limita a disegnarli.
class FeverGaugeComponent extends PositionComponent {
  FeverGaugeComponent() : super(size: Vector2(140, 46), anchor: Anchor.topLeft);

  static const int maxCharge = 8;

  /// Livello corrente della barra (0..8).
  int charge = 0;

  /// Vero mentre la modalità Fever è in corso.
  bool isActive = false;

  /// Frazione di tempo Fever rimanente (1 → appena iniziata, 0 → finita).
  double timeFraction = 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (isActive) {
      _renderTimer(canvas);
    } else {
      _renderCharge(canvas);
    }
  }

  /// Otto pallini in fila: pieni (arancio acceso) fino a `charge`, vuoti
  /// oltre. È la barra 1-8 di Puyo Pop Fever.
  void _renderCharge(Canvas canvas) {
    const dotRadius = 7.0;
    const spacing = 17.0;

    final emptyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF);
    final fullPaint = Paint()..color = const Color(0xFFFFA000);
    final glowPaint = Paint()..color = const Color(0x55FFC400);

    for (var i = 0; i < maxCharge; i++) {
      final center = Offset(dotRadius + i * spacing, size.y / 2);
      if (i < charge) {
        canvas.drawCircle(center, dotRadius + 2, glowPaint);
        canvas.drawCircle(center, dotRadius, fullPaint);
      } else {
        canvas.drawCircle(center, dotRadius, emptyPaint);
      }
    }
  }

  /// Barra orizzontale del tempo rimanente, colorata dal giallo al rosso
  /// man mano che si esaurisce.
  void _renderTimer(Canvas canvas) {
    final barRect = Rect.fromLTWH(0, size.y / 2 - 7, size.x, 14);
    final barRRect = RRect.fromRectAndRadius(barRect, const Radius.circular(7));

    final backgroundPaint = Paint()..color = const Color(0x33FFFFFF);
    canvas.drawRRect(barRRect, backgroundPaint);

    final fillWidth = (size.x * timeFraction).clamp(0.0, size.x);
    if (fillWidth > 0) {
      final fillRect = Rect.fromLTWH(0, barRect.top, fillWidth, barRect.height);
      final fillPaint = Paint()
        ..color = Color.lerp(const Color(0xFFFF1744), const Color(0xFFFFC400), timeFraction)!;
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(7)), fillPaint);
    }
  }
}
