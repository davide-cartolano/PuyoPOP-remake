import 'dart:ui' show Canvas, Offset;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import 'grid_component.dart';
import 'piece_shapes.dart';
import 'playfield_grid.dart';
import 'puyo_component.dart';

/// Il pezzo attualmente controllabile dal giocatore.
///
/// È il "manager" che fa da contenitore per i singoli `PuyoComponent`: li
/// crea secondo una forma scelta a caso (Singolo, Coppia, Triangolo o
/// Tripla dritta) e di un UNICO colore casuale, li muove, li fa cadere
/// con continuità e li ruota tutti insieme — finché non si bloccano,
/// diventando Puyo fermi sulla griglia.
///
/// Da notare: una volta bloccato, questo componente NON viene rimosso
/// dall'albero. Diventa semplicemente inerte (`_isLocked = true`) e resta
/// lì come "contenitore" dei suoi PuyoComponent ormai fermi, che
/// continuano ad essere disegnati esattamente dove sono. La loro presenza
/// nella pila è tracciata altrove, in `playfieldGrid`.
class FallingPiece extends PositionComponent with KeyboardHandler {
  FallingPiece({
    required this.playfieldGrid,
    required this.onLocked,
    required PieceSpec spec,
  })  : _offsets = spec.offsets,
        _color = spec.color,
        super(
          // FallingPiece non disegna nulla di suo: è solo un contenitore
          // logico. Lo posizioniamo all'origine (0,0) — lo stesso sistema
          // di coordinate che GridComponent usa per le celle — così i
          // PuyoComponent figli, che si posizionano in base a colonna/riga
          // ASSOLUTE, risultano allineati senza bisogno di calcoli extra.
          position: Vector2.zero(),
          size: Vector2.zero(),
          anchor: Anchor.topLeft,
        ) {
    _spawnBlocks();
  }

  /// Colonna in cui compare ogni nuovo pezzo: quella centrale (con
  /// arrotondamento per difetto se il numero di colonne è pari), calcolata
  /// a partire da `GridComponent.columns` così resta corretta anche se la
  /// larghezza della griglia cambia.
  ///
  /// È pubblica perché `PuyoGame` deve poterla consultare per controllare,
  /// PRIMA di generare un pezzo, se la cella di spawn è libera: se non lo
  /// è, la pila ha raggiunto il punto in cui i nuovi pezzi compaiono, e la
  /// partita è persa (il classico "game over" dei puzzle game ad incastro).
  static const int spawnColumn = (GridComponent.columns - 1) ~/ 2;

  /// Quanti SECONDI impiega il pezzo ad attraversare un'intera cella,
  /// in condizioni normali e durante il soft drop. Sono gli stessi tempi
  /// dello step precedente: li riusiamo solo per ricavarne una VELOCITÀ
  /// continua (vedi `_currentFallSpeed`), invece di scandire il tempo a
  /// scatti con un timer.
  static const double _normalFallDuration = 0.5;
  static const double _softDropFallDuration = 0.1;

  /// Modello condiviso dei Puyo già bloccati: lo interroghiamo per sapere
  /// se una cella è libera prima di muoverci, cadere o ruotare.
  final PlayfieldGrid playfieldGrid;

  /// Invocata quando il pezzo si blocca. `PuyoGame` la userà per generare
  /// subito il pezzo successivo: è così che otteniamo lo "spawn continuo".
  final void Function() onLocked;

  /// Offset (relativi al pivot) che definiscono la forma corrente. Il
  /// primo elemento è sempre (0, 0): è il blocco pivot, il perno di
  /// rotazione. Viene SOSTITUITO per intero ad ogni rotazione riuscita.
  List<GridOffset> _offsets;

  /// Colore, unico per tutto il pezzo: deciso una volta per tutte da
  /// `PieceSpec`, all'esterno di questa classe (vedi `PuyoGame`), così che
  /// possa essere conosciuto — e mostrato in anteprima — un turno prima
  /// che diventi davvero il pezzo controllabile.
  final Color _color;

  /// Posizione del blocco pivot, in coordinate di griglia ASSOLUTE. La
  /// posizione di ogni altro blocco si ottiene sempre come `pivot + offset`.
  int _pivotColumn = spawnColumn;
  int _pivotRow = 0;

  /// I componenti visivi, uno per offset, nello stesso ordine di `_offsets`.
  final List<PuyoComponent> _blocks = [];

  /// Una volta bloccato, il pezzo ignora sia il game loop sia la tastiera:
  /// è lo stato di "Locking" richiesto.
  bool _isLocked = false;

  bool _isSoftDropping = false;

  /// Colonna corrente del pivot. Esposta in lettura per `AiController`
  /// (vedi `ai_controller.dart`), che deve sapere dove si trova il pezzo
  /// per decidere se spostarlo a sinistra o a destra verso la colonna
  /// scelta dall'AI.
  int get pivotColumn => _pivotColumn;

  /// Offset correnti della forma. Esposti in lettura per `puyo_ai.dart`,
  /// che li usa come punto di partenza per simulare le rotazioni possibili.
  List<GridOffset> get offsets => _offsets;

  /// Vero una volta che il pezzo si è bloccato. `AiController` lo controlla
  /// per sapere quando smettere di pilotarlo.
  bool get isLocked => _isLocked;

  /// Sposta il pezzo di una colonna a sinistra, se possibile. Equivalente,
  /// per un controllore esterno come `AiController`, alla freccia Sinistra.
  void moveLeft() => _tryShiftHorizontally(-1);

  /// Sposta il pezzo di una colonna a destra, se possibile. Equivalente,
  /// per un controllore esterno come `AiController`, alla freccia Destra.
  void moveRight() => _tryShiftHorizontally(1);

  /// Ruota il pezzo di 90° in senso orario, se possibile. Equivalente,
  /// per un controllore esterno come `AiController`, alla freccia Su.
  void rotateClockwise() => _tryRotateClockwise();

  /// Attiva o disattiva la caduta accelerata. `AiController` lo usa al
  /// posto della pressione continua della freccia Giù.
  void setSoftDropping(bool value) {
    _isSoftDropping = value;
  }

  /// Avanzamento CONTINUO della caduta, in pixel, all'interno della riga
  /// corrente (`_pivotRow`): cresce con continuità da 0 a `cellSize`.
  /// La posizione verticale "vera" di ogni blocco è sempre
  /// `riga_logica * cellSize + _fallProgressPixels`. Quando vale 0, il
  /// pezzo è perfettamente allineato alla griglia logica.
  double _fallProgressPixels = 0;

  /// Velocità di caduta corrente, in PIXEL AL SECONDO: la ricaviamo dalla
  /// "durata per cella" con `spazio = velocità × tempo` invertita
  /// (`velocità = cellSize / durata`). È il modo più semplice per passare
  /// da "tempo a scatti" a "velocità continua" mantenendo lo stesso feeling.
  double get _currentFallSpeed {
    final fallDuration = _isSoftDropping ? _softDropFallDuration : _normalFallDuration;
    return GridComponent.cellSize / fallDuration;
  }

  void _spawnBlocks() {
    // Forme monocromatiche: tutti i blocchi del pezzo condividono lo
    // stesso `_color`, deciso una volta per tutte dallo `PieceSpec`
    // ricevuto in costruzione.
    for (final offset in _offsets) {
      final block = PuyoComponent(
        column: _pivotColumn + offset.column,
        row: _pivotRow + offset.row,
        color: _color,
      );
      _blocks.add(block);
      add(block);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (_isLocked) return;
    _renderGhost(canvas);
  }

  /// Disegna, nella colonna/righe in cui il pezzo atterrerebbe se lo si
  /// lasciasse cadere subito, una versione semitrasparente dei suoi
  /// blocchi (`paintPuyoGhost`) — il classico "ghost piece" che aiuta a
  /// pianificare la mossa senza dover indovinare a occhio dove andrà a
  /// finire.
  void _renderGhost(Canvas canvas) {
    final ghostPivotRow = _computeGhostPivotRow();
    if (ghostPivotRow == _pivotRow) {
      // Il pezzo è già praticamente atterrato: un fantasma sovrapposto al
      // pezzo vero non aggiungerebbe alcuna informazione.
      return;
    }

    const padding = 4.0;
    final radius = (GridComponent.cellSize - padding * 2) / 2;

    for (final offset in _offsets) {
      final column = _pivotColumn + offset.column;
      final row = ghostPivotRow + offset.row;
      final center = Offset(
        column * GridComponent.cellSize + GridComponent.cellSize / 2,
        row * GridComponent.cellSize + GridComponent.cellSize / 2,
      );
      paintPuyoGhost(canvas, center: center, radius: radius, color: _color);
    }
  }

  /// Simula la caduta libera del pezzo, partendo dalla riga del pivot
  /// CORRENTE, finché non trova la prima riga in cui non potrebbe più
  /// scendere: è esattamente la stessa regola di `_canPlace` usata per la
  /// caduta vera, solo applicata in anticipo e senza muovere nulla.
  int _computeGhostPivotRow() {
    var candidateRow = _pivotRow;
    while (_canPlace(pivotColumn: _pivotColumn, pivotRow: candidateRow + 1, offsets: _offsets)) {
      candidateRow++;
    }
    return candidateRow;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_isLocked) return;

    // Controlliamo PRIMA se la riga sottostante è libera: così il pezzo
    // non "intravede" mai visivamente una cella occupata. Se non c'è
    // spazio, il pezzo ha toccato terra qui, in questo preciso istante.
    final canEnterRowBelow = _canPlace(
      pivotColumn: _pivotColumn,
      pivotRow: _pivotRow + 1,
      offsets: _offsets,
    );

    if (!canEnterRowBelow) {
      // Grid Snapping: azzeriamo l'avanzamento frazionario residuo, il che
      // forza la posizione verticale a `riga_logica * cellSize`, cioè
      // perfettamente allineata alla griglia — poi blocchiamo il pezzo lì.
      _fallProgressPixels = 0;
      _syncBlocksWithGrid();
      _lock();
      return;
    }

    // Caduta fluida: niente più "scatti" temporizzati, solo
    // `spazio percorso = velocità × tempo trascorso` ad ogni frame.
    _fallProgressPixels += _currentFallSpeed * dt;

    if (_fallProgressPixels >= GridComponent.cellSize) {
      // Una cella intera è stata attraversata visivamente: "commitiamo"
      // l'avanzamento sulla riga logica successiva, riportando il residuo
      // sotto la soglia. Sottraendo (anziché azzerando) preserviamo
      // l'eventuale eccesso, così la velocità media resta corretta anche
      // con frame rate variabili — la stessa tecnica già vista nello step
      // della "gravità a scatti".
      _pivotRow++;
      _fallProgressPixels -= GridComponent.cellSize;
    }

    _syncBlocksWithGrid();
  }

  /// "Congela" il pezzo e lo scompone (stato di Locking):
  /// 1. smette di rispondere a game loop e tastiera;
  /// 2. ogni blocco viene reso un Puyo INDIPENDENTE: registrato a sé
  ///    stante in `playfieldGrid` (non più come "membro di un pezzo", ma
  ///    come singola cella occupata) e staccato da `FallingPiece` per
  ///    diventare figlio diretto della griglia — proprio come avviene in
  ///    Puyo Puyo, dove un pezzo che tocca terra si separa nei singoli
  ///    elementi che lo componevano, ognuno libero di cadere per conto
  ///    proprio se sotto di lui resta spazio vuoto;
  /// 3. il contenitore ormai vuoto (`this`) viene rimosso dall'albero:
  ///    non ha più nulla da disegnare né da gestire;
  /// 4. avvisa `PuyoGame` tramite `onLocked`, che si occuperà di applicare
  ///    la gravità globale, far scoppiare eventuali gruppi e — quando la
  ///    griglia sarà stabile — generare il pezzo successivo.
  void _lock() {
    _isLocked = true;
    _isSoftDropping = false;

    final grid = parent;
    for (final block in _blocks) {
      playfieldGrid.lock(block);
      block.removeFromParent();
      grid?.add(block);
      // Tocco cosmetico: un piccolo "schiacciamento" elastico al momento
      // dell'atterraggio, invece del passaggio istantaneo e immobile da
      // pezzo controllabile a Puyo fermo.
      block.playLandSquashEffect();
    }
    _blocks.clear();

    removeFromParent();
    onLocked();
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Stato di Locking: niente più input una volta bloccato.
    if (_isLocked) return false;

    // Soft drop: stato continuo, segue semplicemente se la freccia Giù è
    // premuta in questo istante (si veda lo step precedente per i dettagli).
    _isSoftDropping = keysPressed.contains(LogicalKeyboardKey.arrowDown);

    // Movimento orizzontale e rotazione: azioni "a scatto", quindi
    // reagiamo al solo fronte di discesa della pressione (KeyDownEvent),
    // non al key-repeat del sistema operativo.
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _tryShiftHorizontally(-1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _tryShiftHorizontally(1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _tryRotateClockwise();
      }
    }

    return true;
  }

  /// Sposta l'intero pezzo di `columnDelta` colonne (-1 sinistra, +1
  /// destra) SOLO se ogni blocco atterrerebbe in una cella libera. Lo
  /// stesso identico controllo di `_stepDown` ci garantisce, in un colpo
  /// solo, sia i limiti laterali della griglia (Boundaries) sia
  /// l'impossibilità di sovrapporsi a Puyo già bloccati.
  void _tryShiftHorizontally(int columnDelta) {
    final targetColumn = _pivotColumn + columnDelta;
    final canShift = _canPlace(
      pivotColumn: targetColumn,
      pivotRow: _pivotRow,
      offsets: _offsets,
    );

    if (canShift) {
      _pivotColumn = targetColumn;
      _syncBlocksWithGrid();
    }
    // Se `canShift` è falso, l'input viene semplicemente ignorato: è
    // esattamente il comportamento richiesto ai bordi della griglia.
  }

  /// Ruota il pezzo di 90° in senso orario attorno al blocco pivot.
  ///
  /// Prova, in ordine:
  /// 1. la rotazione "sul posto" (il pivot resta dov'è);
  /// 2. un Wall Kick di base: se la rotazione sul posto andrebbe a
  ///    sbattere contro un bordo laterale (o contro un Puyo bloccato lì
  ///    vicino), proviamo a traslare l'intero pezzo di una colonna verso
  ///    l'interno della griglia e a ruotare in quella nuova posizione —
  ///    è ciò che, in molti puzzle game, permette di ruotare un pezzo
  ///    anche quando è incollato al muro.
  ///
  /// Se nemmeno il wall kick funziona, la rotazione viene semplicemente
  /// ignorata: il pezzo resta come prima. Questo realizza, nel caso più
  /// estremo, anche il secondo comportamento richiesto ("impedimento
  /// della rotazione vicino al bordo").
  void _tryRotateClockwise() {
    final rotatedOffsets = [
      for (final offset in _offsets) offset.rotatedClockwise(),
    ];

    if (_canPlace(pivotColumn: _pivotColumn, pivotRow: _pivotRow, offsets: rotatedOffsets)) {
      _applyRotation(rotatedOffsets, newPivotColumn: _pivotColumn);
      return;
    }

    for (final columnShift in const [-1, 1]) {
      final shiftedColumn = _pivotColumn + columnShift;
      final fits = _canPlace(
        pivotColumn: shiftedColumn,
        pivotRow: _pivotRow,
        offsets: rotatedOffsets,
      );
      if (fits) {
        _applyRotation(rotatedOffsets, newPivotColumn: shiftedColumn);
        return;
      }
    }

    // Né la rotazione sul posto né il wall kick sono validi: ignoriamo
    // l'input e lasciamo il pezzo esattamente dov'era.
  }

  void _applyRotation(List<GridOffset> newOffsets, {required int newPivotColumn}) {
    _offsets = newOffsets;
    _pivotColumn = newPivotColumn;
    _syncBlocksWithGrid();
  }

  /// Vero se OGNI blocco della forma — posizionato con il pivot in
  /// (pivotColumn, pivotRow) e gli `offsets` indicati — cadrebbe in una
  /// cella libera e dentro ai confini della griglia.
  ///
  /// Centralizzando qui il controllo, lo stesso identico metodo risponde
  /// a tre domande diverse — "posso cadere?", "posso spostarmi di lato?",
  /// "posso ruotare?" — semplicemente passandogli pivot e offset candidati
  /// differenti. Una sola fonte di verità per tutte le collisioni.
  bool _canPlace({
    required int pivotColumn,
    required int pivotRow,
    required List<GridOffset> offsets,
  }) {
    for (final offset in offsets) {
      final column = pivotColumn + offset.column;
      final row = pivotRow + offset.row;
      if (!playfieldGrid.isFree(column, row)) {
        return false;
      }
    }
    return true;
  }

  /// Riallinea ogni PuyoComponent figlio alla cella che gli compete
  /// (`pivot + proprio offset`), dopo uno spostamento, una caduta o una
  /// rotazione — propagando anche `_fallProgressPixels`, l'avanzamento
  /// continuo della discesa. I PuyoComponent restano "ignoranti": ricevono
  /// solo le coordinate (logiche + il piccolo offset visivo) e si
  /// ridisegnano di conseguenza.
  ///
  /// Nota: spostamenti laterali e rotazioni NON azzerano
  /// `_fallProgressPixels` — la caduta continua a scorrere senza
  /// interruzioni "sotto" a quei movimenti, esattamente come ci si
  /// aspetterebbe da un pezzo che cade fluido mentre lo si guida di lato.
  void _syncBlocksWithGrid() {
    for (var i = 0; i < _blocks.length; i++) {
      final offset = _offsets[i];
      _blocks[i].moveTo(
        _pivotColumn + offset.column,
        _pivotRow + offset.row,
        verticalOffset: _fallProgressPixels,
      );
    }
  }
}
