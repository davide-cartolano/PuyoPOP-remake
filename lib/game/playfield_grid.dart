import 'grid_component.dart';
import 'puyo_component.dart';

/// Tiene traccia di quali celle della griglia sono occupate da Puyo ormai
/// "bloccati" (fermi sul fondo o impilati sopra ad altri Puyo).
///
/// È pura logica/stato — non disegna nulla — e fa da "fonte di verità"
/// condivisa fra:
/// - `FallingPiece`, che la consulta per sapere se può muoversi, cadere o
///   ruotare senza sovrapporsi a Puyo già fermi o uscire dai bordi;
/// - `PuyoGame`, che vi registra i blocchi nel momento in cui un pezzo
///   tocca terra e si blocca.
///
/// Questa separazione è ciò che ci permette di distinguere "il pezzo
/// controllabile" (logica viva, in `FallingPiece`) da "i Puyo a riposo"
/// (semplice stato, qui dentro).
class PlayfieldGrid {
  PlayfieldGrid()
      : _cells = List.generate(
          GridComponent.rows,
          (_) => List<PuyoComponent?>.filled(GridComponent.columns, null),
          growable: false,
        );

  /// Quanti Puyo dello stesso colore, collegati fra loro, servono perché
  /// un gruppo "scoppi". Tenerlo qui, come costante nominata, rende
  /// immediato cambiarlo in futuro (es. per una modalità di difficoltà
  /// diversa) senza andare a caccia del "4" nel codice.
  static const int _minGroupSizeToClear = 5;

  /// Le quattro direzioni in cui due Puyo si considerano "adiacenti":
  /// sopra, sotto, sinistra, destra — MAI in diagonale. Ogni elemento è
  /// una coppia (deltaRiga, deltaColonna) da sommare a una cella di
  /// partenza per ottenere quella vicina.
  static const _adjacentOffsets = <(int deltaRow, int deltaColumn)>[
    (-1, 0),
    (1, 0),
    (0, -1),
    (0, 1),
  ];

  /// Matrice [riga][colonna]: `null` significa "cella libera", altrimenti
  /// contiene il PuyoComponent ormai fermo che occupa quella cella.
  final List<List<PuyoComponent?>> _cells;

  /// Vero se (column, row) ricade dentro ai confini della griglia.
  bool isInsideBounds(int column, int row) {
    return column >= 0 &&
        column < GridComponent.columns &&
        row >= 0 &&
        row < GridComponent.rows;
  }

  /// Vero se la cella è dentro la griglia E non è occupata da un Puyo
  /// già bloccato.
  ///
  /// Un solo controllo copre sia i "muri" della griglia sia le collisioni
  /// con la pila di Puyo fermi: è esattamente ciò che serve a
  /// `FallingPiece` per validare in un colpo solo ogni movimento, caduta
  /// o rotazione.
  bool isFree(int column, int row) {
    return isInsideBounds(column, row) && _cells[row][column] == null;
  }

  /// Registra un Puyo come "bloccato" nella sua cella corrente
  /// (`puyo.column`, `puyo.row`). Da questo momento in poi, `isFree` per
  /// quella cella restituirà `false`.
  void lock(PuyoComponent puyo) {
    _cells[puyo.row][puyo.column] = puyo;
  }

  /// Cerca tutti i gruppi di Puyo dello stesso colore, collegati in
  /// orizzontale e/o verticale (NON in diagonale), abbastanza grandi da
  /// "scoppiare" (almeno `_minGroupSizeToClear` elementi).
  ///
  /// Scandisce ogni cella della griglia una sola volta: se non è ancora
  /// stata assegnata a un gruppo, la usa come "seme" per un flood fill
  /// (`_collectGroup`) che raccoglie tutti i Puyo dello stesso colore
  /// raggiungibili da lì. È il classico algoritmo di ricerca delle
  /// "componenti connesse" applicato a una griglia colorata.
  List<List<PuyoComponent>> findGroupsToClear() {
    final visited = List.generate(
      GridComponent.rows,
      (_) => List<bool>.filled(GridComponent.columns, false),
    );

    final groupsToClear = <List<PuyoComponent>>[];

    for (var row = 0; row < GridComponent.rows; row++) {
      for (var column = 0; column < GridComponent.columns; column++) {
        if (visited[row][column] || _cells[row][column] == null) {
          continue;
        }

        final group = _collectGroup(row, column, visited);
        if (group.length >= _minGroupSizeToClear) {
          groupsToClear.add(group);
        }
      }
    }

    return groupsToClear;
  }

  /// Flood fill a partire dalla cella (`startRow`, `startColumn`): raccoglie
  /// tutti i Puyo dello stesso colore di quello di partenza, raggiungibili
  /// muovendosi un passo alla volta in una delle quattro direzioni cardinali.
  ///
  /// `visited` è condivisa fra tutte le chiamate di `findGroupsToClear`:
  /// segniamo una cella come visitata SOLO quando la includiamo in un
  /// gruppo (o scopriamo che è vuota). Una cella di colore diverso, invece,
  /// NON viene segnata qui: resterà libera di diventare il seme del
  /// proprio gruppo quando il ciclo principale la raggiungerà.
  List<PuyoComponent> _collectGroup(
    int startRow,
    int startColumn,
    List<List<bool>> visited,
  ) {
    final targetColor = _cells[startRow][startColumn]!.color;

    final group = <PuyoComponent>[];
    final pending = <(int row, int column)>[(startRow, startColumn)];

    while (pending.isNotEmpty) {
      final (row, column) = pending.removeLast();
      if (visited[row][column]) {
        continue;
      }

      final puyo = _cells[row][column];
      if (puyo == null) {
        visited[row][column] = true;
        continue;
      }
      if (puyo.color != targetColor) {
        // Colore diverso: appartiene a un (potenziale) altro gruppo.
        // La lasciamo non visitata apposta, per il motivo spiegato sopra.
        continue;
      }

      visited[row][column] = true;
      group.add(puyo);

      for (final (deltaRow, deltaColumn) in _adjacentOffsets) {
        final neighborRow = row + deltaRow;
        final neighborColumn = column + deltaColumn;
        if (isInsideBounds(neighborColumn, neighborRow) &&
            !visited[neighborRow][neighborColumn]) {
          pending.add((neighborRow, neighborColumn));
        }
      }
    }

    return group;
  }

  /// Rimuove dalla griglia LOGICA i Puyo del gruppo indicato: le loro
  /// celle tornano libere (`null`).
  ///
  /// Non tocca l'albero grafico di Flame — rimuovere visivamente i
  /// `PuyoComponent` (`removeFromParent`) spetta a chi orchestra il gioco
  /// (`PuyoGame`), che ha la visione d'insieme; questa classe resta pura
  /// logica/stato, come da sua natura.
  void clear(List<PuyoComponent> group) {
    for (final puyo in group) {
      _cells[puyo.row][puyo.column] = null;
    }
  }

  /// Fa "cadere" ogni Puyo rimasto sulla griglia fino alla cella libera
  /// più in basso disponibile nella sua colonna — la "gravità globale":
  /// non riguarda solo i Puyo appena bloccati, ma chiunque abbia una
  /// cella vuota sotto di sé (es. un pezzo a "L" il cui braccio resta
  /// sospeso nel vuoto una volta separatosi nei singoli Puyo, o una pila
  /// che si apre dopo uno scoppio).
  ///
  /// Per ogni colonna, scorriamo dal basso verso l'alto tenendo un
  /// "puntatore di scrittura" sulla prossima cella libera più in basso:
  /// è la classica tecnica di compattazione "in place" (la stessa idea
  /// con cui si rimuovono gli elementi nulli da un array mantenendo
  /// l'ordine relativo di quelli rimasti).
  ///
  /// Aggiorna SUBITO lo stato logico (`_cells` e `puyo.row`) di ogni Puyo
  /// spostato, ma NON lo sposta visivamente: lascia che sia chi orchestra
  /// il gioco (`PuyoGame`) ad animarne la discesa — tramite il Future
  /// restituito da `PuyoComponent.fallTo` — e a decidere quando, in base
  /// a quell'animazione, è il momento di proseguire. Per questo restituisce
  /// l'elenco dei Puyo effettivamente spostati: sono gli unici da animare.
  List<PuyoComponent> applyGravity() {
    final movedPuyos = <PuyoComponent>[];

    for (var column = 0; column < GridComponent.columns; column++) {
      var writeRow = GridComponent.rows - 1;

      for (var readRow = GridComponent.rows - 1; readRow >= 0; readRow--) {
        final puyo = _cells[readRow][column];
        if (puyo == null) {
          continue;
        }

        if (readRow != writeRow) {
          _cells[writeRow][column] = puyo;
          _cells[readRow][column] = null;
          puyo.row = writeRow;
          movedPuyos.add(puyo);
        }

        writeRow--;
      }
    }

    return movedPuyos;
  }
}
