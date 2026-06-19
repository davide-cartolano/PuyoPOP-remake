import 'dart:math';

import 'package:flutter/material.dart' show Color, Colors;

/// Una coppia (colonna, riga) che rappresenta uno spostamento RELATIVO
/// all'interno della griglia. La usiamo per due cose:
/// - descrivere la "forma" di un pezzo, come elenco di posizioni rispetto
///   a un blocco di riferimento (il pivot);
/// - calcolarne la rotazione, ruotando ciascun offset attorno al pivot.
class GridOffset {
  const GridOffset(this.column, this.row);

  final int column;
  final int row;

  /// Ruota questo offset di 90° in senso orario attorno al pivot (0, 0).
  ///
  /// Nel nostro sistema di coordinate la riga CRESCE scendendo (come per
  /// i pixel a schermo). In questo sistema, la trasformazione che produce
  /// una rotazione visivamente oraria è: (colonna, riga) -> (-riga, colonna).
  ///
  /// Verifica intuitiva: un blocco a destra del pivot, offset (1, 0),
  /// dopo la rotazione finisce SOTTO al pivot, offset (0, 1) — proprio
  /// come ci si aspetterebbe ruotando in senso orario.
  GridOffset rotatedClockwise() => GridOffset(-row, column);
}

/// Quante configurazioni di pezzo conosce il gioco. Tenerlo come costante
/// (anziché ripetere "5" ovunque) rende ovvio che `randomPieceOffsets` e
/// lo `switch` qui sotto devono restare sincronizzati.
const _shapeCount = 6;

/// Sceglie casualmente una delle configurazioni di pezzo previste dal
/// gioco e la restituisce come elenco di `GridOffset` relativi al blocco
/// "pivot": il perno attorno a cui ruota l'intero pezzo. Per convenzione,
/// il pivot è sempre il PRIMO elemento della lista, sempre con offset (0, 0).
///
/// Prima di restituirla, applica anche una rotazione iniziale scelta a
/// caso (si veda `_withRandomInitialAngle`): ogni pezzo può quindi
/// comparire già ruotato di 0°, 90°, 180° o 270°, per un po' di varietà
/// in più fra una generazione e l'altra.
List<GridOffset> randomPieceOffsets(Random random) {
  final List<GridOffset> baseOffsets;

  switch (random.nextInt(_shapeCount)) {
    case 0:
      // Singolo: un solo Puyo. La rotazione non produce alcun effetto
      // visibile, ma passa comunque per lo stesso codice degli altri pezzi.
      baseOffsets = const [GridOffset(0, 0)];

    case 1:
      // Coppia: due Puyo in verticale, uno sopra l'altro. Il pivot è
      // quello in basso: è così che ruota la coppia nel gioco originale
      // (l'altro Puyo "orbita" attorno a quello inferiore).
      baseOffsets = const [
        GridOffset(0, 0),
        GridOffset(0, -1),
      ];

    case 2:
      // Triangolo "Fever": tre Puyo a L — due affiancati sulla stessa riga
      // (il pivot e uno alla sua destra) e un terzo sopra, posizionato a
      // caso sopra il pivot o sopra il blocco a destra, per un po' di
      // varietà tra le forme generate.
      final extraBlockAboveRightOne = random.nextBool();
      baseOffsets = [
        const GridOffset(0, 0),
        const GridOffset(1, 0),
        GridOffset(extraBlockAboveRightOne ? 1 : 0, -1),
      ];

    case 3:
      // Tripla dritta: tre Puyo impilati in verticale, come la "I" del
      // Tetris. Il pivot è quello CENTRALE: ruotando, gli altri due si
      // dispongono in modo simmetrico a sinistra e a destra — vedi
      // `GridOffset.rotatedClockwise` per i dettagli della trasformazione.
      // Nota: il blocco superiore nasce a riga -1, cioè un filo sopra al
      // bordo della griglia: è lo stesso meccanismo, già visto con la
      // Coppia, con cui i pezzi "emergono" dall'alto nei puzzle game.
      baseOffsets = const [
        GridOffset(0, 0),
        GridOffset(0, -1),
        GridOffset(0, 1),
      ];

    case 4:
      // Quadrupla a "L":
      //   XXX
      //     X
      // Tre Puyo in fila e un quarto subito sotto a quello più a destra.
      // Il pivot è il blocco centrale della fila orizzontale: ruotando,
      // gli altri tre si dispongono in modo coerente attorno a lui — vedi
      // `GridOffset.rotatedClockwise`.
      baseOffsets = const [
        GridOffset(-1, 0),
        GridOffset(0, 0),
        GridOffset(1, 0),
        GridOffset(1, 1),
      ];

    default:
      // Quadrupla a "T" (non a "L"):
      //   X
      //   XX
      //   X
      // Tre Puyo impilati in verticale con un quarto attaccato sul fianco
      // destro di quello centrale. Il pivot è proprio il blocco centrale
      // — l'unico collegato a tutti gli altri tre — così la rotazione
      // (vedi `GridOffset.rotatedClockwise`) lo mantiene come perno fisso
      // e dispone gli altri tre coerentemente attorno a lui, un po' come
      // la "T" del Tetris.
      baseOffsets = const [
        GridOffset(0, 0),
        GridOffset(0, -1),
        GridOffset(0, 1),
        GridOffset(1, 0),
      ];
  }

  return _withRandomInitialAngle(baseOffsets, random);
}

/// Applica alla forma un numero CASUALE di rotazioni di 90° in senso
/// orario (da 0 a 3, cioè 0°/90°/180°/270°), così che ogni pezzo possa
/// comparire fin da subito con una qualunque delle sue angolazioni
/// possibili — esattamente come richiesto ("ogni elemento può essere
/// creato inizialmente con qualsiasi angolazione possibile scelta in
/// maniera casuale").
///
/// Riusa `GridOffset.rotatedClockwise`, lo stesso identico calcolo che
/// `FallingPiece` applica quando il giocatore preme la freccia Su: una
/// "rotazione iniziale casuale" non è altro che applicarlo, in anticipo,
/// un numero variabile di volte.
List<GridOffset> _withRandomInitialAngle(List<GridOffset> offsets, Random random) {
  final rotationSteps = random.nextInt(4);

  var rotated = offsets;
  for (var step = 0; step < rotationSteps; step++) {
    rotated = [for (final offset in rotated) offset.rotatedClockwise()];
  }
  return rotated;
}

/// Forma e colore di un pezzo, già decisi insieme. Generarli in coppia
/// (invece che separatamente, come faceva prima `FallingPiece`) è ciò che
/// permette di calcolare "il prossimo pezzo" con un anticipo di un turno:
/// lo si genera una volta, lo si usa per riempire l'anteprima a schermo, e
/// solo quando il pezzo CORRENTE si blocca lo si passa davvero a un nuovo
/// `FallingPiece`.
class PieceSpec {
  const PieceSpec({required this.offsets, required this.color});

  final List<GridOffset> offsets;
  final Color color;
}

/// I cinque colori tra cui viene scelto quello di ogni nuovo pezzo:
/// Rosso, Verde, Giallo, Blu, Rosa.
const _puyoColors = [
  Colors.red,
  Colors.green,
  Colors.yellow,
  Colors.blue,
  Colors.pink,
];

/// Da quanti "turni" (pezzi generati) ciascun colore non viene scelto.
///
/// È STATICA — e non un campo di istanza — perché questa "memoria" deve
/// persistere fra un pezzo e il successivo: ricreandola ad ogni pezzo
/// perderemmo la cronologia e torneremmo a una scelta puramente uniforme.
/// Tutti i pezzi della partita condividono la stessa mappa, proprio come
/// condividono la stessa sorgente `Random`.
final Map<Color, int> _turnsSinceColorWasPicked = {
  for (final color in _puyoColors) color: 0,
};

/// Sceglie il colore del prossimo pezzo con una casualità "pesata": più
/// turni sono passati dall'ultima volta che un colore è uscito, più alta
/// è la probabilità che esca ora — e simmetricamente, il colore appena
/// uscito riparte da un peso minimo, la probabilità più bassa possibile.
///
/// Tecnica: ad ogni colore assegniamo un peso pari a `turni_di_assenza +
/// 1` (il "+1" garantisce che anche il colore appena uscito abbia un peso
/// positivo, quindi possa comunque ripresentarsi, solo con probabilità
/// minima). Sommando i pesi otteniamo un intervallo totale; un numero
/// casuale in quell'intervallo "cade" in uno dei sotto-intervalli, in
/// proporzione al peso del colore — è l'algoritmo classico della
/// "selezione pesata" (roulette-wheel selection).
Color _pickNextPieceColor(Random random) {
  final weights = [
    for (final color in _puyoColors) _turnsSinceColorWasPicked[color]! + 1,
  ];
  final totalWeight = weights.reduce((sum, weight) => sum + weight);

  var roll = random.nextInt(totalWeight);
  var chosenIndex = _puyoColors.length - 1;
  for (var index = 0; index < weights.length; index++) {
    if (roll < weights[index]) {
      chosenIndex = index;
      break;
    }
    roll -= weights[index];
  }

  // Aggiorniamo la "memoria": il colore scelto torna a zero turni di
  // assenza (il suo peso scenderà al minimo), tutti gli altri ne
  // accumulano uno in più (il loro peso — e quindi la loro probabilità —
  // crescerà al prossimo giro).
  for (var index = 0; index < _puyoColors.length; index++) {
    final color = _puyoColors[index];
    _turnsSinceColorWasPicked[color] = index == chosenIndex ? 0 : _turnsSinceColorWasPicked[color]! + 1;
  }

  return _puyoColors[chosenIndex];
}

/// Genera la coppia forma+colore del prossimo pezzo. È la funzione che
/// `PuyoGame` chiama un turno in anticipo, per poter mostrare l'anteprima
/// a schermo prima ancora che quel pezzo diventi quello controllabile.
PieceSpec generatePieceSpec(Random random) {
  return PieceSpec(
    offsets: randomPieceOffsets(random),
    color: _pickNextPieceColor(random),
  );
}
