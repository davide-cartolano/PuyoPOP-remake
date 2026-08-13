/// Griglie precostruite della modalità Fever, una per lunghezza di combo.
///
/// Ogni board è descritta dall'alto verso il basso, una stringa per riga:
/// `.` = cella vuota, `0`-`4` = indice in `puyoColors` (vedi
/// `piece_shapes.dart`). Sono state GENERATE e VERIFICATE da uno script di
/// ricerca con costruzione a ritroso: ognuna è stabile così com'è, e basta
/// far scoppiare il gruppo "monco" in basso a sinistra (colonna 0/1) per
/// innescare una combo ESATTAMENTE della lunghezza dichiarata. Il test
/// `test/fever_presets_test.dart` riverifica questa proprietà a ogni run.
///
/// La colonna 0 è sempre vuota: è la colonna d'innesco — un pezzo del
/// colore giusto lasciato cadere lì completa il primo gruppo e fa partire
/// tutta la catena.
library;

/// Combo minima e massima disponibili come preset.
const int feverMinChain = 4;

int get feverMaxChain => feverMinChain + feverBoards.length - 1;

/// Board per la combo richiesta, con clamp sui limiti disponibili.
List<String> feverBoardForChain(int chain) {
  final index = (chain - feverMinChain).clamp(0, feverBoards.length - 1);
  return feverBoards[index];
}

const List<List<String>> feverBoards = [
  // Catena da 4 anelli.
  [
    '......',
    '......',
    '......',
    '......',
    '......',
    '......',
    '......',
    '.4....',
    '.4..2.',
    '.21.2.',
    '.2412.',
    '.24112',
  ],
  // Catena da 5 anelli.
  [
    '......',
    '......',
    '......',
    '......',
    '.4....',
    '.0....',
    '.2....',
    '.233..',
    '.243..',
    '.304..',
    '.304..',
    '.3203.',
  ],
  // Catena da 6 anelli.
  [
    '......',
    '......',
    '...0..',
    '...0..',
    '...0..',
    '...2..',
    '.3.2..',
    '.2.4..',
    '.2.4..',
    '.4340.',
    '.4232.',
    '.42342',
  ],
  // Catena da 7 anelli.
  [
    '......',
    '......',
    '......',
    '......',
    '.....3',
    '.....3',
    '.11..3',
    '.12..4',
    '.023.4',
    '.32134',
    '.30243',
    '.30033',
  ],
  // Catena da 8 anelli.
  [
    '....1.',
    '....2.',
    '....2.',
    '....2.',
    '....4.',
    '....4.',
    '....0.',
    '.1420.',
    '.13431',
    '.32031',
    '.31321',
    '.31220',
  ],
  // Catena da 9 anelli.
  [
    '.3.0..',
    '.2.2..',
    '.2.2..',
    '.2.2..',
    '.4.3..',
    '.4.4..',
    '.131..',
    '.031..',
    '.023..',
    '.2430.',
    '.21320',
    '.20030',
  ],
  // Catena da 10 anelli.
  [
    '...40.',
    '...42.',
    '...02.',
    '...03.',
    '...33.',
    '...110',
    '...142',
    '...442',
    '.44101',
    '.04104',
    '.03410',
    '.04410',
  ],
  // Catena da 11 anelli.
  [
    '....4.',
    '....2.',
    '.4..2.',
    '.14.2.',
    '.24.3.',
    '.2043.',
    '.2031.',
    '.44012',
    '.41423',
    '.31421',
    '.32121',
    '.34402',
  ],
  // Catena da 12 anelli.
  [
    '......',
    '....0.',
    '..440.',
    '..232.',
    '.21320',
    '.11320',
    '.20242',
    '.20241',
    '.24131',
    '.04001',
    '.04212',
    '.02422',
  ],
];
