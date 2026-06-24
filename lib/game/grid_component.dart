import 'dart:math' show sin;
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

  /// Quante righe, partendo dall'alto, vengono coperte dall'indicatore di
  /// pericolo quando `isInDanger` è vero. Tenuta in sincrono "a mano" con
  /// `PlayfieldGrid.dangerRowCount`: sono in due file diversi perché uno
  /// è puro stato (`PlayfieldGrid`) e l'altro puro rendering
  /// (`GridComponent`), e non vale la pena introdurre una dipendenza
  /// reciproca solo per condividere questa singola costante.
  static const int _dangerRowCount = 3;

  /// Impostato da `PuyoGame` ad ogni frame in base a
  /// `PlayfieldGrid.isStackInDanger()`: quando vero, le righe più alte
  /// della griglia lampeggiano in rosso per avvisare che il game over è
  /// vicino.
  bool isInDanger = false;

  /// Avanzamento, in secondi, dell'oscillazione del lampeggio: cresce
  /// solo mentre `isInDanger` è vero, così l'effetto riparte sempre dalla
  /// stessa fase quando il pericolo si ripresenta.
  double _dangerPulseTime = 0;

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
  void update(double dt) {
    super.update(dt);
    _dangerPulseTime = isInDanger ? _dangerPulseTime + dt : 0;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Pennello per lo sfondo della griglia: un gradiente verticale (notte
    // stellata, dal blu-viola scuro in alto a un blu più profondo in
    // basso) invece di un riempimento piatto, per dare al "tavolo di
    // gioco" un minimo di ambientazione.
    final backgroundPaint = Paint()
      ..shader = Gradient.linear(
        Offset(0, 0),
        Offset(0, size.y),
        [const Color(0xFF1B1B3A), const Color(0xFF0E0E1E)],
      );

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

    if (isInDanger) {
      _renderDangerOverlay(canvas);
    }
  }

  /// Sovrappone un velo rosso pulsante sulle righe più alte della
  /// griglia: un'oscillazione continua (seno del tempo trascorso),
  /// invece di un semplice on/off, rende il lampeggio più "vivo" e meno
  /// meccanico — lo stesso principio già usato per il battito di ciglia
  /// dei Puyo.
  void _renderDangerOverlay(Canvas canvas) {
    final pulse = (sin(_dangerPulseTime * 6) + 1) / 2;
    final overlayPaint = Paint()
      ..color = Color.lerp(const Color(0x00FF1744), const Color(0x66FF1744), pulse)!;

    final overlayRect = Rect.fromLTWH(0, 0, size.x, _dangerRowCount * cellSize);
    canvas.drawRect(overlayRect, overlayPaint);
  }
}
