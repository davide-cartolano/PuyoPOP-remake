import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'game/puyo_ai.dart';
import 'game_screen.dart';
import 'versus_screen.dart';

/// Schermata iniziale: titolo del gioco e pulsanti di gioco, su uno
/// sfondo a gradiente in tema con l'ambientazione "Fever" del campo.
///
/// È un widget Flutter "puro" (nessuna dipendenza da Flame): il motore di
/// gioco viene creato solo quando il giocatore preme Play, navigando verso
/// `GameScreen`/`VersusScreen`. Così l'istanza di `PuyoGame` — e quindi la
/// partita — nasce nel momento giusto, non all'avvio dell'app.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  /// Chiede la difficoltà della CPU e, una volta scelta, avvia la
  /// partita contro di lei.
  Future<void> _startVersus(BuildContext context) async {
    final difficulty = await showDialog<AiDifficulty>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Difficoltà CPU'),
        children: [
          for (final difficulty in AiDifficulty.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(difficulty),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(difficulty.label, style: const TextStyle(fontSize: 18)),
              ),
            ),
        ],
      ),
    );

    if (difficulty == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => VersusScreen(difficulty: difficulty)),
    );
  }

  Widget _buildMenuButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: 260,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1B54), Color(0xFF1B1B3A), Color(0xFF0B0B1E)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Titolo su due righe, con ombra colorata: un piccolo tocco
              // "arcade" senza dipendere da font o asset esterni.
              const Text(
                'PUYO POP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  shadows: [Shadow(color: Color(0xFF6C5CE7), blurRadius: 18, offset: Offset(0, 4))],
                ),
              ),
              const Text(
                'FEVER',
                style: TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 10,
                  shadows: [Shadow(color: Color(0xFFFF6D00), blurRadius: 18, offset: Offset(0, 4))],
                ),
              ),
              const SizedBox(height: 56),
              _buildMenuButton('Gioca da solo', () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const GameScreen()),
                );
              }),
              const SizedBox(height: 16),
              _buildMenuButton('Gioca contro CPU', () => _startVersus(context)),
              // `exit(0)` non ha senso sul web e su iOS è contro le linee
              // guida: mostriamo il pulsante solo dove serve davvero.
              if (!kIsWeb) ...[
                const SizedBox(height: 16),
                _buildMenuButton('Esci', () => exit(0)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
