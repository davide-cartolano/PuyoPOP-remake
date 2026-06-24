import 'dart:io';

import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'versus_screen.dart';

/// Schermata iniziale: titolo del gioco e pulsante "Play".
///
/// È un widget Flutter "puro" (nessuna dipendenza da Flame): il motore di
/// gioco viene creato solo quando il giocatore preme Play, navigando verso
/// `GameScreen`. Così l'istanza di `PuyoGame` — e quindi la partita — nasce
/// nel momento giusto, non all'avvio dell'app.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Puyo Pop Fever Clone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              // Navigator.push apre la schermata di gioco "sopra" al menu:
              // tornando indietro (es. tasto Indietro del browser), il
              // giocatore ritrova il menu.
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const GameScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                textStyle: const TextStyle(fontSize: 20),
              ),
              child: const Text('Gioca da solo'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const VersusScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                textStyle: const TextStyle(fontSize: 20),
              ),
              child: const Text('Gioca contro CPU'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                exit(0);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                textStyle: const TextStyle(fontSize: 20),
              ),
              child: const Text('Esci'),
            ),
          ],
        ),
      ),
    );
  }
}
