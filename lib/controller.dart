/*
 Copyright (C) 2021, William Foote

 Author: William Foote

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' as ui;
import 'package:pedantic/pedantic.dart';
import 'package:quiver/collection.dart' as quiver;
import 'package:quiver/core.dart' as quiver;

import 'constants.dart';
import 'graphics.dart';
import 'game.dart';

class ChangeNotifier extends ui.ChangeNotifier {
  // Make it public
  @override
  void notifyListeners() => super.notifyListeners();
}

///
/// Controller and view manager for Solitaire.  The GameController manages
/// the positions of the graphical assets.  The view should register as a
/// listener via the `ChangeNotifier` API.
///
class GameController<ST extends Slot> extends ChangeNotifier {
  Game<ST> _game;
  Game<ST> get game => _game;
  final List<bool> hasExtendedSlots;
  final List<double> rowHeight;
  final gameChangeNotifier = ChangeNotifier();

  /// size in card widths/card heights, not accounting for extended slots
  final ui.Size sizeInCards;
  final int extendedSlotRowCount;

  /// Set by GameState, and changed when the card sizes might change.
  late CardFinder<ST> _finder;

  /// Set and updated by GameState.
  late GamePainter _painter;

  Drag<ST>? drag;
  FoundCard<ST>? doubleClickCard;
  _GameAnimation<ST>? _inFlight;
  MovingStack<ST>? get movement => drag ?? _inFlight;

  GameController._p(this._game, this.sizeInCards, List<bool> hasExtendedSlots,
      List<double> rowHeight)
      : hasExtendedSlots = List.unmodifiable(hasExtendedSlots),
        rowHeight = List.unmodifiable(rowHeight),
        extendedSlotRowCount =
            hasExtendedSlots.fold(0, (count, v) => v ? (count + 1) : count);

  factory GameController(Game<ST> game) {
    final hasExtendedSlots = List<bool>.empty(growable: true);
    final rowHeight = List<double>.empty(growable: true);
    double height = 0;
    double width = 0;
    double rowH = 0;
    double rowW = 0;
    bool extendedSeen = false;
    for (final s in game.slots) {
      s.visit(normal: (slot) {
        rowW++;
        rowH = max(rowH, 1);
      }, extended: (slot) {
        extendedSeen = true;
        rowH = max(rowH, 1);
        rowW++;
      }, cr: (slot) {
        width = max(width, rowW);
        hasExtendedSlots.add(extendedSeen);
        rowHeight.add(rowH + slot.extraHeight);
        height += rowH + slot.extraHeight;
        rowW = rowH = 0;
        extendedSeen = false;
      }, horizontalSpace: (slot) {
        rowW += slot.width;
      });
    }
    return GameController<ST>._p(
        game, ui.Size(width, height), hasExtendedSlots, rowHeight);
  }

  GamePainter get painter => _painter;
  set painter(GamePainter v) {
    _painter = v;
    _finder = CardFinder<ST>(_painter);
  }

  ui.Size get screenSize => painter.lastPaintSize;
  double get cardWidth => screenSize.width / sizeInCards.width;

  void doubleClickStart(ui.Offset pos) {
    pos = addPaintOffset(pos);
    final f = _finder.find(pos, this);
    if (f != null) {
      doubleClickCard = f;
    }
  }

  void _finishPending() {
    while (_inFlight != null) {
      _inFlight!.finish();
    }
  }

  void doubleClick() {
    final dc = doubleClickCard;
    if (dc == null) {
      return;
    }
    _finishPending();
    final List<Move<ST>> todo = game.doubleClick(dc);
    if (todo.isEmpty) {
      return;
    }
    _inFlight = _GameAnimation(this, todo, () => doAutomaticMoves());
  }

  void clickStart(ui.Offset pos) {
    pos = addPaintOffset(pos);
    // final f = finder.find(pos, size, this);
  }

  void click() {}

  void dragStart(ui.Offset pos) {
    pos = addPaintOffset(pos);
    final f = _finder.find(pos, this);
    if (f != null && game.board.canSelect(f)) {
      _finishPending();
      drag = Drag(f, pos);
      notifyListeners();
    }
  }

  void dragMove(ui.Offset pos) {
    pos = addPaintOffset(pos);
    final d = drag;
    if (d != null) {
      d.current = pos;
      notifyListeners();
    }
  }

  void dragCancel() {
    drag = null;
    notifyListeners();
  }

  void dragEnd() {
    final d = drag;
    if (d != null) {
      final area = d.card.area
          .translate(d.current.dx - d.start.dx, d.current.dy - d.start.dy);
      final ST? dest = _finder.findSlot(area, this);
      if (dest != null &&
          dest != d.card.slot &&
          game.board.canDrop(d.card, dest)) {
        final move = Move(src: d.card, dest: dest, automatic: false);
        move.move();
        addUndo(UndoRecord(move));
        doAutomaticMoves();
      }
    }
    drag = null;
    notifyListeners();
  }

  void doAutomaticMoves([void Function() onDone = _nop]) {
    assert(_inFlight == null);
    final newMoves = game.board.automaticMoves();
    if (newMoves.isEmpty) {
      onDone();
    } else {
      _inFlight =
          _GameAnimation(this, newMoves, () => doAutomaticMoves(onDone));
      notifyListeners();
    }
  }

  static void _nop() {}

  ui.Offset addPaintOffset(ui.Offset pos) => (_painter.lastPaintOffset == 0.0)
      ? pos
      : ui.Offset(pos.dx - _painter.lastPaintOffset, pos.dy);

  void solve() {
    final scratch = game.board.makeSearchBoard();
    painter.currentSearch = scratch;
    final initial = scratch.slotData;
    print('@@ Solving ${scratch.toExternal()}');
    final q = PriorityQueue<SearchSlotData>(
        (a, b) => b.goodness.compareTo(a.goodness));
    final seen = HashSet<List<int>>(
        equals: quiver.listsEqual, hashCode: quiver.hashObjects);
    scratch.doAllAutomaticMoves();
    scratch.canonicalize();
    seen.add(scratch.slotData.raw);
    final sw = Stopwatch()..start();
    scratch.calculateChildren(scratch, (k) {
      k.timeCreated = sw.elapsedTicks / sw.frequency;
      seen.add(k.raw);
      q.add(k);
      return true;
    });
    double nextFrame = 0.25 * sw.frequency;
    unawaited(() async {
      int iterations = 0;
      while (q.isNotEmpty && seen.length < 100000000) {
        final k = q.removeFirst();
        if (sw.elapsedTicks > nextFrame) {
          nextFrame += 0.25 * sw.frequency;
          notifyListeners();
          print('@@ $iterations iterations');
          await Future<void>.delayed(Duration(milliseconds: 5));
        }
        scratch.slotData = k;
        if (scratch.gameWon) {
          print('@@@@ ==> Found after $iterations iterations, '
              'duration ${sw.elapsed}.');
          sw.stop();
          scratch.slotData = initial;
          SearchSlotData? next = k;
          final path = List.generate(k.depth + 1, (_) {
            final sd = next!;
            next = sd.from;
            return sd;
          });
          final solution = Solution(path, scratch);
          assert(next == null);
          print('@@ Done - created ${seen.length} arrangements.');
          painter.currentSearch = null;
          solution.run(this);
          return;
        }
        iterations++;
        scratch.calculateChildren(scratch, (final SearchSlotData kk) {
          if (seen.add(kk.raw)) {
            kk.timeCreated = sw.elapsedTicks / sw.frequency;
            q.add(kk);
            return true;
          } else {
            return false;
          }
        });
      }
      if (q.isEmpty) {
        print('@@ No solution.  Saw ${seen.length} arrangements.');
      } else {
        print('@@ Gave up after $iterations iterations, '
            '${seen.length} arrangements.');
      }
      painter.currentSearch = null;
      notifyListeners();
    }());
  }

  void _changeGame(void Function() f) {
    bool oldUndo = game.canUndo;
    bool oldRedo = game.canRedo;
    f();
    if ((game.canRedo != oldRedo) || (game.canUndo != oldUndo)) {
      gameChangeNotifier.notifyListeners();
    }
  }

  void addUndo(UndoRecord<ST> u) {
    _changeGame(() => game.addUndo(u));
  }

  void newGame() {
    _finishPending();
    _game = game.newGame();
    notifyListeners();
    gameChangeNotifier.notifyListeners();
  }

  void undo() {
    if (_inFlight != null) {
      _inFlight!.finish();
      _inFlight?.cancel();
      _inFlight = null;
      notifyListeners();
    }
    if (game.canUndo) {
      UndoRecord<ST>? undoN;
      _changeGame(() {
        undoN = game.takeUndo();
      });
      final u = undoN!;
      u.printComment();
      final Card bottom = u.dest.cardDownFromTop(u.numCards - 1);
      final cs = CardStack(u.dest, u.numCards, bottom);
      final move = Move(src: cs, dest: u.src, automatic: u.automatic);
      _inFlight = _GameAnimation<ST>(this, [move], () {
        if (u.automatic) {
          undo();
        }
      }, isUndo: true);
      notifyListeners();
    }
  }

  void redo({bool onlyAutomatic = false}) {
    _finishPending();
    if (game.canRedo) {
      UndoRecord<ST>? undoN;
      _changeGame(() {
        undoN = game.takeRedo(onlyAutomatic: onlyAutomatic);
      });
      if (undoN == null) {
        return;
      }
      final u = undoN!;
      u.printComment();
      final Card bottom = u.src.cardDownFromTop(u.numCards - 1);
      final cs = CardStack(u.src, u.numCards, bottom);
      final move = Move(src: cs, dest: u.dest, automatic: u.automatic);
      _inFlight = _GameAnimation<ST>(this, [move], () {
        redo(onlyAutomatic: true);
      }, isUndo: true);
      notifyListeners();
    }
  }
}

///
/// A solution of this game.  The data structure looks like this:
/// <pre>
///              from ┌──────┐      ┌──────┐          ┌──────┐         ┌──────┐
///             ┌─────┤ null │ from │  m1  │   from   │  m2  │  from   │  m3  │
///             ▼     │      │◄─────┤      │◄─────────┤      │◄────────┤      │
///            ───    │      │      │      │          │      │         │      │
///            ///    │  s0  │      │ s1   │          │ s2   │         │ s3   │
///       auto,canon  │      │      │      │          │      │         │      │
///      ┌──────────► │      │      └────┬─┘          └───┬──┘         └──────┘
///      │            └──┬───┘       ▲   │m2          ▲   │m3            ▲
/// ┌────┴──┐            │m1         │   │            │   │              │
/// │ start │            ▼           │   ▼            │   ▼              │
/// │       │           ┌──┐         │  ┌──┐          │ ┌──┐             │
/// │       │           │b1├─────────┘  │b2├──────────┘ │b3├─────────────┘
/// │       │           └──┘auto,canon  └──┘ auto,canon └──┘ auto,canon
/// │       │
/// └───────┘
///
/// </pre>
/// Each box is a board arrangement; SearchSlotData instances are along the
/// top, where m? is viaXXX.  For the pictured graph, path would contain
/// [s3, s2, s1, s0].
///
class Solution<ST extends Slot> {
  /// The path to the solution, in reverse order.
  /// path[0] is the solved game.
  final List<SearchSlotData> path;

  int nextStep;

  /// For nextStep, the map from the slot numbers in
  /// path[nextStep].viaXXX to the real game board.  This moves around
  /// due to slot canonicalization.
  final List<int> slotMap;

  /// A board we can modify as we go
  final Board<ST, SearchSlotData> scratch;

  Solution(List<SearchSlotData> path, Board<ST, SearchSlotData> scratch)
      : path = path,
        nextStep = path.length - 1,
        scratch = scratch,
        slotMap = List<int>.generate(scratch.numSlots, (i) => i);

  bool get done => nextStep < 0;

  void run(GameController<ST> controller) {
    print('@@ Solution has ${path.length} steps');
    assert(path.isEmpty || path[path.length - 1].from == null);
    controller.doAutomaticMoves(() => _moveCompleted(controller));
  }

  /// Now, both scrath and game are at one of the "s" states along the top.
  void _moveCompleted(GameController<ST> controller) {
    int nextEmptySlot = 0;
    final board = controller.game.board;
    assert(NDEBUG ||
        quiver.listsEqual(
            (board.makeSearchBoard()..canonicalize()).slotData.raw,
            scratch.slotData.raw));
    assert(NDEBUG ||
        () {
          slotMap.fillRange(0, slotMap.length, -1);
          return true;
        }());
    for (int i = 0; i < slotMap.length; i++) {
      final realSlot = board.slotFromNumber(i);
      int canonicalized = -1;
      if (realSlot.isEmpty) {
        while (scratch.slotFromNumber(nextEmptySlot).isNotEmpty) {
          nextEmptySlot++;
        }
        canonicalized = scratch.slotFromNumber(nextEmptySlot++).slotNumber;
      } else {
        final Card top = realSlot.top;
        for (int j = 0; j < scratch.numSlots; j++) {
          final s = scratch.slotFromNumber(j);
          if (s.isNotEmpty && s.top == top) {
            canonicalized = j;
            break;
          }
        }
      }
      slotMap[canonicalized] = i;
    }
    assert(NDEBUG || !slotMap.any((v) => v < 0));
    _takeNextStep(controller);
  }

  /// The first time through, scratch is at the state state s0, then s1, etc.
  void _takeNextStep(GameController<ST> controller) {
    nextStep--;
    if (nextStep < 0) {
      assert(controller.game.board.gameWon);
      return;
    }
    final step = path[nextStep];
    scratch.slotData = step;
    unawaited(() async {
/*
      controller.notifyListeners();
      await Future<void>.delayed(Duration(seconds: 1));
      controller.painter.currentSearch = scratch;
      controller.notifyListeners();
      await Future<void>.delayed(Duration(seconds: 1));
      controller.painter.currentSearch = null;
      controller.notifyListeners();
      await Future<void>.delayed(Duration(seconds: 1));
 */
      final board = controller.game.board;
      final srcSlot = board.slotFromNumber(slotMap[step.viaSlotFrom]);
      final Card bottom = srcSlot.cardDownFromTop(step.viaNumCards - 1);
      final src = CardStack(srcSlot, step.viaNumCards, bottom);
      final dest = board.slotFromNumber(slotMap[step.viaSlotTo]);
      final move = Move(src: src, dest: dest, automatic: false);
      assert(NDEBUG || controller._inFlight == null);
      assert(NDEBUG || board.canSelect(src));
      assert(NDEBUG ||
          board.canDrop(
              FoundCard(srcSlot, step.viaNumCards, bottom, ui.Rect.zero),
              dest));
      controller._inFlight = _GameAnimation<ST>(controller, [move],
          () => controller.doAutomaticMoves(() => _moveCompleted(controller)),
          debugComment: 'Step generated at ${step.timeCreated}');
    }());
  }
}

abstract class MovingStack<ST extends Slot> implements CardStack<ST> {
  double get dx;
  double get dy;
}

class Drag<ST extends Slot> implements MovingStack<ST> {
  final FoundCard<ST> card;
  final ui.Offset start;
  ui.Offset current;

  Drag(this.card, ui.Offset start)
      : start = start,
        current = start;

  @override
  int get numCards => card.numCards;

  @override
  ST get slot => card.slot;

  @override
  Card get bottom => card.bottom;

  @override
  double get dx => current.dx - start.dx;

  @override
  double get dy => current.dy - start.dy;
}

class _GameAnimation<ST extends Slot> implements MovingStack<ST> {
  final GameController<ST> controller;
  final List<Move<ST>> moves;
  final void Function() onFinished;
  final bool isUndo;
  final String? debugComment;
  int move = 0;
  final Stopwatch time = Stopwatch();
  int lastTicks = 0;
  late final Timer timer;
  ui.Offset movePos = ui.Offset.zero;
  ui.Offset moveDest = ui.Offset.zero;

  static const double speed = 150; // card widths/second

  _GameAnimation(this.controller, this.moves, this.onFinished,
      {this.isUndo = false, this.debugComment}) {
    timer = Timer.periodic(
        Duration(microseconds: (1000000 / 300).ceil()), _timerTick);
    // 300 Hz is faster than needed, but the amount of work done here is
    // trivial.  This lets the Flutter engine display frames basically as
    // fast as it likes.
    time.start();
    _setPositions();
  }

  bool get finished => move >= moves.length;

  void _setPositions() {
    while (!finished && !moves[move].animate) {
      takeMove(moves[move++]);
    }
    if (finished) {
      finish();
    } else {
      final m = moves[move];
      movePos = ui.Offset.zero;
      var startPos = controller._finder.cardPos(m.bottom, controller);
      var endPos = controller._finder.nextCardPos(m.dest, controller);
      moveDest = endPos - startPos;
    }
    show();
  }

  void _timerTick(Timer _) {
    final elapsedTicks = time.elapsedTicks;
    double seconds = (elapsedTicks - lastTicks).toDouble() / time.frequency;
    lastTicks = elapsedTicks;
    double dist = seconds * speed * controller.cardWidth;
    while (dist > 0) {
      final delta = moveDest - movePos;
      final deltaD = delta.distance;
      if (deltaD > dist) {
        movePos += delta * (dist / deltaD);
        show();
        break;
      } else {
        dist -= deltaD;
        takeMove(moves[move++]);
        _setPositions();
        if (finished) {
          break;
        }
      }
    }
  }

  void show() => controller.notifyListeners();

  void finish() {
    while (move < moves.length) {
      takeMove(moves[move++]);
    }
    time.stop();
    timer.cancel();
    assert(NDEBUG || controller._inFlight == this, '${controller._inFlight}');
    controller._inFlight = null;
    controller.notifyListeners();
    onFinished();
  }

  void takeMove(Move<ST> m) {
    m.move();
    if (!isUndo) {
      // if (debugComment != null) {
      //   print(debugComment);
      // }
      controller.addUndo(UndoRecord(m, debugComment: debugComment));
    }
    // controller.game.board.debugPrintGoodness();
  }

  void cancel() {
    time.stop();
    timer.cancel();
  }

  @override
  int get numCards => moves[move].numCards;

  @override
  ST get slot => moves[move].slot;

  @override
  Card get bottom => moves[move].bottom;

  @override
  double get dx => movePos.dx;

  @override
  double get dy => movePos.dy;
}
// TODO:  Right-click or long-press to show card

// Moderate games:
//  f000000000uIUvLlTnGg0xK0JAFfrEabcHWojZRyNQX0pO0iSYC0Be0P0MhdzqsDt0wmVk
//       10K iterations, 145K arrangements, 59 steps
//  f000000000MyPwFIxaZf0Wg0ANksJU0z0QdtTpjeqiB0OlYhoKHESnrXv0mu0cLRD0CbVG
//    21K iterations, 351K arrangements, 56 steps
//    was difficult before slotWeight
//  f000000000zlywOBdHre0aAEtIMQihXYjgJU00pDmVnk0SoL0fuGT000xPCscbWvqKNRZF
//    9K iterations, 74K arrangements, 65 steps
//  f000000000zXmhPgnBS0pVbovlcWrHEGe0FR0AtDLK0M0IaikTdjJYu0x0sQfOq0yUZCwN
//    13K iterations, 234K arrangements, 66 steps
//
// Hard before 7/2 putback:
//  f000000000CruRfDMsot0bmHFwjGiATZVKvlzOd0NQcgx0XeBEyU00Y0S0WJqkpnhPLaI0
//     now .3 seconds
// Hard before 7/2 tryFromField putback:
//  f000000000utMHJidl0ymExZ0AOnzkh0GPQCocvYeTaNqSLWFbUs0rgfXjDI000RBpKwV0
//     517K iterations, 7M arrangements, 51 steps 1:32
//     Now .4 seconds
//  f000000000gelDzxtWOwv0jQV0CXrFP0dyU0SEM0GbsTLmIpBicnqfZ0A0khoNHa0JKuRY
//     206K iterations, 3.9M arrangements, 70 steps, 0:49
//     Now .3 seconds
// 1.5 seconds, 1696 iterations, 147K arrangement, 58 steps:
//    f000000000wQcWqDBV0Hb0uYzJTR0jOkFatC0hmXfgiNIvpGoAey0LUdPn00xs0SrEKZlM
// Hard:
