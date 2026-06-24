import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import 'game/puyo_game.dart';

/// Schermata di gioco vera e propria: ospita il `GameWidget` con
/// un'istanza di `PuyoGame` e si occupa di reagire al "game over".
///
/// È uno `StatefulWidget` (e non più `StatelessWidget`) perché ha bisogno
/// di un `BuildContext` stabile a cui aggrapparsi quando `PuyoGame` la
/// avvisa, tramite la callback `onGameOver`, che la partita è finita: solo
/// un widget con `State` può mostrare un dialog e navigare in risposta a
/// un evento che arriva "da fuori" (dal motore di gioco), non da un tap
/// sull'interfaccia.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Creiamo l'istanza una sola volta (non in `build`, che può essere
  // richiamato più volte): altrimenti rischieremmo di generare più
  // partite — e più GameWidget — per la stessa schermata.
  late final PuyoGame _game = PuyoGame(onGameOver: _showGameOverDialog);

  void _showGameOverDialog() {
    // `PuyoGame` ci avvisa dal proprio game loop, che gira durante la fase
    // di "frame" di Flutter: aprire subito un dialog (che modifica l'albero
    // dei widget) in quel preciso istante non è sicuro. Rimandando al
    // termine del frame corrente con `addPostFrameCallback` evitiamo
    // qualunque conflitto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Game Over'),
          content: const Text(
            'I Puyo hanno raggiunto la cima della griglia: la partita è finita.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Chiudiamo il dialog...
                Navigator.of(dialogContext).pop();
                // ...e torniamo alla prima schermata della pila di
                // navigazione, cioè il menu principale (`MenuScreen`,
                // impostato come `home` in MyApp).
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  /// Accumulatore dello spostamento orizzontale del dito, in pixel
  /// logici, da quando è iniziato il gesto corrente: l'azione (un passo a
  /// sinistra o a destra) scatta non appena supera `_dragStepThreshold`,
  /// in modo che lo spostamento touch abbia la stessa "grana a celle"
  /// del movimento da tastiera, invece di seguire il dito pixel per pixel.
  double _dragAccumulatorX = 0;

  /// Quanti pixel logici di trascinamento orizzontale corrispondono a
  /// UNA colonna. Un valore comodo da "swipare" col dito senza dover
  /// percorrere l'intera larghezza della griglia per un solo passo.
  static const double _dragStepThreshold = 32;

  void _onPanUpdate(DragUpdateDetails details) {
    _dragAccumulatorX += details.delta.dx;
    while (_dragAccumulatorX > _dragStepThreshold) {
      _game.moveCurrentPieceRight();
      _dragAccumulatorX -= _dragStepThreshold;
    }
    while (_dragAccumulatorX < -_dragStepThreshold) {
      _game.moveCurrentPieceLeft();
      _dragAccumulatorX += _dragStepThreshold;
    }

    // Un trascinamento verso il basso attiva la caduta accelerata, esattamente
    // come tenere premuta la freccia Giù da tastiera — resta attiva finché il
    // dito non si alza (`_onPanEnd`/`_onPanCancel`).
    if (details.delta.dy > 0) {
      _game.setCurrentPieceSoftDropping(true);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _dragAccumulatorX = 0;
    _game.setCurrentPieceSoftDropping(false);
  }

  void _onPanCancel() {
    _dragAccumulatorX = 0;
    _game.setCurrentPieceSoftDropping(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap: ruota il pezzo — l'equivalente touch della freccia Su.
        onTap: _game.rotateCurrentPiece,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: GameWidget(game: _game),
      ),
    );
  }
}
