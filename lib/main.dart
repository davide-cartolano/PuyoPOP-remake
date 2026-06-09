import 'package:flutter/material.dart';

import 'menu_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puyo Pop Fever Clone',
      debugShowCheckedModeBanner: false,
      // Sfondo nero attorno al gioco: utile per il web, dove la finestra
      // potrebbe avere un rapporto d'aspetto diverso da quello del gioco.
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
      // L'app parte sempre dal menu: il GameWidget (e quindi PuyoGame)
      // viene creato solo quando il giocatore preme "Play", in GameScreen.
      home: const MenuScreen(),
    );
  }
}
