import 'dart:math' show sin;
import 'dart:ui';

import 'package:flame/components.dart';

/// Componente che disegna la griglia di gioco: 6 colonne x 12 righe, le
/// stesse proporzioni del campo di Puyo Pop Fever.
///
/// È un PositionComponent: ha una posizione, una dimensione e un "anchor"
/// (punto di riferimento per il posizionamento), ed è capace di disegnarsi
/// da solo sovrascrivendo `render`.
class GridComponent extends PositionComponent {
  static const int columns = 6;
  static const int rows = 12;

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

    final boardRect = size.toRect();
    final boardRRect = RRect.fromRectAndRadius(boardRect, const Radius.circular(10));

    // Fondale della vasca di gioco: un gradiente verticale scuro,
    // leggermente più trasparente del vecchio riempimento pieno, così lo
    // sfondo animato (bolle e stelle di `FeverBackground`) traspare
    // appena sotto i Puyo — l'effetto "acquario" delle schermate di Fever.
    final backgroundPaint = Paint()
      ..shader = Gradient.linear(
        Offset.zero,
        Offset(0, size.y),
        [const Color(0xCC1B1B3A), const Color(0xE60E0E1E)],
      );
    canvas.drawRRect(boardRRect, backgroundPaint);

    // Scacchiera sottile al posto delle linee dure: colonne alternate
    // appena più chiare, più vicine al look pulito del gioco originale
    // delle vecchie linee bianche a griglia.
    final altColumnPaint = Paint()..color = const Color(0x0AFFFFFF);
    for (int col = 0; col < columns; col += 2) {
      canvas.drawRect(Rect.fromLTWH(col * cellSize, 0, cellSize, size.y), altColumnPaint);
    }

    if (isInDanger) {
      _renderDangerOverlay(canvas);
    }

    // Cornice luminosa attorno al campo, sopra a tutto il resto.
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF6C5CE7);
    canvas.drawRRect(boardRRect, framePaint);

    final innerFramePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF);
    canvas.drawRRect(boardRRect.deflate(2), innerFramePaint);
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
