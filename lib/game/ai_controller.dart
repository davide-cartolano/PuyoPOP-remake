import 'package:flame/components.dart';

import 'falling_piece.dart';
import 'playfield_grid.dart';
import 'puyo_ai.dart';

/// Pilota un `FallingPiece` al posto della tastiera, per la modalità
/// "Gioca contro CPU".
///
/// Alla sua prima esecuzione, chiede a `decideBestMove` la mossa migliore
/// per il pezzo corrente (colonna + rotazione) e da quel momento si limita
/// a eseguirla un'azione alla volta, con una pausa fra una e l'altra: è
/// quella pausa a rendere i movimenti dell'AI leggibili a schermo, invece
/// di uno scatto istantaneo nella posizione finale.
class AiController extends Component {
  AiController({required this.piece, required this.playfieldGrid});

  final FallingPiece piece;
  final PlayfieldGrid playfieldGrid;

  /// Quanti secondi separano un'azione dell'AI (rotazione o spostamento)
  /// dalla successiva.
  static const double _actionInterval = 0.12;

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

    _move ??= decideBestMove(playfieldGrid, piece.offsets);
    final move = _move!;

    _actionCooldown -= dt;
    if (_actionCooldown > 0) return;

    if (_rotationsDone < move.rotations) {
      piece.rotateClockwise();
      _rotationsDone++;
      _actionCooldown = _actionInterval;
      return;
    }

    if (piece.pivotColumn < move.targetColumn) {
      piece.moveRight();
      _actionCooldown = _actionInterval;
    } else if (piece.pivotColumn > move.targetColumn) {
      piece.moveLeft();
      _actionCooldown = _actionInterval;
    } else {
      // In colonna e angolazione giuste: non resta che farlo scendere.
      piece.setSoftDropping(true);
    }
  }
}
