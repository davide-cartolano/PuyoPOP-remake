import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;

import 'piece_shapes.dart';
import 'puyo_component.dart';

/// Riquadro che mostra in anteprima il prossimo pezzo, riusando lo stesso
/// disegno (`paintPuyo`) dei Puyo veri ma a una scala più piccola e
/// indipendente dalla griglia di gioco: a differenza di `PuyoComponent`,
/// qui le celle non corrispondono a colonne/righe della partita, ma solo
/// a un piccolo sistema di coordinate locale usato per centrare la forma
/// dentro al riquadro.
class NextPiecePreviewComponent extends PositionComponent {
  NextPiecePreviewComponent()
      : super(
          size: Vector2.all(_boxSize),
          anchor: Anchor.topLeft,
        );

  static const double _boxSize = 120;
  static const double _previewCellSize = 28;

  List<GridOffset> _offsets = const [GridOffset(0, 0)];
  Color _color = Colors.grey;

  /// Aggiorna la forma e il colore mostrati, chiamato da `PuyoGame` ogni
  /// volta che viene deciso un nuovo "prossimo pezzo".
  void updatePiece(PieceSpec spec) {
    _offsets = spec.offsets;
    _color = spec.color;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final backgroundPaint = Paint()..color = const Color(0xFF1B1B2F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8)),
      backgroundPaint,
    );

    // Calcoliamo il riquadro (in celle di anteprima) occupato dalla forma,
    // per poterla centrare dentro al box indipendentemente da quanto sia
    // larga o alta — un Singolo e una Quadrupla a "T" occupano spazi
    // diversi, ma devono comparire entrambi centrati.
    final columns = [for (final offset in _offsets) offset.column];
    final rows = [for (final offset in _offsets) offset.row];
    final minColumn = columns.reduce((a, b) => a < b ? a : b);
    final maxColumn = columns.reduce((a, b) => a > b ? a : b);
    final minRow = rows.reduce((a, b) => a < b ? a : b);
    final maxRow = rows.reduce((a, b) => a > b ? a : b);

    final shapeWidth = (maxColumn - minColumn + 1) * _previewCellSize;
    final shapeHeight = (maxRow - minRow + 1) * _previewCellSize;

    final originX = (size.x - shapeWidth) / 2 - minColumn * _previewCellSize;
    final originY = (size.y - shapeHeight) / 2 - minRow * _previewCellSize;

    const padding = 3.0;
    final radius = (_previewCellSize - padding * 2) / 2;

    for (final offset in _offsets) {
      final center = Offset(
        originX + offset.column * _previewCellSize + _previewCellSize / 2,
        originY + offset.row * _previewCellSize + _previewCellSize / 2,
      );
      paintPuyo(canvas, center: center, radius: radius, color: _color);
    }
  }
}
