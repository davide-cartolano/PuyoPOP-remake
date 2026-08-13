import 'dart:math';

import 'package:flutter/material.dart' show Color;

import 'grid_component.dart';
import 'piece_shapes.dart';
import 'playfield_grid.dart';

/// Le tre difficoltà della CPU, ognuna con i propri parametri di
/// comportamento: quanto in fretta esegue le mosse, quanto spesso
/// "sbaglia" di proposito, e quanto pesa la ricerca delle catene
/// nella valutazione delle mosse.
enum AiDifficulty {
  easy(
    label: 'Facile',
    actionInterval: 0.32,
    mistakeChance: 0.30,
    chainWeight: 0.0,
    buildWeight: 0.4,
    noise: 4.0,
  ),
  normal(
    label: 'Normale',
    actionInterval: 0.16,
    mistakeChance: 0.08,
    chainWeight: 40.0,
    buildWeight: 1.2,
    noise: 1.0,
  ),
  hard(
    label: 'Difficile',
    actionInterval: 0.07,
    mistakeChance: 0.0,
    chainWeight: 120.0,
    buildWeight: 2.0,
    noise: 0.0,
  );

  const AiDifficulty({
    required this.label,
    required this.actionInterval,
    required this.mistakeChance,
    required this.chainWeight,
    required this.buildWeight,
    required this.noise,
  });

  /// Nome mostrato nel menu di selezione.
  final String label;

  /// Secondi fra un'azione della CPU e la successiva: più basso = più veloce.
  final double actionInterval;

  /// Probabilità che la CPU scelga una mossa a caso invece della migliore.
  final double mistakeChance;

  /// Quanto vale, nel punteggio euristico, ogni anello di catena che la
  /// mossa innescherebbe subito (simulato con `_simulateChains`).
  final double chainWeight;

  /// Quanto vale accostare Puyo dello stesso colore SENZA farli scoppiare
  /// subito: è ciò che spinge la CPU a "costruire" catene future.
  final double buildWeight;

  /// Ampiezza del rumore casuale aggiunto al punteggio di ogni mossa:
  /// rende la CPU facile meno deterministica (e meno precisa).
  final double noise;
}

/// Mossa decisa dall'AI per il pezzo corrente: quante rotazioni in senso
/// orario applicare (0-3) e in quale colonna pivot lasciarlo cadere.
class AiMove {
  const AiMove({required this.rotations, required this.targetColumn});

  final int rotations;
  final int targetColumn;
}

/// Decide la mossa per il pezzo corrente (forma `currentOffsets`, colore
/// unico `pieceColor`) secondo la difficoltà scelta.
///
/// Per ogni combinazione rotazione×colonna simula il piazzamento su una
/// copia "a colori" della griglia: applica la gravità, fa scoppiare i
/// gruppi da 4+ e conta gli anelli di catena risultanti — è questa
/// simulazione, assente nella prima versione dell'AI, a permettere alla
/// CPU difficile di cercare (e costruire) vere combo invece di limitarsi
/// a tenere bassa la pila.
AiMove decideBestMove(
  PlayfieldGrid grid,
  List<GridOffset> currentOffsets,
  Color pieceColor,
  AiDifficulty difficulty,
  Random random,
) {
  final candidates = <({AiMove move, double score})>[];

  var rotatedOffsets = currentOffsets;
  for (var rotations = 0; rotations < 4; rotations++) {
    if (rotations > 0) {
      rotatedOffsets = [for (final offset in rotatedOffsets) offset.rotatedClockwise()];
    }

    final columns = rotatedOffsets.map((offset) => offset.column);
    final minColumnOffset = columns.reduce(min);
    final maxColumnOffset = columns.reduce(max);

    final firstColumn = -minColumnOffset;
    final lastColumn = GridComponent.columns - 1 - maxColumnOffset;

    for (var pivotColumn = firstColumn; pivotColumn <= lastColumn; pivotColumn++) {
      final landingRow = _computeLandingRow(grid, pivotColumn, rotatedOffsets);
      if (landingRow == null) continue;

      var score = _scorePlacement(
        grid,
        pivotColumn,
        landingRow,
        rotatedOffsets,
        pieceColor,
        difficulty,
      );
      if (difficulty.noise > 0) {
        score += (random.nextDouble() * 2 - 1) * difficulty.noise;
      }

      candidates.add((move: AiMove(rotations: rotations, targetColumn: pivotColumn), score: score));
    }
  }

  if (candidates.isEmpty) {
    // Nessuna colonna percorribile (pila già al massimo): restiamo fermi,
    // il game over verrà rilevato altrove.
    return const AiMove(rotations: 0, targetColumn: 0);
  }

  // "Errore" volontario: con probabilità `mistakeChance` la CPU sceglie
  // una mossa qualunque invece della migliore — è ciò che rende battibile
  // la difficoltà facile senza dover azzoppare l'euristica.
  if (random.nextDouble() < difficulty.mistakeChance) {
    return candidates[random.nextInt(candidates.length)].move;
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.move;
}

/// Vero se ogni blocco della forma, con il pivot in (pivotColumn, pivotRow),
/// cadrebbe in una cella libera. Le righe sopra alla griglia (row < 0) sono
/// considerate libere per definizione: è lì che un pezzo "emerge" prima di
/// entrare nell'area di gioco vera e propria.
bool _canPlaceAt(PlayfieldGrid grid, int pivotColumn, int pivotRow, List<GridOffset> offsets) {
  for (final offset in offsets) {
    final column = pivotColumn + offset.column;
    final row = pivotRow + offset.row;
    if (column < 0 || column >= GridComponent.columns) return false;
    if (row < 0) continue;
    if (row >= GridComponent.rows) return false;
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

/// Cella della griglia simulata: colore (o null se vuota) + flag
/// spazzatura. La spazzatura, come nel gioco vero, non forma mai gruppi:
/// nella simulazione la trattiamo come un semplice blocco inerte.
class _SimCell {
  _SimCell(this.color, this.isGarbage);

  final Color? color;
  final bool isGarbage;
}

/// Copia lo stato attuale della griglia in una matrice di colori su cui
/// poter simulare liberamente (piazzamenti, gravità, scoppi) senza toccare
/// la partita vera.
List<List<_SimCell?>> _snapshotBoard(PlayfieldGrid grid) {
  return [
    for (var row = 0; row < GridComponent.rows; row++)
      [
        for (var column = 0; column < GridComponent.columns; column++)
          () {
            final puyo = grid.puyoAt(column, row);
            if (puyo == null) return null;
            return _SimCell(puyo.color, puyo.isGarbage);
          }(),
      ],
  ];
}

/// Compatta ogni colonna verso il basso (gravità), come
/// `PlayfieldGrid.applyGravity` ma sulla griglia simulata.
void _simApplyGravity(List<List<_SimCell?>> board) {
  for (var column = 0; column < GridComponent.columns; column++) {
    var writeRow = GridComponent.rows - 1;
    for (var readRow = GridComponent.rows - 1; readRow >= 0; readRow--) {
      final cell = board[readRow][column];
      if (cell == null) continue;
      if (readRow != writeRow) {
        board[writeRow][column] = cell;
        board[readRow][column] = null;
      }
      writeRow--;
    }
  }
}

const _adjacentOffsets = <(int deltaRow, int deltaColumn)>[(-1, 0), (1, 0), (0, -1), (0, 1)];

/// Simula, sulla griglia copiata, l'intero ciclo scoppi→gravità→scoppi
/// del gioco vero, restituendo il numero totale di anelli di catena e di
/// Puyo eliminati: è il cuore della nuova AI, ciò che le permette di
/// riconoscere le mosse che innescano combo.
({int chains, int cleared}) _simulateChains(List<List<_SimCell?>> board) {
  var chains = 0;
  var cleared = 0;

  while (true) {
    final visited = List.generate(GridComponent.rows, (_) => List<bool>.filled(GridComponent.columns, false));
    final groups = <List<(int, int)>>[];

    for (var row = 0; row < GridComponent.rows; row++) {
      for (var column = 0; column < GridComponent.columns; column++) {
        final cell = board[row][column];
        if (visited[row][column] || cell == null || cell.isGarbage) continue;

        // Flood fill dello stesso colore.
        final group = <(int, int)>[];
        final pending = [(row, column)];
        while (pending.isNotEmpty) {
          final (r, c) = pending.removeLast();
          if (visited[r][c]) continue;
          final other = board[r][c];
          if (other == null || other.isGarbage || other.color != cell.color) continue;
          visited[r][c] = true;
          group.add((r, c));
          for (final (dr, dc) in _adjacentOffsets) {
            final nr = r + dr;
            final nc = c + dc;
            if (nr >= 0 && nr < GridComponent.rows && nc >= 0 && nc < GridComponent.columns && !visited[nr][nc]) {
              pending.add((nr, nc));
            }
          }
        }

        if (group.length >= PlayfieldGrid.minGroupSizeToClear) {
          groups.add(group);
        }
      }
    }

    if (groups.isEmpty) break;

    chains += groups.length;
    for (final group in groups) {
      cleared += group.length;
      for (final (r, c) in group) {
        board[r][c] = null;
        // La spazzatura adiacente scompare insieme al gruppo, come nel gioco vero.
        for (final (dr, dc) in _adjacentOffsets) {
          final nr = r + dr;
          final nc = c + dc;
          if (nr >= 0 && nr < GridComponent.rows && nc >= 0 && nc < GridComponent.columns) {
            final neighbor = board[nr][nc];
            if (neighbor != null && neighbor.isGarbage) {
              board[nr][nc] = null;
            }
          }
        }
      }
    }

    _simApplyGravity(board);
  }

  return (chains: chains, cleared: cleared);
}

/// Punteggio euristico di una mossa: combina la simulazione delle catene
/// (quanto scoppierebbe subito), il "potenziale" costruito (vicini dello
/// stesso colore che NON scoppiano ancora) e le classiche penalità di
/// altezza, dislivello e buchi.
double _scorePlacement(
  PlayfieldGrid grid,
  int pivotColumn,
  int pivotRow,
  List<GridOffset> offsets,
  Color pieceColor,
  AiDifficulty difficulty,
) {
  final board = _snapshotBoard(grid);
  for (final offset in offsets) {
    final row = pivotRow + offset.row;
    final column = pivotColumn + offset.column;
    if (row >= 0 && row < GridComponent.rows) {
      board[row][column] = _SimCell(pieceColor, false);
    }
  }
  _simApplyGravity(board);

  // Potenziale di costruzione PRIMA degli scoppi: quanti vicini dello
  // stesso colore ha ciascun blocco appena piazzato.
  var sameColorNeighbors = 0;
  for (var row = 0; row < GridComponent.rows; row++) {
    for (var column = 0; column < GridComponent.columns; column++) {
      final cell = board[row][column];
      if (cell == null || cell.isGarbage) continue;
      for (final (dr, dc) in const [(0, 1), (1, 0)]) {
        final nr = row + dr;
        final nc = column + dc;
        if (nr < GridComponent.rows && nc < GridComponent.columns) {
          final neighbor = board[nr][nc];
          if (neighbor != null && !neighbor.isGarbage && neighbor.color == cell.color) {
            sameColorNeighbors++;
          }
        }
      }
    }
  }

  final result = _simulateChains(board);

  // Metriche di "forma" della pila DOPO gli scoppi simulati.
  final heights = List<int>.filled(GridComponent.columns, 0);
  var holes = 0;
  for (var column = 0; column < GridComponent.columns; column++) {
    var sawOccupied = false;
    for (var row = 0; row < GridComponent.rows; row++) {
      final occupied = board[row][column] != null;
      if (occupied && !sawOccupied) {
        sawOccupied = true;
        heights[column] = GridComponent.rows - row;
      } else if (!occupied && sawOccupied) {
        holes++;
      }
    }
  }

  final maxHeight = heights.reduce(max);
  var bumpiness = 0;
  for (var column = 0; column < GridComponent.columns - 1; column++) {
    bumpiness += (heights[column] - heights[column + 1]).abs();
  }

  // Una catena lunga vale quadraticamente di più di scoppi isolati: è ciò
  // che spinge la difficoltà alta a preparare combo invece di far
  // scoppiare subito ogni gruppetto.
  final chainScore = result.chains * result.chains * difficulty.chainWeight + result.cleared * 2.0;

  // Se la pila è pericolosamente alta, sopravvivere conta più di costruire.
  final panicPenalty = maxHeight >= GridComponent.rows - 4 ? maxHeight * 6.0 : 0.0;

  return chainScore +
      sameColorNeighbors * difficulty.buildWeight -
      2.0 * maxHeight -
      0.8 * bumpiness -
      5.0 * holes -
      panicPenalty;
}
