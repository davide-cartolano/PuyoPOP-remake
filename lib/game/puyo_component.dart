import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';

import 'grid_component.dart';

/// Rappresenta un singolo Puyo: un cerchio colorato disegnato in una
/// precisa cella della griglia.
///
/// Da questo step in poi, `PuyoComponent` è deliberatamente "ignorante":
/// non gestisce input, non cade da solo, non sa nulla del gioco. Sa solo
/// due cose — "in quale cella mi trovo" e "che colore sono" — e si occupa
/// di disegnarsi correttamente in quella cella. Tutta l'intelligenza
/// (movimento, gravità, rotazione, collisioni) vive ora in `FallingPiece`,
/// che possiede e orchestra i `PuyoComponent` come un gruppo.
///
/// Lo stesso identico componente viene riusato sia per i blocchi del
/// pezzo attualmente controllabile, sia — una volta che il pezzo si
/// blocca — per i Puyo ormai fermi e impilati sul fondo: la differenza
/// non sta nel componente, ma in CHI lo controlla (o smette di farlo).
class PuyoComponent extends PositionComponent {
  /// Colonna corrente (0 = colonna più a sinistra).
  int column;

  /// Riga corrente (0 = riga più in alto).
  int row;

  /// Colore del Puyo. Determina anche, nei prossimi step, quali Puyo
  /// possono "scoppiare" insieme.
  final Color color;

  PuyoComponent({
    required this.column,
    required this.row,
    required this.color,
  }) : super(
          // Il Puyo occupa esattamente una cella della griglia.
          size: Vector2.all(GridComponent.cellSize),
          // Anchor.topLeft: `position` indica l'angolo in alto a sinistra
          // del componente, in linea con il modo in cui GridComponent
          // disegna le celle (a partire da (colonna*cellSize,
          // riga*cellSize)). Questo rende l'allineamento immediato.
          anchor: Anchor.topLeft,
        ) {
    moveTo(column, row);
  }

  /// Sposta questo Puyo in una nuova cella della griglia, ricalcolando
  /// subito la sua posizione in pixel di conseguenza.
  ///
  /// `verticalOffset` aggiunge un piccolo spostamento continuo (in pixel)
  /// rispetto al bordo superiore esatto della cella `newRow`. Serve per la
  /// caduta fluida: il Puyo "appartiene" già logicamente a `newRow` (è così
  /// che viene trattato dalle collisioni), ma visivamente sta ancora
  /// scivolando verso di essa, qualche pixel più in alto. Quando vale 0,
  /// il Puyo è perfettamente allineato alla griglia.
  ///
  /// È il metodo che `FallingPiece` chiama per spostare, far cadere o
  /// ruotare i blocchi che possiede: questo componente si limita ad
  /// "obbedire" e a ridisegnarsi nel posto giusto.
  void moveTo(int newColumn, int newRow, {double verticalOffset = 0}) {
    column = newColumn;
    row = newRow;
    position = Vector2(
      column * GridComponent.cellSize,
      row * GridComponent.cellSize + verticalOffset,
    );
  }

  /// Anima lo scivolamento verso la cella indicata da `column`/`row`
  /// CORRENTI, partendo dalla posizione visiva attuale, in `duration`
  /// secondi — è il modo in cui rendiamo "visibile" la gravità globale,
  /// invece di far scattare i Puyo istantaneamente da una cella all'altra.
  ///
  /// Si aspetta che chi la chiama (`PlayfieldGrid.applyGravity`) abbia
  /// GIÀ aggiornato lo stato logico (`column`/`row`) prima di invocarla:
  /// il resto del gioco deve poter considerare il Puyo arrivato a
  /// destinazione mentre l'occhio lo vede ancora scendere — lo stesso
  /// principio già visto con `_fallProgressPixels` in `FallingPiece`.
  ///
  /// Restituisce un Future che si completa alla fine dell'animazione:
  /// è il modo in cui `PuyoGame` sa quando può proseguire (es. controllare
  /// se la caduta ha appena formato un nuovo gruppo da far scoppiare).
  Future<void> fallTo({double duration = 0.2}) {
    final completer = Completer<void>();
    add(
      MoveToEffect(
        Vector2(
          column * GridComponent.cellSize,
          row * GridComponent.cellSize,
        ),
        EffectController(duration: duration),
        onComplete: completer.complete,
      ),
    );
    return completer.future;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final paint = Paint()..color = color;

    // Piccolo margine interno: il cerchio non tocca i bordi della cella,
    // così resta visibile la linea della griglia sotto il Puyo.
    const padding = 4.0;
    final radius = (size.x - padding * 2) / 2;
    final center = Offset(size.x / 2, size.y / 2);

    canvas.drawCircle(center, radius, paint);
  }
}
