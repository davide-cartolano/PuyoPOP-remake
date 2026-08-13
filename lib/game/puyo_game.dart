import 'dart:math';

import 'package:flame/components.dart' show Anchor, PositionComponent, TextComponent, TextPaint;
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/material.dart' show Colors, FontWeight, TextStyle;

import 'ai_controller.dart';
import 'falling_piece.dart';
import 'fever_background.dart';
import 'fever_gauge_component.dart';
import 'fever_presets.dart';
import 'grid_component.dart';
import 'next_piece_preview.dart';
import 'piece_shapes.dart';
import 'playfield_grid.dart';
import 'puyo_ai.dart';
import 'puyo_component.dart';

/// Classe principale del gi oco. Estendere FlameGame ci dà accesso al
/// game loop di Flame (update/re nder automatici), al sistema di componenti
/// e alla gestione delle dimensioni dello schermo.
/// Il mixin `HasKeyboardHandlerComponents` dice a Flame: "questo gioco
/// riceve eventi da tastiera e deve inoltrarli ai componenti figli che
/// implementano `KeyboardHandler`" (come il nostro FallingPiece).
/// Senza questo mixin, gli eventi tastiera non arriverebbero ai componenti.
class PuyoGame extends FlameGame with HasKeyboardHandlerComponents {
  PuyoGame({
    required this.onGameOver,
    this.isAiControlled = false,
    this.aiDifficulty = AiDifficulty.normal,
    this.onSendGarbage,
    this.onPendingGarbageChanged,
  });

  /// Invocata quando la partita finisce (pila arrivata fino alla cella di
  /// spawn). `PuyoGame` è puro Flame/Dart e non ha un `BuildContext`: è
  /// `GameScreen` — che lo possiede — a passarci questa callback, e a
  /// occuparsi di mostrare il messaggio a schermo e tornare al menu.
  final VoidCallback onGameOver;

  /// Se vero, ogni pezzo generato viene pilotato da `AiController` invece
  /// che dalla tastiera — è ciò che distingue la griglia della CPU da
  /// quella del giocatore umano nella modalità "Gioca contro CPU".
  final bool isAiControlled;

  /// Difficoltà della CPU (rilevante solo se `isAiControlled`): determina
  /// velocità, precisione e profondità di ricerca dell'AI — vedi
  /// `AiDifficulty` in `puyo_ai.dart`.
  final AiDifficulty aiDifficulty;

  /// Invocata ogni volta che una combo di questa partita genera Puyo
  /// spazzatura da inviare all'avversario (vedi `_resolveBoardThenSpawnNext`).
  /// `VersusScreen` collega questa callback all'altra istanza di `PuyoGame`,
  /// chiamandone `receiveGarbage`: `PuyoGame` di per sé non sa nulla
  /// dell'avversario, sa solo "quanti Puyo spazzatura ho generato".
  /// `null` nella modalità "Gioca da solo", dove non esiste un avversario.
  final void Function(int garbageCount)? onSendGarbage;

  /// Invocata ogni volta che cambia la quantità di Puyo spazzatura
  /// accumulati CONTRO questa partita (`_pendingGarbage`): ricevuti da una
  /// combo avversaria, compensati da una nostra combo, o fatti cadere.
  /// `VersusScreen` la usa per mostrare il contatore sopra la griglia.
  final void Function(int pendingGarbageCount)? onPendingGarbageChanged;

  /// Quanti Puyo spazzatura genera una combo, in base alla sua lunghezza
  /// (`chainNumber`, il numero di anelli/scoppi consecutivi avvenuti senza
  /// che la griglia tornasse stabile fra l'uno e l'altro): una singola
  /// esplosione senza combo ne genera 2, una combo da 2 ne genera 5, da 3
  /// ne genera 8, da 4 ne genera 12 — poi continua a crescere di 4 per
  /// ogni anello in più, in modo che le catene lunghe restino sempre
  /// sproporzionatamente più pericolose delle combo corte, come nel gioco
  /// originale.
  static int _garbageCountForChain(int chainNumber) {
    if (chainNumber <= 1) return 2;
    if (chainNumber == 2) return 5;
    if (chainNumber == 3) return 8;
    return 12 + (chainNumber - 4) * 4;
  }

  /// Puyo spazzatura accumulati CONTRO questa partita: ricevuti da combo
  /// avversarie ma non ancora fatti cadere. Cadono solo quando un pezzo si
  /// blocca SENZA causare alcuno scoppio (vedi `_resolveBoardThenSpawnNext`)
  /// — mai a metà di una mossa, e mai mentre siamo noi a far scoppiare
  /// qualcosa. Una nostra combo, quando arriva, li riduce per prima cosa
  /// (vedi `_sendGarbageForChain`) prima che l'eventuale eccedenza raggiunga
  /// davvero l'avversario.
  int _pendingGarbage = 0;

  void _setPendingGarbage(int value) {
    _pendingGarbage = value;
    onPendingGarbageChanged?.call(_pendingGarbage);
  }

  /// Invocato da `VersusScreen` quando l'avversario fa una combo: accoda
  /// i Puyo spazzatura generati, che cadranno alla prossima occasione.
  void receiveGarbage(int count) {
    _setPendingGarbage(_pendingGarbage + count);
  }

  /// Calcola quanti Puyo spazzatura genera una combo di lunghezza
  /// `chainNumber` e li scarica prima su quelli già accumulati contro di
  /// noi: solo l'eventuale eccedenza viene davvero inviata all'avversario
  /// tramite `onSendGarbage`.
  void _sendGarbageForChain(int chainNumber) {
    final garbageGenerated = _garbageCountForChain(chainNumber);

    final offset = min(garbageGenerated, _pendingGarbage);
    _setPendingGarbage(_pendingGarbage - offset);

    final garbageToSend = garbageGenerated - offset;
    if (garbageToSend > 0) {
      onSendGarbage?.call(garbageToSend);
    }
  }

  /// Punteggio corrente, esposto in lettura per chi ospita il gioco (es.
  /// `VersusScreen`, che lo usa per stabilire chi ha vinto la partita).
  int get score => _score;

  /// Il pezzo attualmente controllabile, o `null` fra un lock e il prossimo
  /// spawn. `GameScreen` lo pilota indirettamente tramite i metodi
  /// `moveCurrentPieceLeft/Right`, `rotateCurrentPiece` e
  /// `setCurrentPieceSoftDropping`, per tradurre i gesti touch (swipe, tap)
  /// in comandi — `FallingPiece` di per sé risponde solo alla tastiera.
  FallingPiece? _currentPiece;

  void moveCurrentPieceLeft() => _currentPiece?.moveLeft();

  void moveCurrentPieceRight() => _currentPiece?.moveRight();

  void rotateCurrentPiece() => _currentPiece?.rotateClockwise();

  void setCurrentPieceSoftDropping(bool value) => _currentPiece?.setSoftDropping(value);

  // Creiamo subito l'istanza (non in onLoad): Flame può chiamare
  // onGameResize prima che onLoad termini, e a quel punto questo campo
  // deve già esistere per evitare un LateInitializationError.
  final GridComponent _grid = GridComponent();

  /// Sfondo animato (gradiente + bolle + stelle) dietro a tutto il resto:
  /// riempie l'intera area del gioco, non solo la griglia.
  final FeverBackground _background = FeverBackground();

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

  /// Indicatore della barra Fever (pallini 1-8) e, durante la Fever, del
  /// tempo rimanente. Vive nella sidebar, sotto all'anteprima.
  final FeverGaugeComponent _feverGaugeDisplay = FeverGaugeComponent();

  /// Etichetta sopra la barra Fever: "Fever" normalmente, "FEVER!"
  /// lampeggiante quando la modalità è attiva.
  final TextComponent _feverLabel = TextComponent(
    text: 'Fever',
    textRenderer: TextPaint(
      style: const TextStyle(color: Colors.white, fontSize: 20),
    ),
  );

  // --- Stato della modalità Fever -------------------------------------

  /// Quanto dura la modalità Fever, in secondi.
  static const double _feverDuration = 45;

  /// Livello corrente della barra Fever (0..8): cresce di 1 per ogni
  /// anello di catena fatto scoppiare MENTRE c'è spazzatura in sospeso
  /// contro di noi; a 8 scatta la modalità Fever.
  int _feverCharge = 0;

  /// Vero mentre la modalità Fever è attiva.
  bool _isFeverActive = false;

  /// Secondi di Fever rimanenti (conta alla rovescia in `update`).
  double _feverTimeLeft = 0;

  /// Lunghezza di combo della PROSSIMA board precostruita da caricare:
  /// parte da `feverMinChain` (4) e cresce di 1 dopo ogni combo innescata,
  /// fino a `feverMaxChain`.
  int _feverChainLevel = feverMinChain;

  /// Contenitore di TUTTO l'HUD (griglia, punteggio, anteprima): griglia e
  /// sidebar vengono disposte al suo interno con coordinate FISSE (vedi
  /// `_layoutHud`), e siamo NOI a scalare e centrare questo contenitore
  /// per farlo entrare nello spazio realmente disponibile. Senza questo
  /// livello in più, su uno schermo più piccolo della larghezza fissa di
  /// griglia+sidebar (es. metà schermo di un telefono in modalità
  /// "Gioca contro CPU") il contenuto sborderebbe oltre i propri confini,
  /// invadendo visivamente l'area dell'altra partita.
  final PositionComponent _hud = PositionComponent();

  /// Spazio riservato, a destra della griglia, al punteggio e
  /// all'anteprima del prossimo pezzo.
  static const double _sidebarWidth = 160;

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

    await add(_background);
    _background.size = size.clone();
    await add(_hud);
    await _hud.add(_grid);
    await _hud.add(_scoreText);
    await _hud.add(_nextPieceLabel);
    await _hud.add(_nextPiecePreview);
    await _hud.add(_feverLabel);
    await _hud.add(_feverGaugeDisplay);
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

  @override
  void update(double dt) {
    super.update(dt);

    // Controllato qui, ad ogni frame, invece che solo nei punti in cui la
    // pila cambia (scoppi, gravità, lock): è la via più semplice per
    // tenere l'indicatore di pericolo sempre sincronizzato con lo stato
    // reale della griglia, senza dover individuare ogni singolo punto del
    // codice che potrebbe alterare l'altezza della pila.
    _grid.isInDanger = _playfieldGrid.isStackInDanger();

    // Conto alla rovescia della Fever: quando il tempo scade, la modalità
    // finisce e la griglia resta com'è in quel momento (come su PSP).
    if (_isFeverActive) {
      _feverTimeLeft -= dt;
      _feverGaugeDisplay.timeFraction = (_feverTimeLeft / _feverDuration).clamp(0, 1);
      if (_feverTimeLeft <= 0) {
        _exitFever();
      }
    }
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

    final piece = FallingPiece(
      playfieldGrid: _playfieldGrid,
      onLocked: _resolveBoardThenSpawnNext,
      spec: spec,
    );
    _currentPiece = piece;
    _grid.add(piece);

    if (isAiControlled) {
      _grid.add(AiController(
        piece: piece,
        playfieldGrid: _playfieldGrid,
        difficulty: aiDifficulty,
        random: _random,
      ));
    } 
  }

  /// Fa cadere tutti i Puyo spazzatura accumulati in `_pendingGarbage`,
  /// distribuendoli a caso fra le colonne — un'"ondata" per volta (al più
  /// uno per colonna, così le cadute in parallelo non si pestano i piedi),
  /// finché non ne restano più o la griglia non ha più spazio.
  Future<void> _dropPendingGarbage() async {
    var remaining = _pendingGarbage;
    _setPendingGarbage(0);

    while (remaining > 0) {
      final shuffledColumns = List.generate(GridComponent.columns, (column) => column)..shuffle(_random);
      final fallingAnimations = <Future<void>>[];

      for (final column in shuffledColumns) {
        if (remaining <= 0) break;

        final landingRow = _playfieldGrid.landingRowForGarbage(column);
        if (landingRow == null) continue; // colonna già piena: questo Puyo va perso.
        remaining--;

        final garbagePuyo = PuyoComponent(
          column: column,
          row: landingRow,
          color: Colors.white,
          isGarbage: true,
        );
        _playfieldGrid.lock(garbagePuyo);

        // Lo facciamo nascere un filo sopra al bordo della griglia, così
        // `fallTo` lo anima scendendo fino alla sua cella di destinazione
        // — esattamente come la caduta per gravità dei Puyo già in gioco.
        garbagePuyo.position = Vector2(column * GridComponent.cellSize, -GridComponent.cellSize);
        _grid.add(garbagePuyo);
        fallingAnimations.add(garbagePuyo.fallTo());
      }

      if (fallingAnimations.isEmpty) {
        // Nessuna colonna aveva spazio in questa ondata: il resto dei
        // Puyo spazzatura in eccesso viene semplicemente scartato.
        break;
      }

      await Future.wait(fallingAnimations);
    }
  }

  // --- Modalità Fever ---------------------------------------------------

  /// Fa salire la barra Fever di `amount` livelli (senza superare 8),
  /// aggiornando subito l'indicatore a schermo. Chiamata solo mentre c'è
  /// spazzatura in sospeso contro di noi: è la condizione, richiesta dal
  /// design, perché gli scoppi "carichino" la Fever.
  void _chargeFeverGauge(int amount) {
    _feverCharge = (_feverCharge + amount).clamp(0, FeverGaugeComponent.maxCharge);
    _feverGaugeDisplay.charge = _feverCharge;
  }

  /// Entra in modalità Fever: azzera la barra, avvia i 45 secondi,
  /// svuota completamente la griglia e la sostituisce con la prima board
  /// precostruita (combo da `feverMinChain`).
  void _enterFever() {
    _isFeverActive = true;
    _feverTimeLeft = _feverDuration;
    _feverChainLevel = feverMinChain;
    _feverCharge = 0;
    _feverGaugeDisplay
      ..charge = 0
      ..isActive = true
      ..timeFraction = 1;
    _feverLabel.text = 'FEVER!';

    _replaceBoardWithFeverPreset();
    _showFeverPopup();
  }

  /// Esce dalla modalità Fever: la griglia resta ESATTAMENTE com'è in quel
  /// momento (come nella versione PSP) e si torna al gioco normale.
  void _exitFever() {
    _isFeverActive = false;
    _feverGaugeDisplay
      ..isActive = false
      ..charge = 0;
    _feverLabel.text = 'Fever';
  }

  /// Svuota la griglia (logica + componenti) e vi piazza la board
  /// precostruita corrispondente a `_feverChainLevel`.
  void _replaceBoardWithFeverPreset() {
    for (final puyo in _playfieldGrid.clearAll()) {
      puyo.removeFromParent();
    }

    final rows = feverBoardForChain(_feverChainLevel);
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final cell = rows[row][column];
        if (cell == '.') continue;

        final puyo = PuyoComponent(
          column: column,
          row: row,
          color: puyoColors[int.parse(cell)],
        );
        _playfieldGrid.lock(puyo);
        _grid.add(puyo);
      }
    }
  }

  /// Grande scritta "FEVER!" al centro della griglia quando la modalità
  /// si attiva — stesso meccanismo del popup delle catene, ma più vistosa.
  void _showFeverPopup() {
    final popup = TextComponent(
      text: 'FEVER!',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.orangeAccent,
          fontSize: 44,
          fontWeight: FontWeight.w900,
        ),
      ),
      position: _grid.position.clone(),
      anchor: Anchor.center,
      scale: Vector2.zero(),
    );
    popup.add(ScaleEffect.to(Vector2.all(1), EffectController(duration: 0.25)));
    popup.add(MoveByEffect(Vector2(0, -30), EffectController(duration: 1.1)));
    popup.add(RemoveEffect(delay: 1.1));
    _hud.add(popup);
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
  Future<void> _resolveBoardThenSpawnNext({required bool toppedOut}) async {
    // Il pezzo si è bloccato: da questo momento (e finché non ne nasce un
    // altro) non c'è alcun pezzo controllabile a cui inoltrare i comandi
    // touch — vedi `moveCurrentPieceLeft/Right`, `rotateCurrentPiece`.
    _currentPiece = null;

    // Un blocco del pezzo è rimasto sopra al bordo della griglia: la pila
    // è arrivata in cima e la partita finisce subito, senza risolvere
    // altro — è la gestione (prima mancante, e causa di crash) della
    // sconfitta "per soffocamento".
    if (toppedOut) {
      _triggerGameOver();
      return;
    }

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

      // Ogni gruppo che scoppia in questo stesso anello (gruppi di colori
      // diversi separati, scoppiati simultaneamente dopo l'ultima caduta
      // per gravità) vale un punto di combo a sé, non solo l'anello nel
      // suo insieme: 5 verdi + 5 rossi insieme, alla prima occasione, è
      // già una combo di 2 — non di 1 — esattamente come un secondo
      // anello di catena lo sarebbe.
      chainNumber += groups.length;

      // Barra Fever: ogni anello della catena vale +1, ma SOLO mentre
      // siamo "sotto pressione": spazzatura ancora in sospeso contro di
      // noi, OPPURE già caduta e presente sulla griglia. Il secondo caso
      // è essenziale: la spazzatura cade alla prima mossa a vuoto, e
      // senza questo controllo gli scoppi fatti per liberarsene non
      // caricherebbero mai la barra.
      if (!_isFeverActive && (_pendingGarbage > 0 || _playfieldGrid.hasGarbage())) {
        _chargeFeverGauge(1);
      }

      // Breve pausa "di lettura": il giocatore vede per un istante il
      // gruppo appena formatosi prima che scompaia, invece di un taglio
      // secco — coerente con la richiesta di mostrare gli scoppi della
      // catena come eventi distinti.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // I Puyo spazzatura adiacenti a un gruppo che scoppia vengono
      // liberati insieme a lui (non scoppiano mai da soli, vedi
      // `findAdjacentGarbage`), ma non contano per il punteggio: solo i
      // gruppi colorati (`groups`) entrano in `_scoreForLink`.
      final garbageNeighbors = _playfieldGrid.findAdjacentGarbage(groups);

      // Aggiorniamo SUBITO lo stato logico (la pila non deve "aspettare"
      // la fine dell'animazione per considerarsi libera in quelle celle),
      // ma rimuoviamo i PuyoComponent solo dopo che l'effetto di scoppio
      // — animazione + particelle — è terminato: è questa attesa, non più
      // un semplice ritardo cieco, a riempire visivamente la pausa fra
      // uno scoppio della catena e il successivo.
      final puyosToClear = [for (final group in groups) ...group, ...garbageNeighbors];
      for (final group in groups) {
        _playfieldGrid.clear(group);
      }
      _playfieldGrid.clear(garbageNeighbors);

      await Future.wait([for (final puyo in puyosToClear) _playPopEffect(puyo)]);

      for (final puyo in puyosToClear) {
        puyo.removeFromParent();
      }

      _addScore(_scoreForLink(chainNumber: chainNumber, groups: groups));
      _showChainPopup(chainNumber);

      // Attendiamo per intero la caduta animata generata da QUESTO
      // scoppio prima di tornare in cima al ciclo: è esattamente questa
      // attesa a separare visivamente uno scoppio della catena dal
      // successivo, invece di farli franare tutti insieme.
      await _settleWithGravity();
    }

    if (chainNumber > 0) {
      // Abbiamo fatto scoppiare qualcosa: generiamo Puyo spazzatura per
      // l'avversario (in base alla lunghezza della catena) e NON facciamo
      // cadere quelli eventualmente accumulati contro di noi — restano in
      // sospeso fino a una nostra mossa "a vuoto".
      _sendGarbageForChain(chainNumber);
    } else if (_pendingGarbage > 0 && !_isFeverActive) {
      // Questo pezzo si è bloccato senza causare alcuno scoppio: è
      // esattamente — e SOLO — in questo momento che la spazzatura
      // accumulata contro di noi cade davvero, prima del prossimo pezzo.
      // Durante la Fever, invece, la spazzatura resta in sospeso: la
      // modalità non va "sporcata" da macigni che rovinerebbero le board
      // precostruite — cadranno alla prima occasione dopo la sua fine.
      await _dropPendingGarbage();
    }

    if (_isFeverActive && chainNumber > 0) {
      // Durante la Fever, ogni combo innescata consuma la board corrente:
      // quel che ne resta viene spazzato via e sostituito da una nuova
      // board precostruita con una combo ancora più lunga.
      _feverChainLevel = min(_feverChainLevel + 1, feverMaxChain);
      _replaceBoardWithFeverPreset();
    } else if (!_isFeverActive && _feverCharge >= FeverGaugeComponent.maxCharge) {
      // Barra piena: la Fever parte adesso, PRIMA del prossimo pezzo, con
      // la griglia appena stabilizzata.
      _enterFever();
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

  /// Anima lo scoppio di un singolo Puyo: lo fa "rigonfiare e collassare"
  /// (`PuyoComponent.playPopEffect`) e, in contemporanea, genera dalla sua
  /// posizione un piccolo burst di particelle dello stesso colore
  /// (`createPuyoBurst`). Il Future si completa solo quando l'animazione
  /// del Puyo è finita: è quello che `_resolveBoardThenSpawnNext` attende
  /// prima di rimuoverlo davvero dall'albero.
  Future<void> _playPopEffect(PuyoComponent puyo) {
    final burstCenter = puyo.position + puyo.size / 2;
    _grid.add(createPuyoBurst(position: burstCenter, color: puyo.color));
    return puyo.playPopEffect();
  }

  /// Mostra, al centro della griglia, un breve testo "Chain xN!" quando
  /// uno scoppio fa parte di una catena (`chainNumber` >= 2) — il primo
  /// scoppio di ogni caduta non è ancora una "combo", quindi non genera
  /// alcun popup. Il testo nasce piccolo, "scatta" alla sua dimensione
  /// piena, fluttua verso l'alto e si rimuove da solo a fine animazione.
  void _showChainPopup(int chainNumber) {
    if (chainNumber < 2) return;

    final popup = TextComponent(
      text: 'Chain x$chainNumber!',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.amber,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      position: _grid.position.clone(),
      anchor: Anchor.center,
      scale: Vector2.zero(),
    );

    popup.add(
      ScaleEffect.to(Vector2.all(1), EffectController(duration: 0.15)),
    );
    popup.add(
      MoveByEffect(Vector2(0, -36), EffectController(duration: 0.7)),
    );
    popup.add(RemoveEffect(delay: 0.7));

    // Aggiunto a `_hud` (non alla radice del gioco): `_grid.position` è
    // espresso nelle coordinate FISSE e non scalate dell'HUD (vedi
    // `_layoutHud`), quindi il popup deve vivere nello stesso sistema di
    // coordinate per comparire davvero al centro della griglia.
    _hud.add(popup);
  }

  /// Tabella del "chain power" del gioco originale: il moltiplicatore
  /// cresce con l'anello della catena (`chainNumber`), ma non
  /// linearmente — ogni anello in più vale proporzionalmente di più dei
  /// precedenti, fino ad appiattirsi oltre la dodicesima concatenazione.
  /// Indice 0 = primo anello (nessun bonus: non è ancora una "catena").
  static const List<int> _chainPowerTable = [
    0, 8, 16, 32, 64, 96, 128, 160, 192, 224, 256, 288,
  ];

  /// Tabella del bonus colore: più colori DIVERSI scoppiano nello stesso
  /// anello, più alto il bonus — è ciò che rende preziosi gli scoppi
  /// "multicolore" simultanei, e non solo le catene lunghe di un solo
  /// colore.
  static const List<int> _colorBonusTable = [0, 3, 6, 12, 24];

  /// Punti assegnati per UN anello della catena (uno scoppio simultaneo
  /// di uno o più gruppi), secondo la formula del gioco originale:
  /// `puyo_eliminati * 10 * bonus`, dove `bonus` è la somma di tre
  /// componenti — chain power, bonus colore, bonus gruppo — con un minimo
  /// di 1 (mai zero, altrimenti anche scoppi "validi" darebbero 0 punti).
  int _scoreForLink({required int chainNumber, required List<List<PuyoComponent>> groups}) {
    final totalPuyosCleared = groups.fold(0, (sum, group) => sum + group.length);
    final distinctColors = groups.map((group) => group.first.color).toSet();

    final chainPower = _chainPowerTable[(chainNumber - 1).clamp(0, _chainPowerTable.length - 1)];
    final colorBonus = _colorBonusTable[(distinctColors.length - 1).clamp(0, _colorBonusTable.length - 1)];
    final groupBonus = groups.fold(0, (sum, group) => sum + _groupBonus(group.length));

    final bonus = chainPower + colorBonus + groupBonus;
    return totalPuyosCleared * 10 * (bonus == 0 ? 1 : bonus);
  }

  /// Bonus per la dimensione di un singolo gruppo che scoppia: i 5 Puyo
  /// minimi richiesti non danno alcun bonus, ma ogni Puyo in più nello
  /// stesso gruppo ne aggiunge — premiando i gruppi grandi oltre al
  /// minimo necessario per scoppiare.
  int _groupBonus(int groupSize) {
    if (groupSize <= 5) return 0;
    if (groupSize == 6) return 2;
    if (groupSize == 7) return 3;
    if (groupSize == 8) return 4;
    if (groupSize <= 10) return 5;
    if (groupSize <= 12) return 6;
    return 10;
  }

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
    _background.size = size.clone();
    _layoutHud();
  }

  /// Dispone gli elementi dell'interfaccia di gioco (griglia a sinistra,
  /// punteggio e anteprima del prossimo pezzo a destra) in coordinate
  /// FISSE — esattamente come se lo schermo avesse sempre la stessa
  /// dimensione — e poi scala e centra l'intero `_hud` per farlo entrare
  /// nello spazio realmente disponibile (`size`).
  ///
  /// Questo secondo passaggio è ciò che permette al gioco di adattarsi a
  /// QUALUNQUE area assegnata dal layout Flutter che lo ospita: una
  /// finestra desktop, una pagina web, ma anche solo MEZZO schermo di un
  /// telefono come nella modalità "Gioca contro CPU" — senza la scala,
  /// griglia e sidebar (disegnate a dimensione fissa in pixel) potrebbero
  /// risultare più larghe dello spazio disponibile e sborderebbero
  /// nell'area della partita vicina.
  void _layoutHud() {
    final gridSize = Vector2(
      GridComponent.columns * GridComponent.cellSize,
      GridComponent.rows * GridComponent.cellSize,
    );

    final contentSize = Vector2(gridSize.x + _sidebarWidth, gridSize.y);

    // Essendo `_grid` ancorata al centro (Anchor.center), per metterla
    // nell'angolo in alto a sinistra del contenuto basta posizionarla a
    // metà della propria dimensione.
    _grid.position = gridSize / 2;

    // Sidebar (punteggio + anteprima) subito a destra del bordo destro
    // della griglia, allineata al suo bordo superiore.
    const sidebarX = GridComponent.columns * GridComponent.cellSize + 24;
    const sidebarTop = 0.0;

    _scoreText.position = Vector2(sidebarX, sidebarTop);
    _nextPieceLabel.position = Vector2(sidebarX, sidebarTop + 48);
    _nextPiecePreview.position = Vector2(sidebarX, sidebarTop + 80);
    _feverLabel.position = Vector2(sidebarX, sidebarTop + 216);
    _feverGaugeDisplay.position = Vector2(sidebarX, sidebarTop + 244);

    // Scala uniforme (stessa per X e Y, altrimenti la griglia risulterebbe
    // deformata) che fa entrare l'intero contenuto, a dimensione fissa,
    // nello spazio davvero disponibile — sia che sia più piccolo (lo
    // riduce) sia che sia più grande (lo amplia, evitando un riquadro di
    // gioco minuscolo su un monitor desktop ampio).
    if (contentSize.x <= 0 || contentSize.y <= 0 || size.x <= 0 || size.y <= 0) {
      return;
    }

    final scale = min(size.x / contentSize.x, size.y / contentSize.y);
    _hud.scale = Vector2.all(scale);

    // Centra il contenuto SCALATO nello spazio disponibile.
    final scaledContentSize = contentSize * scale;
    _hud.position = (size - scaledContentSize) / 2;
  }
}
