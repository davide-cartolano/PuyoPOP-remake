import 'grid_component.dart';
import 'piece_shapes.dart';
import 'playfield_grid.dart';

/// Mossa decisa dall'AI per il pezzo corrente: quante rotazioni in senso
/// orario applicare (0-3) e in quale colonna pivot lasciarlo cadere.
class AiMove {
  const AiMove({required this.rotations, required this.targetColumn});

  final int rotations;
  final int targetColumn;
}

/// Decide la mossa migliore per `offsets` (la forma del pezzo corrente,
/// nella sua angolazione attuale) simulando OGNI combinazione di rotazione
/// (0-3) e colonna possibile, e scegliendo quella con il punteggio
/// euristico più alto secondo `_scorePlacement`.
///
/// È una ricerca esaustiva, non un vero minimax: non c'è un avversario che
/// risponde alle nostre mosse (le due griglie, in modalità CPU, sono
/// indipendenti), quindi basta valutare l'effetto della propria mossa sulla
/// propria griglia — non serve un albero di gioco a più livelli.
AiMove decideBestMove(PlayfieldGrid grid, List<GridOffset> currentOffsets) {
  AiMove? bestMove;
  var bestScore = double.negativeInfinity;

  var rotatedOffsets = currentOffsets;
  for (var rotations = 0; rotations < 4; rotations++) {
    if (rotations > 0) {
      rotatedOffsets = [for (final offset in rotatedOffsets) offset.rotatedClockwise()];
    }

    final columns = rotatedOffsets.map((offset) => offset.column);
    final minColumnOffset = columns.reduce((a, b) => a < b ? a : b);
    final maxColumnOffset = columns.reduce((a, b) => a > b ? a : b);

    final firstColumn = -minColumnOffset;
    final lastColumn = GridComponent.columns - 1 - maxColumnOffset;

    for (var pivotColumn = firstColumn; pivotColumn <= lastColumn; pivotColumn++) {
      final landingRow = _computeLandingRow(grid, pivotColumn, rotatedOffsets);
      if (landingRow == null) continue;

      final score = _scorePlacement(grid, pivotColumn, landingRow, rotatedOffsets);
      if (score > bestScore) {
        bestScore = score;
        bestMove = AiMove(rotations: rotations, targetColumn: pivotColumn);
      }
    }
  }

  // Se nessuna colonna risultasse percorribile (pila già al massimo),
  // restiamo semplicemente fermi: il game over verrà rilevato altrove.
  return bestMove ?? const AiMove(rotations: 0, targetColumn: 0);
}

/// Vero se ogni blocco della forma, con il pivot in (pivotColumn, pivotRow),
/// cadrebbe in una cella libera. Le righe sopra alla griglia (row < 0) sono
/// considerate libere per definizione: è lì che un pezzo "emerge" prima di
/// entrare nell'area di gioco vera e propria, esattamente come già
/// avviene per il pezzo controllato dal giocatore (vedi `FallingPiece`).
bool _canPlaceAt(PlayfieldGrid grid, int pivotColumn, int pivotRow, List<GridOffset> offsets) {
  for (final offset in offsets) {
    final column = pivotColumn + offset.column;
    final row = pivotRow + offset.row;
    if (column < 0 || column >= GridComponent.columns) return false;
    if (row < 0) continue;
    if (!grid.isFree(column, row)) return false;
  }
  return true;
}

/// Simula la caduta libera della forma nella colonna indicata, restituendo
/// la riga pivot finale di atterraggio, o `null` se la forma non entra
/// nemmeno alla riga di spawn (colonna già piena fino in cima).
int? _computeLandingRow(PlayfieldGrid grid, int pivotColumn, List<GridOffset> offsets) {
  if (!_canPlaceAt(grid, pivotColumn, 0, offsets)) return null;

  var row = 0;
  while (_canPlaceAt(grid, pivotColumn, row + 1, offsets)) {
    row++;
  }
  return row;
}

/// Punteggio euristico di una mossa: più alto è, migliore è la mossa.
///
/// Penalizza altezza massima della pila, "sbalzo" fra colonne adiacenti
/// (bumpiness) e buchi creati (celle vuote sotto a Puyo bloccati — qui
/// inaccessibili finché non scoppia qualcosa sopra di loro); premia
/// l'accostare il pezzo a Puyo già presenti dello stesso colore, che è
/// ciò che costruisce i gruppi che poi scoppiano.
double _scorePlacement(PlayfieldGrid grid, int pivotColumn, int pivotRow, List<GridOffset> offsets) {
  final landingCells = [
    for (final offset in offsets) (column: pivotColumn + offset.column, row: pivotRow + offset.row),
  ];
  final landingByColumn = <int, int>{};
  for (final cell in landingCells) {
    final currentTop = landingByColumn[cell.column];
    if (currentTop == null || cell.row < currentTop) {
      landingByColumn[cell.column] = cell.row;
    }
  }

  final heights = List<int>.filled(GridComponent.columns, 0);
  for (var column = 0; column < GridComponent.columns; column++) {
    var topRow = GridComponent.rows;
    for (var row = 0; row < GridComponent.rows; row++) {
      if (!grid.isFree(column, row)) {
        topRow = row;
        break;
      }
    }

    final pieceTopRow = landingByColumn[column];
    if (pieceTopRow != null && pieceTopRow < topRow) {
      topRow = pieceTopRow;
    }

    heights[column] = GridComponent.rows - topRow;
  }

  final maxHeight = heights.reduce((a, b) => a > b ? a : b);

  var bumpiness = 0;
  for (var column = 0; column < GridComponent.columns - 1; column++) {
    bumpiness += (heights[column] - heights[column + 1]).abs();
  }

  var holes = 0;
  for (var column = 0; column < GridComponent.columns; column++) {
    var sawOccupiedAbove = false;
    for (var row = 0; row < GridComponent.rows; row++) {
      final isOccupied = landingByColumn[column] == row || !grid.isFree(column, row);
      if (isOccupied) {
        sawOccupiedAbove = true;
      } else if (sawOccupiedAbove) {
        holes++;
      }
    }
  }

  var colorMatches = 0;
  // Il colore del pezzo non è ricavabile da `grid` (le sue celle sono
  // ancora libere finché non si blocca): contiamo invece, più semplicemente,
  // quanti vicini occupati avrebbe ciascun blocco — accostarsi alla pila
  // invece di lasciare colonne isolate è già un buon indizio di una mossa
  // sensata, anche senza conoscere i colori in gioco.
  for (final cell in landingCells) {
    for (final neighbor in [(cell.column - 1, cell.row), (cell.column + 1, cell.row), (cell.column, cell.row + 1)]) {
      if (grid.colorAt(neighbor.$1, neighbor.$2) != null) {
        colorMatches++;
      }
    }
  }

  return -3.0 * maxHeight - 1.0 * bumpiness - 4.0 * holes + 1.5 * colorMatches;
}
