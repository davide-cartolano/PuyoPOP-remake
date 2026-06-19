import 'dart:math';

import 'package:flame/components.dart' show TextComponent, TextPaint;
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/material.dart' show Colors, TextStyle;

import 'falling_piece.dart';
import 'grid_component.dart';
import 'next_piece_preview.dart';
import 'piece_shapes.dart';
import 'playfield_grid.dart';

/// Classe principale del gioco. Estendere FlameGame ci dà accesso al
/// game loop di Flame (update/render automatici), al sistema di componenti
/// e alla gestione delle dimensioni dello schermo.
/// Il mixin `HasKeyboardHandlerComponents` dice a Flame: "questo gioco
/// riceve eventi da tastiera e deve inoltrarli ai componenti figli che
/// implementano `KeyboardHandler`" (come il nostro FallingPiece).
/// Senza questo mixin, gli eventi tastiera non arriverebbero ai componenti.
class PuyoGame extends FlameGame with HasKeyboardHandlerComponents {
  PuyoGame({required this.onGameOver});

  /// Invocata quando la partita finisce (pila arrivata fino alla cella di
  /// spawn). `PuyoGame` è puro Flame/Dart e non ha un `BuildContext`: è
  /// `GameScreen` — che lo possiede — a passarci questa callback, e a
  /// occuparsi di mostrare il messaggio a schermo e tornare al menu.
  final VoidCallback onGameOver;

  // Creiamo subito l'istanza (non in onLoad): Flame può chiamare
  // onGameResize prima che onLoad termini, e a quel punto questo campo
  // deve già esistere per evitare un LateInitializationError.
  final GridComponent _grid = GridComponent();

  /// Testo del punteggio, disegnato a lato della griglia. Lo creiamo già
  /// con il suo contenuto iniziale: lo aggiorneremo in seguito chiamando
  /// `_addScore`, che si limita a cambiarne la stringa `text`.
  final TextComponent _scoreText = TextComponent(
    text: 'Score: 0',
    textRenderer: TextPaint(
      style: const TextStyle(color: Colors.white, fontSize: 24),
    ),
  );

  /// Etichetta sopra il riquadro di anteprima del prossimo pezzo.
  final TextComponent _nextPieceLabel = TextComponent(
    text: 'Next',
    textRenderer: TextPaint(
      style: const TextStyle(color: Colors.white, fontSize: 20),
    ),
  );

  /// Riquadro che mostra il prossimo pezzo, a lato della griglia.
  final NextPiecePreviewComponent _nextPiecePreview = NextPiecePreviewComponent();

  /// Punteggio corrente della partita.
  int _score = 0;

  /// Vero dal momento in cui la partita finisce. Ci serve per non
  /// innescare il game over più volte (es. se più frame rilevassero la
  /// condizione prima che il motore venga effettivamente messo in pausa).
  bool _isGameOver = false;

  /// Modello condiviso dei Puyo già bloccati sulla griglia. Lo creiamo una
  /// sola volta per partita e lo passiamo ad ogni FallingPiece generato:
  /// è così che pezzi diversi "vedono" lo stesso stato della pila.
  late final PlayfieldGrid _playfieldGrid;

  /// Un'unica sorgente di numeri casuali per tutta la partita, condivisa
  /// fra tutti i pezzi generati (forma e colori).
  final Random _random = Random();

  /// Forma e colore del pezzo che apparirà DOPO quello attualmente in
  /// gioco — generati un turno in anticipo proprio per poterli mostrare
  /// nel riquadro di anteprima prima ancora che diventino il pezzo
  /// controllabile.
  late PieceSpec _nextSpec;

  @override
  Future<void> onLoad() async {
    super.onLoad();

    await add(_grid);
    await add(_scoreText);
    await add(_nextPieceLabel);
    await add(_nextPiecePreview);
    _layoutHud();

    _playfieldGrid = PlayfieldGrid();

    // Decidiamo subito il primo "prossimo pezzo" e lo mostriamo in
    // anteprima: `_spawnNewPiece` lo trasformerà nel pezzo controllabile
    // alla sua prima chiamata.
    _nextSpec = generatePieceSpec(_random);
    _nextPiecePreview.updatePiece(_nextSpec);

    // Avvio dello "spawn continuo": generiamo subito il primo pezzo. Ogni
    // pezzo, quando si blocca, chiamerà a sua volta `_spawnNewPiece` (è
    // la callback `onLocked` che gli passiamo), generando il successivo.
    _spawnNewPiece();
  }

  /// Crea un nuovo pezzo controllabile (`FallingPiece`) e lo aggiunge al
  /// gioco come FIGLIO della griglia — esattamente come facevamo con il
  /// PuyoComponent dello step precedente: in questo modo eredita il
  /// sistema di coordinate locale di GridComponent (origine in alto a
  /// sinistra, celle di `cellSize` pixel), e i Puyo al suo interno
  /// risultano allineati senza calcoli aggiuntivi.
  ///
  /// PRIMA di generarlo, però, controlliamo che la sua cella di spawn
  /// (colonna centrale, riga più in alto) sia libera: se la pila di Puyo
  /// bloccati è arrivata fin lì, non c'è più spazio per un nuovo pezzo —
  /// è la condizione classica di "game over" nei puzzle game ad incastro.
  void _spawnNewPiece() {
    final spawnCellIsFree = _playfieldGrid.isFree(FallingPiece.spawnColumn, 0);
    if (!spawnCellIsFree) {
      _triggerGameOver();
      return;
    }

    // Il pezzo che stava in anteprima diventa quello controllabile, e ne
    // generiamo subito un altro per l'anteprima successiva: è così che
    // il riquadro a lato della griglia mostra sempre, con un turno di
    // anticipo, cosa arriverà dopo.
    final spec = _nextSpec;
    _nextSpec = generatePieceSpec(_random);
    _nextPiecePreview.updatePiece(_nextSpec);

    _grid.add(
      FallingPiece(
        playfieldGrid: _playfieldGrid,
        onLocked: _resolveBoardThenSpawnNext,
        spec: spec,
      ),
    );
  }

  /// Risolve la griglia dopo che un pezzo si è bloccato e separato nei
  /// singoli Puyo indipendenti.
  ///
  /// È qui che alterniamo, in un ciclo, le due fasi richieste:
  /// "caduta per gravità" e "verifica degli scoppi" — finché un giro
  /// completo non trova più nulla da eliminare, cioè la griglia è
  /// STABILE. Questa alternanza è, di per sé, l'intero meccanismo delle
  /// reazioni a catena (combo): ogni scoppio può aprire un vuoto sotto
  /// ad altri Puyo, la gravità li fa scendere, e quella discesa può
  /// formare un nuovo gruppo da 4+ — che il giro successivo del ciclo
  /// scoprirà e farà scoppiare a sua volta, con un `chainNumber` più alto.
  ///
  /// È una funzione `async`: ogni fase di caduta viene ANIMATA e ATTESA
  /// (`await _settleWithGravity()`) prima di proseguire. Questo è ciò che
  /// crea la "pausa" richiesta fra uno scoppio della catena e il
  /// successivo — il giocatore vede chiaramente i Puyo scendere e poi
  /// scoppiare, invece che un collasso istantaneo e indistinguibile di
  /// tutta la catena in un solo istante. Solo quando il `while` termina
  /// (griglia stabile) generiamo il prossimo pezzo.
  Future<void> _resolveBoardThenSpawnNext() async {
    // Il pezzo si è appena separato nei suoi Puyo indipendenti: prima di
    // cercare eventuali gruppi, lasciamo che la gravità globale li faccia
    // assestare (es. il braccio di una "L" rimasto sospeso nel vuoto).
    await _settleWithGravity();

    var chainNumber = 0;

    while (true) {
      final groups = _playfieldGrid.findGroupsToClear();
      if (groups.isEmpty) {
        // Nessun gruppo: la griglia è stabile, il ciclo (e la catena) finisce qui.
        break;
      }

      chainNumber++;

      // Breve pausa "di lettura": il giocatore vede per un istante il
      // gruppo appena formatosi prima che scompaia, invece di un taglio
      // secco — coerente con la richiesta di mostrare gli scoppi della
      // catena come eventi distinti.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      for (final group in groups) {
        _playfieldGrid.clear(group);
        for (final puyo in group) {
          puyo.removeFromParent();
        }
      }

      _addScore(_scoreForChain(chainNumber));

      // Attendiamo per intero la caduta animata generata da QUESTO
      // scoppio prima di tornare in cima al ciclo: è esattamente questa
      // attesa a separare visivamente uno scoppio della catena dal
      // successivo, invece di farli franare tutti insieme.
      await _settleWithGravity();
    }

    _spawnNewPiece();
  }

  /// Applica la gravità globale (`PlayfieldGrid.applyGravity`, che
  /// aggiorna subito lo stato logico) e ne anima la caduta, restituendo
  /// il controllo solo quando OGNI Puyo spostato ha finito di scivolare
  /// nella propria nuova cella — `Future.wait` attende il completamento
  /// di tutte le animazioni in parallelo (cadono tutti insieme, ma
  /// `_resolveBoardThenSpawnNext` riprende solo a caduta ultimata).
  Future<void> _settleWithGravity() async {
    final movedPuyos = _playfieldGrid.applyGravity();
    if (movedPuyos.isEmpty) {
      return;
    }

    await Future.wait([
      for (final puyo in movedPuyos) puyo.fallTo(),
    ]);
  }

  /// Punti assegnati per uno scoppio alla concatenazione (chain) numero
  /// `chainNumber`, secondo la progressione richiesta — i numeri
  /// triangolari 1, 3, 6, 10, ... ottenuti dalla formula `n*(n+1)/2`:
  /// ogni anello in più della catena vale proporzionalmente di più,
  /// premiando le combo lunghe assai più che la somma dei singoli scoppi.
  int _scoreForChain(int chainNumber) => (chainNumber * (chainNumber + 1)) ~/ 2;

  /// Aggiunge punti al totale e aggiorna subito il testo a schermo:
  /// `TextComponent` si ridisegna da solo quando la sua proprietà `text`
  /// cambia, quindi non serve altro per riflettere il nuovo punteggio.
  void _addScore(int points) {
    _score += points;
    _scoreText.text = 'Score: $_score';
  }

  /// Termina la partita: ferma il game loop di Flame (`pauseEngine`, così
  /// nessun pezzo continua a muoversi sotto al messaggio) e avvisa lo
  /// strato Flutter tramite `onGameOver`, che mostrerà il dialog e
  /// riporterà il giocatore al menu.
  void _triggerGameOver() {
    if (_isGameOver) return;
    _isGameOver = true;

    pauseEngine();
    onGameOver();
  }

  /// Flame chiama questo metodo ogni volta che la dimensione dell'area di
  /// gioco cambia (es. resize della finestra del browser). Lo sfruttiamo
  /// per ridisporre sia la griglia che il punteggio, requisito
  /// fondamentale per una build web dove la viewport può avere qualunque
  /// proporzione.
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layoutHud();
  }

  /// Dispone gli elementi dell'interfaccia di gioco: la griglia al
  /// centro dello schermo, e il punteggio appena alla sua destra, alla
  /// stessa altezza del bordo superiore — "a lato della griglia", come
  /// richiesto.
  void _layoutHud() {
    // Essendo `_grid` ancorata al centro (Anchor.center), basta impostarne
    // la posizione al centro esatto dell'area di gioco (`size / 2`)
    // perché risulti perfettamente centrata sullo schermo.
    _grid.position = size / 2;

    final gridHalfSize = Vector2(
      GridComponent.columns * GridComponent.cellSize,
      GridComponent.rows * GridComponent.cellSize,
    ) / 2;

    // `_scoreText` ha l'anchor di default (Anchor.topLeft): posizionarlo
    // significa indicare dove va il suo angolo in alto a sinistra. Lo
    // mettiamo subito a destra del bordo destro della griglia
    // (`gridHalfSize.x` oltre al centro), allineato al suo bordo superiore.
    final sidebarX = _grid.position.x + gridHalfSize.x + 24;
    final sidebarTop = _grid.position.y - gridHalfSize.y;

    _scoreText.position = Vector2(sidebarX, sidebarTop);

    // Etichetta e anteprima del prossimo pezzo, impilate subito sotto al
    // punteggio nella stessa colonna laterale.
    _nextPieceLabel.position = Vector2(sidebarX, sidebarTop + 48);
    _nextPiecePreview.position = Vector2(sidebarX, sidebarTop + 80);
  }
}

