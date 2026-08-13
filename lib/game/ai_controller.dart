import 'dart:math';

import 'package:flame/components.dart';

import 'falling_piece.dart';
import 'playfield_grid.dart';
import 'puyo_ai.dart';

/// Pilota un `FallingPiece` al posto della tastiera, per la modalità
/// "Gioca contro CPU".
///
/// Alla sua prima esecuzione, chiede a `decideBestMove` la mossa migliore
/// per il pezzo corrente (colonna + rotazione) e da quel momento si limita
/// a eseguirla un'azione alla volta, con una pausa fra una e l'altra — la
/// cui durata dipende dalla difficoltà: è quella pausa a rendere i
/// movimenti dell'AI leggibili a schermo, e a differenziare la reattività
/// di una CPU facile da una difficile.
class AiController extends Component {
  AiController({
    required this.piece,
    required this.playfieldGrid,
    required this.difficulty,
    required this.random,
  });

  final FallingPiece piece;
  final PlayfieldGrid playfieldGrid;
  final AiDifficulty difficulty;

  /// Sorgente di casualità condivisa con la partita: serve sia per gli
  /// "errori" volontari della CPU sia per il rumore sul punteggio delle
  /// mosse (vedi `decideBestMove`).
  final Random random;

  AiMove? _move;
  int _rotationsDone = 0;
  double _actionCooldown = 0;

  @override
  void update(double dt) {
    super.update(dt);

    // Il pezzo si è bloccato (o lo gestisce già qualcun altro): il nostro
    // compito qui è finito, `PuyoGame` ne creerà uno nuovo con un nuovo
    // `AiController`.
    if (piece.isLocked) {
      removeFromParent();
      return;
    }

    _move ??= decideBestMove(playfieldGrid, piece.offsets, piece.color, difficulty, random);
    final move = _move!;

    _actionCooldown -= dt;
    if (_actionCooldown > 0) return;

    if (_rotationsDone < move.rotations) {
      piece.rotateClockwise();
      _rotationsDone++;
      _actionCooldown = difficulty.actionInterval;
      return;
    }

    if (piece.pivotColumn < move.targetColumn) {
      piece.moveRight();
      _actionCooldown = difficulty.actionInterval;
    } else if (piece.pivotColumn > move.targetColumn) {
      piece.moveLeft();
      _actionCooldown = difficulty.actionInterval;
    } else {
      // In colonna e angolazione giuste: non resta che farlo scendere.
      piece.setSoftDropping(true);
    }
  }
}
