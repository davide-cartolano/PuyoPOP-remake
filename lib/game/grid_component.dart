import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;

/// Componente che disegna la griglia di gioco: 8 colonne x 15 righe.
///
/// È un PositionComponent: ha una posizione, una dimensione e un "anchor"
/// (punto di riferimento per il posizionamento), ed è capace di disegnarsi
/// da solo sovrascrivendo `render`.
class GridComponent extends PositionComponent {
  static const int columns = 8;
  static const int rows = 15;

  /// Lato di ogni cella della griglia, in pixel logici.
  static const double cellSize = 40;

  GridComponent()
      : super(
          // La dimensione totale del componente è calcolata dal numero di
          // celle moltiplicato per la loro grandezza.
          size: Vector2(columns * cellSize, rows * cellSize),
          // Anchor.center fa sì che `position` indichi il CENTRO del
          // componente (e non l'angolo in alto a sinistra, come sarebbe
          // di default). Questo ci semplifica la vita per centrarlo.
          anchor: Anchor.center,
        );

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Pennello per lo sfondo della griglia (un riquadro scuro semi-trasparente
    // che farà da "tavolo di gioco").
    final backgroundPaint = Paint()..color = const Color(0xFF1B1B2F);

    // Pennello per le linee della griglia.
    final linePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Disegniamo lo sfondo dell'intera area di gioco.
    // `size.toRect()` converte la dimensione del componente in un Rect
    // che parte da (0,0): tutto il rendering di un componente avviene nel
    // suo sistema di coordinate locale, Flame si occupa di traslarlo nella
    // posizione corretta sullo schermo.
    canvas.drawRect(size.toRect(), backgroundPaint);

    // Disegniamo le linee verticali (una per ogni colonna, compresi i bordi).
    for (int col = 0; col <= columns; col++) {
      final x = col * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), linePaint);
    }

    // Disegniamo le linee orizzontali (una per ogni riga, compresi i bordi).
    for (int row = 0; row <= rows; row++) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.x, y), linePaint);
    }
  }
}
