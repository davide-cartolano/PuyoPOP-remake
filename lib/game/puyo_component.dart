import 'dart:async';
import 'dart:math' show Random, cos, pi, sin;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/particles.dart';

import 'grid_component.dart';

/// Rappresenta un singolo Puyo: un cerchio colorato disegnato in una
/// precisa cella della griglia.
///
/// Da questo step in poi, `PuyoComponent` è deliberatamente "ignorante":
/// non gestisce input, non cade da solo, non sa nulla del gioco. Sa solo
/// due cose — "in quale cella mi trovo" e "che colore sono" — e si occupa
/// di disegnarsi correttamente in quella cella. Tutta l'intelligenza
/// (movimento, gravità, rotazione, collisioni) vive ora in `FallingPiece`,
/// che possiede e orchestra i `PuyoComponent` come un gruppo.
///
/// Lo stesso identico componente viene riusato sia per i blocchi del
/// pezzo attualmente controllabile, sia — una volta che il pezzo si
/// blocca — per i Puyo ormai fermi e impilati sul fondo: la differenza
/// non sta nel componente, ma in CHI lo controlla (o smette di farlo).
class PuyoComponent extends PositionComponent {
  /// Colonna corrente (0 = colonna più a sinistra).
  int column;

  /// Riga corrente (0 = riga più in alto).
  int row;

  /// Colore del Puyo. Determina anche, nei prossimi step, quali Puyo
  /// possono "scoppiare" insieme.
  final Color color;

  /// Vero per un Puyo "spazzatura" (bianco), inviato dall'avversario dopo
  /// una sua combo (vedi `PuyoGame._resolveBoardThenSpawnNext` e
  /// `PlayfieldGrid.findAdjacentGarbage`). Un Puyo spazzatura non si unisce
  /// mai a un gruppo — il suo colore non coincide con nessuno dei colori
  /// di gioco — ma scompare insieme a un gruppo che scoppia se gli è
  /// adiacente: è così che ostacola l'avversario senza poter scoppiare da
  /// solo.
  final bool isGarbage;

  /// Sorgente di casualità per il battito di ciglia (vedi sotto): è
  /// un'istanza per Puyo, così ognuno sbatte le palpebre con un proprio
  /// ritmo indipendente, invece che tutti all'unisono.
  final Random _random = Random();

  /// Quanto manca (in secondi) al prossimo battito di ciglia.
  double _timeUntilNextBlink = 0;

  /// Quanto manca (in secondi) alla fine del battito di ciglia in corso;
  /// quando è positivo, gli occhi vengono disegnati chiusi.
  double _blinkTimeRemaining = 0;

  /// Durata di un singolo battito di ciglia.
  static const double _blinkDuration = 0.12;

  PuyoComponent({
    required this.column,
    required this.row,
    required this.color,
    this.isGarbage = false,
  }) : super(
          // Il Puyo occupa esattamente una cella della griglia.
          size: Vector2.all(GridComponent.cellSize),
          // Anchor.topLeft: `position` indica l'angolo in alto a sinistra
          // del componente, in linea con il modo in cui GridComponent
          // disegna le celle (a partire da (colonna*cellSize,
          // riga*cellSize)). Questo rende l'allineamento immediato.
          anchor: Anchor.topLeft,
        ) {
    moveTo(column, row);
    _timeUntilNextBlink = _randomBlinkInterval();
  }

  /// Intervallo casuale, in secondi, fino al prossimo battito di ciglia:
  /// senza questa variazione tutti i Puyo sbatterebbero le palpebre
  /// esattamente nello stesso istante, un effetto meccanico che la
  /// casualità per-istanza evita.
  double _randomBlinkInterval() => 1.5 + _random.nextDouble() * 3.5;

  @override
  void update(double dt) {
    super.update(dt);

    if (_blinkTimeRemaining > 0) {
      _blinkTimeRemaining -= dt;
      return;
    }

    _timeUntilNextBlink -= dt;
    if (_timeUntilNextBlink <= 0) {
      _blinkTimeRemaining = _blinkDuration;
      _timeUntilNextBlink = _randomBlinkInterval();
    }
  }

  /// Sposta questo Puyo in una nuova cella della griglia, ricalcolando
  /// subito la sua posizione in pixel di conseguenza.
  ///
  /// `verticalOffset` aggiunge un piccolo spostamento continuo (in pixel)
  /// rispetto al bordo superiore esatto della cella `newRow`. Serve per la
  /// caduta fluida: il Puyo "appartiene" già logicamente a `newRow` (è così
  /// che viene trattato dalle collisioni), ma visivamente sta ancora
  /// scivolando verso di essa, qualche pixel più in alto. Quando vale 0,
  /// il Puyo è perfettamente allineato alla griglia.
  ///
  /// È il metodo che `FallingPiece` chiama per spostare, far cadere o
  /// ruotare i blocchi che possiede: questo componente si limita ad
  /// "obbedire" e a ridisegnarsi nel posto giusto.
  void moveTo(int newColumn, int newRow, {double verticalOffset = 0}) {
    column = newColumn;
    row = newRow;
    position = Vector2(
      column * GridComponent.cellSize,
      row * GridComponent.cellSize + verticalOffset,
    );
  }

  /// Anima lo scivolamento verso la cella indicata da `column`/`row`
  /// CORRENTI, partendo dalla posizione visiva attuale, in `duration`
  /// secondi — è il modo in cui rendiamo "visibile" la gravità globale,
  /// invece di far scattare i Puyo istantaneamente da una cella all'altra.
  ///
  /// Si aspetta che chi la chiama (`PlayfieldGrid.applyGravity`) abbia
  /// GIÀ aggiornato lo stato logico (`column`/`row`) prima di invocarla:
  /// il resto del gioco deve poter considerare il Puyo arrivato a
  /// destinazione mentre l'occhio lo vede ancora scendere — lo stesso
  /// principio già visto con `_fallProgressPixels` in `FallingPiece`.
  ///
  /// Restituisce un Future che si completa alla fine dell'animazione:
  /// è il modo in cui `PuyoGame` sa quando può proseguire (es. controllare
  /// se la caduta ha appena formato un nuovo gruppo da far scoppiare).
  Future<void> fallTo({double duration = 0.2}) {
    final completer = Completer<void>();
    add(
      MoveToEffect(
        Vector2(
          column * GridComponent.cellSize,
          row * GridComponent.cellSize,
        ),
        EffectController(duration: duration),
        onComplete: completer.complete,
      ),
    );
    return completer.future;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Piccolo margine interno: il cerchio non tocca i bordi della cella,
    // così resta visibile la linea della griglia sotto il Puyo.
    const padding = 4.0;
    final radius = (size.x - padding * 2) / 2;
    final center = Offset(size.x / 2, size.y / 2);

    if (isGarbage) {
      // I Puyo spazzatura hanno lo stesso viso (e battito di ciglia) dei
      // Puyo colorati, ma un corpo bianco leggermente trasparente: basta
      // a renderli distinguibili a colpo d'occhio senza farli sembrare
      // un elemento completamente estraneo al resto del gioco.
      paintGarbagePuyo(canvas, center: center, radius: radius, eyesClosed: _blinkTimeRemaining > 0);
      return;
    }

    paintPuyo(canvas, center: center, radius: radius, color: color, eyesClosed: _blinkTimeRemaining > 0);
  }

  /// Anima lo "scoppio" di questo Puyo quando fa parte di un gruppo che
  /// viene eliminato: un breve rigonfiamento seguito da un collasso a
  /// dimensione zero, invece della scomparsa istantanea che si aveva
  /// prima. Il `Future` restituito si completa a fine animazione — è
  /// quello che permette a `PuyoGame` di attendere l'effetto prima di
  /// rimuovere davvero il componente dall'albero.
  Future<void> playPopEffect() {
    final completer = Completer<void>();

    // L'ancoraggio normale (Anchor.topLeft) è comodo per allinearsi alla
    // griglia, ma scalerebbe il Puyo a partire dal suo angolo in alto a
    // sinistra invece che dal centro. Passiamo qui all'ancoraggio
    // centrale, ricalcolando `position` per non far "saltare" visivamente
    // il componente: dato che si tratta dell'ultimo istante di vita del
    // Puyo (verrà rimosso a fine animazione), non serve riportarlo indietro.
    position = position + size / 2;
    anchor = Anchor.center;

    add(
      SequenceEffect(
        [
          ScaleEffect.to(Vector2.all(1.3), EffectController(duration: 0.08)),
          ScaleEffect.to(Vector2.zero(), EffectController(duration: 0.14)),
        ],
        onComplete: completer.complete,
      ),
    );
    return completer.future;
  }

  /// Anima un breve "schiacciamento elastico" quando il pezzo tocca terra
  /// e si blocca: prima si appiattisce (largo e basso), poi rimbalza in
  /// senso opposto (stretto e alto), infine torna alla scala normale. Non
  /// serve attendere il completamento — è solo un tocco cosmetico — quindi
  /// a differenza di `playPopEffect` questo metodo non espone un Future.
  void playLandSquashEffect() {
    add(
      SequenceEffect([
        ScaleEffect.to(Vector2(1.18, 0.78), EffectController(duration: 0.07)),
        ScaleEffect.to(Vector2(0.92, 1.1), EffectController(duration: 0.08)),
        ScaleEffect.to(Vector2.all(1), EffectController(duration: 0.08)),
      ]),
    );
  }
}

/// Disegna un Puyo spazzatura: una sfera bianca lucida come un Puyo
/// normale, con lo stesso viso (occhi + battito di ciglia), ma
/// leggermente trasparente — è il "macigno" che il gioco originale fa
/// cadere sull'avversario dopo una combo, e che non scoppia mai da solo
/// (vedi `PuyoComponent.isGarbage`). La trasparenza è ciò che lo
/// distingue a colpo d'occhio dai Puyo colorati, pur restando coerente
/// visivamente con loro.
void paintGarbagePuyo(Canvas canvas, {required Offset center, required double radius, bool eyesClosed = false}) {
  const garbageColor = Color(0xFFFAFAFF);
  const opacity = 0.7;

  final bodyPaint = Paint()
    ..shader = Gradient.radial(
      center.translate(-radius * 0.35, -radius * 0.35),
      radius * 1.4,
      [
        const Color(0xFFFFFFFF).withValues(alpha: opacity),
        garbageColor.withValues(alpha: opacity),
      ],
    );
  canvas.drawCircle(center, radius, bodyPaint);

  final outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFFD0D0DC).withValues(alpha: opacity);
  canvas.drawCircle(center, radius, outlinePaint);

  _renderFace(canvas, center, radius, eyesClosed);
}

/// Disegna un Puyo (corpo lucido + viso) centrato in `center`, con il
/// raggio indicato. È una funzione libera, non un metodo di
/// `PuyoComponent`, proprio per poter essere riusata anche da
/// `NextPiecePreviewComponent`, che deve disegnare la stessa identica
/// faccina ma più piccola e senza essere un Puyo "vero" della griglia.
void paintPuyo(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required Color color,
  bool eyesClosed = false,
}) {
  // Corpo: un gradiente radiale (più chiaro verso l'alto a sinistra)
  // simula una piccola fonte di luce e dà al cerchio l'aspetto lucido e
  // "gommoso" tipico dei Puyo, invece di un semplice riempimento piatto.
  final bodyPaint = Paint()
    ..shader = Gradient.radial(
      center.translate(-radius * 0.35, -radius * 0.35),
      radius * 1.4,
      [_lighten(color, 0.45), color],
    );
  canvas.drawCircle(center, radius, bodyPaint);

  final outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = _darken(color, 0.35);
  canvas.drawCircle(center, radius, outlinePaint);

  _renderFace(canvas, center, radius, eyesClosed);
}

/// Disegna gli occhi (bianchi con pupilla e riflesso, o un trattino se
/// `eyesClosed` — il battito di ciglia) e la boccuccia: è questo
/// dettaglio del viso, più del colore, a rendere ogni Puyo riconoscibile
/// come un personaggio e non solo come una pallina colorata.
void _renderFace(Canvas canvas, Offset bodyCenter, double bodyRadius, bool eyesClosed) {
  final eyeOffset = Offset(bodyRadius * 0.38, -bodyRadius * 0.05);
  final eyeRadius = bodyRadius * 0.34;
  final pupilRadius = eyeRadius * 0.48;

  if (eyesClosed) {
    final closedEyePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyRadius * 0.12
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1B1B2F);

    for (final side in [-1, 1]) {
      final eyeCenter = bodyCenter.translate(eyeOffset.dx * side, eyeOffset.dy);
      canvas.drawLine(
        eyeCenter.translate(-eyeRadius * 0.7, 0),
        eyeCenter.translate(eyeRadius * 0.7, 0),
        closedEyePaint,
      );
    }
  } else {
    final eyeWhitePaint = Paint()..color = const Color(0xFFFFFFFF);
    final pupilPaint = Paint()..color = const Color(0xFF1B1B2F);
    final shinePaint = Paint()..color = const Color(0xFFFFFFFF);

    for (final side in [-1, 1]) {
      final eyeCenter = bodyCenter.translate(eyeOffset.dx * side, eyeOffset.dy);

      canvas.drawCircle(eyeCenter, eyeRadius, eyeWhitePaint);

      final pupilCenter = eyeCenter.translate(0, eyeRadius * 0.1);
      canvas.drawCircle(pupilCenter, pupilRadius, pupilPaint);

      final shineCenter = pupilCenter.translate(-pupilRadius * 0.35, -pupilRadius * 0.35);
      canvas.drawCircle(shineCenter, pupilRadius * 0.35, shinePaint);
    }
  }

  // Boccuccia: un semplice arco a "v" rovesciata sotto gli occhi.
  final mouthPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = bodyRadius * 0.1
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF1B1B2F);

  final mouthRect = Rect.fromCenter(
    center: bodyCenter.translate(0, bodyRadius * 0.32),
    width: bodyRadius * 0.7,
    height: bodyRadius * 0.5,
  );
  canvas.drawArc(mouthRect, 0.15 * pi, pi - 0.3 * pi, false, mouthPaint);
}

/// Disegna la "controfigura" semitrasparente di un Puyo, usata per
/// mostrare in anteprima dove atterrerebbe il pezzo se lo si lasciasse
/// cadere da subito (il "ghost piece" dei puzzle game ad incastro). A
/// differenza di `paintPuyo`, niente gradiente né viso: solo un disco e
/// un contorno tenui, per non confondersi visivamente con i Puyo veri.
void paintPuyoGhost(Canvas canvas, {required Offset center, required double radius, required Color color}) {
  final fillPaint = Paint()..color = color.withAlpha(50);
  canvas.drawCircle(center, radius, fillPaint);

  final outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = color.withAlpha(160);
  canvas.drawCircle(center, radius, outlinePaint);
}

Color _lighten(Color base, double amount) => Color.lerp(base, const Color(0xFFFFFFFF), amount)!;

Color _darken(Color base, double amount) => Color.lerp(base, const Color(0xFF000000), amount)!;

/// Numero di particelle generate da ogni scoppio: un compromesso fra un
/// effetto ben visibile e il costo di disegnarle tutte.
const _burstParticleCount = 10;

/// Crea un piccolo "scoppio" di particelle colorate centrato su
/// `position`, da accompagnare alla scomparsa di un Puyo. Ogni particella
/// parte in una direzione diversa (distribuite a raggiera) con una
/// leggera accelerazione verso il basso, per dare un minimo di peso
/// fisico all'esplosione invece di un'espansione perfettamente uniforme.
///
/// Restituisce un `ParticleSystemComponent` già pronto da aggiungere al
/// gioco: si rimuove da solo (vedi `Particle`/`ParticleSystemComponent` di
/// Flame) una volta esaurita la propria `lifespan`, senza bisogno che
/// `PuyoGame` se ne occupi.
ParticleSystemComponent createPuyoBurst({required Vector2 position, required Color color}) {
  final particle = Particle.generate(
    count: _burstParticleCount,
    lifespan: 0.4,
    generator: (index) {
      final angle = (index / _burstParticleCount) * 2 * pi;
      final speed = Vector2(cos(angle), sin(angle)) * 90;
      return AcceleratedParticle(
        speed: speed,
        acceleration: Vector2(0, 160),
        child: CircleParticle(radius: 3, paint: Paint()..color = color),
      );
    },
  );

  return ParticleSystemComponent(position: position, particle: particle);
}
