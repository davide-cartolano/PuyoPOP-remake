import 'package:flutter_test/flutter_test.dart';

import 'package:puyopop_feveer/game/fever_presets.dart';
import 'package:puyopop_feveer/game/grid_component.dart';
import 'package:puyopop_feveer/game/piece_shapes.dart';
import 'package:puyopop_feveer/game/playfield_grid.dart';
import 'package:puyopop_feveer/game/puyo_component.dart';

/// Carica una board precostruita dentro una PlayfieldGrid vera.
PlayfieldGrid _loadBoard(List<String> rows) {
  final grid = PlayfieldGrid();
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < rows[row].length; column++) {
      final cell = rows[row][column];
      if (cell == '.') continue;
      final puyo = PuyoComponent(column: column, row: row, color: puyoColors[int.parse(cell)]);
      expect(grid.lock(puyo), isTrue);
    }
  }
  return grid;
}

/// Risolve la griglia con le STESSE regole di PuyoGame (gravità → scoppi →
/// gravità...) e restituisce il numero totale di gruppi scoppiati — che è
/// esattamente il contatore di combo mostrato in partita.
int _resolve(PlayfieldGrid grid) {
  var totalGroups = 0;
  while (true) {
    grid.applyGravity();
    final groups = grid.findGroupsToClear();
    if (groups.isEmpty) return totalGroups;
    totalGroups += groups.length;
    for (final group in groups) {
      grid.clear(group);
    }
    grid.clear(grid.findAdjacentGarbage(groups));
  }
}

void main() {
  test('ogni board Fever è stabile finché non viene innescata', () {
    for (var chain = feverMinChain; chain <= feverMaxChain; chain++) {
      final grid = _loadBoard(feverBoardForChain(chain));
      expect(_resolve(grid), 0, reason: 'la board della combo $chain non deve scoppiare da sola');
    }
  });

  test('ogni board Fever, innescata in colonna 0, produce la combo dichiarata', () {
    for (var chain = feverMinChain; chain <= feverMaxChain; chain++) {
      final rows = feverBoardForChain(chain);
      final grid = _loadBoard(rows);

      // Il colore d'innesco è quello del gruppo "monco" in fondo alla
      // colonna 1: un puyo di quel colore lasciato cadere in colonna 0
      // (vuota per costruzione) completa il gruppo e avvia la catena.
      final triggerColor = grid.colorAt(1, GridComponent.rows - 1);
      expect(triggerColor, isNotNull);

      final trigger = PuyoComponent(column: 0, row: GridComponent.rows - 1, color: triggerColor!);
      expect(grid.lock(trigger), isTrue);

      expect(_resolve(grid), chain, reason: 'la board della combo $chain deve produrre esattamente $chain gruppi');
    }
  });
}
