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
  // I riferimenti reciproci nei closure (`_cpuGame`/`_playerGame`) sono
  // sicuri nonostante l'ordine di dichiarazione: essendo `late final`,
  // l'inizializzatore di ciascun campo viene eseguito alla prima lettura,
  // non alla dichiarazione — e i closure qui sotto leggono l'altro campo
  // solo quando una combo li invoca davvero, ben dopo che entrambi
  // esistono.
  late final PuyoGame _playerGame = PuyoGame(
    onGameOver: () => _showResultDialog(playerLost: true),
    onSendGarbage: (count) => _cpuGame.receiveGarbage(count),
    onPendingGarbageChanged: (count) => setState(() => _playerPendingGarbage = count),
  );

  late final PuyoGame _cpuGame = PuyoGame(
    isAiControlled: true,
    onGameOver: () => _showResultDialog(playerLost: false),
    onSendGarbage: (count) => _playerGame.receiveGarbage(count),
    onPendingGarbageChanged: (count) => setState(() => _cpuPendingGarbage = count),
  );

  bool _resultShown = false;

  /// Puyo spazzatura attualmente accumulati contro ciascun giocatore,
  /// mostrati sopra la rispettiva griglia (vedi `_buildGarbageCounter`).
  int _playerPendingGarbage = 0;
  int _cpuPendingGarbage = 0;

  /// Stesso meccanismo di "grana a celle" per lo swipe, e stessa soglia di
  /// spostamento TOTALE per la caduta accelerata, usati in `GameScreen`:
  /// vedi lì per i dettagli (in breve: evitano che un dito fermo, o il
  /// jitter di un trascinamento laterale, attivi la caduta accelerata).
  double _dragAccumulatorX = 0;
  static const double _dragStepThreshold = 32;
  double _dragTotalY = 0;
  static const double _softDropEngageThreshold = 24;

  void _onPanUpdate(DragUpdateDetails details) {
    _dragAccumulatorX += details.delta.dx;
    while (_dragAccumulatorX > _dragStepThreshold) {
      _playerGame.moveCurrentPieceRight();
      _dragAccumulatorX -= _dragStepThreshold;
    }
    while (_dragAccumulatorX < -_dragStepThreshold) {
      _playerGame.moveCurrentPieceLeft();
      _dragAccumulatorX += _dragStepThreshold;
    }

    _dragTotalY += details.delta.dy;
    _playerGame.setCurrentPieceSoftDropping(_dragTotalY > _softDropEngageThreshold);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragAccumulatorX = 0;
    _dragTotalY = 0;
    _playerGame.setCurrentPieceSoftDropping(false);
  }

  void _onPanCancel() {
    _dragAccumulatorX = 0;
    _dragTotalY = 0;
    _playerGame.setCurrentPieceSoftDropping(false);
  }

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
          title: const Text('Partita terminata'),
          content: Text(
            '${playerLost ? 'Hai perso!' : 'Hai vinto!'}\n'
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

  /// Etichetta sopra una griglia, con la quantità di Puyo spazzatura
  /// attualmente accumulati contro quel giocatore — 0 non viene mostrato
  /// in grassetto/rosso: solo quando c'è davvero una minaccia in arrivo
  /// vale la pena attirare l'attenzione su questo numero.
  Widget _buildGarbageCounter(String label, int count) {
    return Container(
      color: const Color(0xFF0E0E1E),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: Text(
        '$label: $count 🪨',
        style: TextStyle(
          color: count > 0 ? Colors.redAccent : Colors.white54,
          fontSize: 16,
          fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildGarbageCounter('Tu', _playerPendingGarbage),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _playerGame.rotateCurrentPiece,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    onPanCancel: _onPanCancel,
                    child: GameWidget(game: _playerGame),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(color: Colors.white24, width: 1),
          Expanded(
            child: Column(
              children: [
                _buildGarbageCounter('CPU', _cpuPendingGarbage),
                // `autofocus: false` impedisce a questa griglia di
                // intercettare gli eventi tastiera: devono arrivare solo
                // al pezzo del giocatore, mai a quello pilotato dall'AI.
                Expanded(child: GameWidget(game: _cpuGame, autofocus: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
