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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(game: _game),
    );
  }
}
