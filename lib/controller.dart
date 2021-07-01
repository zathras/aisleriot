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

import 'graphics.dart';
import 'm/game.dart';

///
/// Controller and view manager for Solitaire.  The GameController manages
/// the positions of the graphical assets.  The view should register as a
/// listener via the `ChangeNotifier` API.
///
class GameController<ST extends Slot> extends ui.ChangeNotifier {
  final Game<ST> game;
  final List<bool> hasExtendedSlots;
  final List<double> rowHeight;

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

  GameController._p(this.game, this.sizeInCards, List<bool> hasExtendedSlots,
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
        d.card.slot.moveStackTo(d.numCards, dest);
        doAutomaticMoves();
      }
    }
    drag = null;
    notifyListeners();
  }

  @override
  void notifyListeners() => super.notifyListeners();
  // Make it public

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
    print("@@ Solving ${scratch.toExternal()}");
    final q = PriorityQueue<SearchSlotData>(
        (a, b) => b.goodness.compareTo(a.goodness));
    final seen = HashSet<List<int>>(
        equals: quiver.listsEqual, hashCode: quiver.hashObjects);
    scratch.doAllAutomaticMoves();
    scratch.canonicalize();
    seen.add(scratch.slotData.raw);
    scratch.calculateChildren(scratch, (k) {
      seen.add(k.raw);
      q.add(k);
    });
    final sw = Stopwatch()..start();
    double nextFrame = 0.25 * sw.frequency;
    unawaited(() async {
      int iterations = 0;
      while (q.isNotEmpty) {
        final k = q.removeFirst();
        if (sw.elapsedTicks > nextFrame) {
          nextFrame += 0.25 * sw.frequency;
          notifyListeners();
          print("@@ $iterations iterations");
          await Future<void>.delayed(Duration(milliseconds: 5));
        }
        scratch.slotData = k;
        if (scratch.gameWon) {
          print(
              "@@@@ ==> Found after $iterations iterations, duration ${sw.elapsed}.");
          sw.stop();
          notifyListeners();
          await Future<void>.delayed(Duration(seconds: 1));
          scratch.slotData = initial;
          SearchSlotData? next = k;
          final path = List.generate(k.depth + 1, (_) {
            final sd = next!;
            next = sd.from;
            return sd;
          });
          final solution = Solution(path, scratch);
          assert(next == null);
          print("@@ Done - created ${seen.length} arrangements.");
          painter.currentSearch = null;
          solution.run(this);
          return;
        }
        iterations++;
        scratch.calculateChildren(scratch, (kk) {
          if (seen.add(kk.raw)) {
            q.add(kk);
          }
        });
      }
    }());
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
    print("@@ Solution has ${path.length} steps");
    assert(path.isEmpty || path[path.length-1].from == null);
    controller.doAutomaticMoves(() => _moveCompleted(controller));
  }

  /// Now, both scrath and game are at one of the "s" states along the top.
  void _moveCompleted(GameController<ST> controller) {
    int nextEmptySlot = 0;
    final board = controller.game.board;
    assert(quiver.listsEqual(
        (board.makeSearchBoard()..canonicalize()).slotData.raw,
        scratch.slotData.raw));
    assert(() {
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
    assert(!slotMap.any((v) => v < 0));
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
      final move = Move(src: src, dest: dest);
      assert(controller._inFlight == null);
      assert(board.canSelect(src));
      assert(board.canDrop(
          FoundCard(srcSlot, step.viaNumCards, bottom, ui.Rect.zero), dest));
      controller._inFlight = _GameAnimation<ST>(
          controller, [move], () => controller.doAutomaticMoves(() => _moveCompleted(controller)));
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
  int move = 0;
  final Stopwatch time = Stopwatch();
  int lastTicks = 0;
  late final Timer timer;
  ui.Offset movePos = ui.Offset.zero;
  ui.Offset moveDest = ui.Offset.zero;

  static const double speed = 5; // @@ TODO 75; // card widths/second

  _GameAnimation(this.controller, this.moves, this.onFinished) {
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
      moves[move++].move();
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
        moves[move++].move();
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
      moves[move++].move();
    }
    time.stop();
    timer.cancel();
    assert(controller._inFlight == this);
    controller._inFlight = null;
    controller.notifyListeners();
    onFinished();
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
//   f000000000uIUvLlTnGg0xK0JAFfrEabcHWojZRyNQX0pO0iSYC0Be0P0MhdzqsDt0wmVk
//       14K iterations, 186K arrangements, 57 steps
// Difficult games:
//  f000000000MyPwFIxaZf0Wg0ANksJU0z0QdtTpjeqiB0OlYhoKHESnrXv0mu0cLRD0CbVG
//  f0eAEzZv1vwPZfSp1LSFnvv-R_LWZhXX5OFgEO6f8a3EbsfCqKcjq8goai_3lE_jOpasv-l2HUV2D4jwrZ1dgl2DXZxdjk2ZTYxNkYQAAA_wcVUw==
//    847K iterations, 15M arrangements
