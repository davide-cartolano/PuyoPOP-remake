import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import 'game/puyo_game.dart';

/// Schermata "Gioca contro CPU": due griglie indipendenti fianco a fianco,
/// una pilotata dal giocatore (tastiera) e una dall'AI (`AiController`,
/// vedi `game/ai_controller.dart`). Le due partite non si influenzano a
/// vicenda (nessun "garbage puyo" inviato all'avversario): vince chi
/// regge più a lungo senza arrivare al game over.
///
/// Come `GameScreen`, è uno `StatefulWidget`: serve un `BuildContext`
/// stabile a cui aggrapparsi quando una delle due partite finisce.
class VersusScreen extends StatefulWidget {
  const VersusScreen({super.key});

  @override
  State<VersusScreen> createState() => _VersusScreenState();
}

class _VersusScreenState extends State<VersusScreen> {
  late final PuyoGame _playerGame = PuyoGame(
    onGameOver: () => _showResultDialog(playerLost: true),
  );

  late final PuyoGame _cpuGame = PuyoGame(
    isAiControlled: true,
    onGameOver: () => _showResultDialog(playerLost: false),
  );

  bool _resultShown = false;

  void _showResultDialog({required bool playerLost}) {
    // Se una griglia finisce, anche l'altra deve fermarsi: la partita è
    // decisa, non avrebbe senso lasciarla proseguire da sola.
    _playerGame.pauseEngine();
    _cpuGame.pauseEngine();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resultShown) return;
      _resultShown = true;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(playerLost ? 'Hai perso!' : 'Hai vinto!'),
          content: Text(
            'Punteggio finale — Tu: ${_playerGame.score}, CPU: ${_cpuGame.score}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
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
      body: Row(
        children: [
          Expanded(child: GameWidget(game: _playerGame)),
          const VerticalDivider(color: Colors.white24, width: 1),
          // `autofocus: false` impedisce a questa griglia di intercettare
          // gli eventi tastiera: devono arrivare solo al pezzo del
          // giocatore, mai a quello pilotato dall'AI.
          Expanded(child: GameWidget(game: _cpuGame, autofocus: false)),
        ],
      ),
    );
  }
}
