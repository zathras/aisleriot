/*
 Copyright (C) 2021, 2022, William Foote

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
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as ui;

import 'constants.dart';
import 'graphics.dart';
import 'game.dart';
import 'solver.dart';

class ChangeNotifier extends ui.ChangeNotifier {
  // Make it public
  void publicNotifyListeners() => notifyListeners();
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
  Solver<ST>? solver;

  /// size in card widths/card heights, not accounting for extended slots
  final ui.Size sizeInCards;
  final int extendedSlotRowCount;

  /// Set by GameState, and changed when the card sizes might change.
  late CardFinder<ST> _finder;

  /// Set and updated by GameState.
  late GamePainter _painter;

  Drag<ST>? drag;
  FoundCard<ST>? doubleClickCard;
  GameAnimation<ST>? inFlight;
  MovingStack<ST>? get movement => drag ?? inFlight;

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
    stopSolve();
    while (inFlight != null) {
      inFlight!.finish();
    }
  }

  void doubleClick() {
    game.settings.automaticPlay = false;
    _finishPending();
    final dc = doubleClickCard;
    if (dc == null) {
      return;
    }
    final List<Move<ST>> todo = game.doubleClick(dc);
    if (todo.isEmpty) {
      return;
    }
    inFlight = GameAnimation(this, todo, () => doAutomaticMoves());
  }

  void clickStart(ui.Offset pos) {
    // pos = addPaintOffset(pos);
    // final f = finder.find(pos, size, this);
  }

  void click() {}

  void dragStart(ui.Offset pos) {
    game.settings.automaticPlay = false;
    _finishPending();
    pos = addPaintOffset(pos);
    final f = _finder.find(pos, this);
    if (f != null && game.board.canSelect(f)) {
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
        takeMove(move, false);
        doAutomaticMoves();
      }
    }
    drag = null;
    notifyListeners();
  }

  void doAutomaticMoves([void Function() onDone = _nop]) {
    assert(inFlight == null);
    final newMoves = game.board.automaticMoves();
    if (newMoves.isEmpty) {
      onDone();
    } else {
      inFlight = GameAnimation(this, newMoves, () => doAutomaticMoves(onDone));
      notifyListeners();
    }
  }

  static void _nop() {}

  ui.Offset addPaintOffset(ui.Offset pos) => (_painter.lastPaintOffset == 0.0)
      ? pos
      : ui.Offset(pos.dx - _painter.lastPaintOffset, pos.dy);

  void _changeGame(void Function() f) {
    bool oldUndo = game.canUndo;
    bool oldRedo = game.canRedo;
    bool oldGameWon = game.gameWon;
    bool oldLost = game.lost;
    f();
    if ((game.canRedo != oldRedo) ||
        (game.canUndo != oldUndo) ||
        (game.gameWon != oldGameWon) ||
        (oldLost != game.lost)) {
      gameChangeNotifier.notifyListeners();
    }
    // game.board.debugPrintGoodness();
  }

  void takeMove(Move<ST> m, bool isUndo) {
    _changeGame(() {
      m.move();
      if (!isUndo) {
        game.addUndo(UndoRecord(m));
      }
    });
  }

  void newGame() {
    game.settings.automaticPlay = false;
    _finishPending();
    _game = game.newGame();
    notifyListeners();
    gameChangeNotifier.notifyListeners();
  }

  void undo() {
    game.settings.automaticPlay = false;
    stopSolve();
    _finishPending();
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
      inFlight = GameAnimation<ST>(this, [move], () {
        if (u.automatic) {
          undo();
        }
      }, isUndo: true);
      notifyListeners();
    }
  }

  void redo({bool onlyAutomatic = false}) {
    game.settings.automaticPlay = false;
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
      if (u.automatic && !onlyAutomatic) {
        u.automatic = false;
        // We manually asked for the redo, so it's not automatic anymore.
      }
      u.printComment();
      final Card bottom = u.src.cardDownFromTop(u.numCards - 1);
      final cs = CardStack(u.src, u.numCards, bottom);
      final move = Move(src: cs, dest: u.dest, automatic: u.automatic);
      inFlight = GameAnimation<ST>(this, [move], () {
        redo(onlyAutomatic: true);
      }, isUndo: true);
      notifyListeners();
    }
  }

  void solve({void Function()? onNewGame}) {
    _finishPending();
    assert(solver == null);
    if (game.settings.automaticPlay) {
      unawaited(() async {
        for (;;) {
          final s = solver = SolutionSearcher(this);
          final ok = await s.solve();
          if (!ok) {
            _changeGame(() {
              game.lost = true;
            });
          }
          if (!game.settings.automaticPlay) {
            break;
          } else {
            gameChangeNotifier.notifyListeners();
            _game = game.newGame();
            final f = onNewGame;
            if (f != null) {
              f();
            }
            notifyListeners();
            gameChangeNotifier.notifyListeners();
          }
        }
      }());
    } else {
      final s = solver = SolutionSearcher(this);
      unawaited(s.solve());
    }
  }

  void stopSolve() {
    solver?.stop();
    solver = null;
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

  Drag(this.card, this.start) : current = start;

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

class GameAnimation<ST extends Slot> implements MovingStack<ST> {
  final GameController<ST> controller;
  final List<Move<ST>> moves;
  final void Function() onFinished;
  final bool isUndo;
  int move = 0;
  final Stopwatch time = Stopwatch();
  int lastTicks = 0;
  late final Timer timer;
  ui.Offset movePos = ui.Offset.zero;
  ui.Offset moveDest = ui.Offset.zero;

  static const double speed = 150; // card widths/second

  GameAnimation(this.controller, this.moves, this.onFinished,
      {this.isUndo = false}) {
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

  void show() => controller.publicNotifyListeners();

  void finish() {
    while (move < moves.length) {
      takeMove(moves[move++]);
    }
    time.stop();
    timer.cancel();
    assert(
        disableDebug || controller.inFlight == this, '${controller.inFlight}');
    controller.inFlight = null;
    controller.publicNotifyListeners();
    onFinished();
  }

  void takeMove(Move<ST> m) => controller.takeMove(m, isUndo);

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
// 3 seconds, 3321 iterations, 330K arrangements, 55 steps:
//    f000000000cPyupVkRt0q0i00SNoH0TXmwWnhsrgDZjEQfYCLv0OB0JGUxMeFa0KbAzIld
// 3.8 seconds, 4184 iterations, 463K arrangements, 59 steps:
//    f000000000ygrxZFhP0LRXtBCJndibHje0AIaYTQ0ukDGMKVlvp0zcN00fwWUsEomOq00S
// 4.7 seconds, 4814 iterations, 546K arrangements, 51 steps:
//    f000000000rfVqgSIT0UsuMFDJ0Gl0t0diKv0n0X0mARNHkQpPceBaOowZxLEhbWCYyjz0
// 10.8 seconds, 15911 iterations, 1.2M arrangements, 54 steps:
//    f000000000pSIMWFDx0jbTrPZGKe00VHscglJLoqAm0w0UifOvdyYa0ChR0nBQXE0zNutk
// 30 seconds:
//    f000000000fIjczdiNwLql0JGUaPHgB0OXSCFeTQE0DbWrxZkot0spMR0mKyVuv0Yn0h0A
// 184 seconds:
//    f000000000SpNiugdq0mYRFrCXtAI0000cUe0KWZBhnLsDTVb0jPG0HOowlMazkEvyxJfQ
// 476 seconds:
//    f000000000JXHWNjbT0DvnYu0tcfO00ARZh0iUylzdCmg0rG0EpMPewkxsaFVIKS0LQoqB
// 797 seconds, 187K iterations, 12M arrangements:
//    f000000000TYcCuBzEmpFNLs0JGWnZOPXe0K0lIVDSry0whoUadqQMH0k0f0x0gvitbRjA
// 1028 seconds:
//    f000000000DSJmTPbWgMoYRijHI0eZfdhutCOGLVBEQ0XyakcwK0nxz0Aspq0UNrv0Fl00
// 2595 seconds, 582K iterations, 32M arrangements:
//    f000000000DmvkgofTrR0Xhqn0YAjJwpdyH0VCFQl0uKPxEZc0UM0i0tze0WLOsSNaBbIG
// Unsolved before tryToField, trivial after:
//    f000000000JQleDUKsBXSrkvGt0oWZq0ngR0adCjHh0y0VPxm0zcwYTbALiFEM0ufON0pI
// Hard before tryFromFreecells():
//  1037 seconds, 5.2M iterations, 26M arrangements:
//    f000000000LeBNqndsOx0mhlcD0wgAFu0yXJWCHrG0okYIif0KEpSPbMUR00zQvaZtjV0T
//  401 seconds, 176K iterations, 15M arrangements:
//    f000000000dBZwCQTHUEuSDqFnOAGYXa0stRJglevMop0chVi0Lf00Ijb00zkmrPWK0Nyx
//  Unsolved (at 9338 wins) before tryFromFreecells(), trivial after:
//    f000000000iIxGwyQfsaH0dWKJO0lbCXTnBA000PomqUFDhR0eMtLg0zpSk0rujcNZVYEv
//
// Unsolvable:
//    f000000000GtJmguzbRqvDZcW0VyCAx00Tw0KOfQBsLdYISiH0XMnjkeF0l0Ph0aroEpUN

// Nearly solved:
//    f00000PoB0000bcD0C0pqrFGuIJxLM00ndRSTUiWXlm00AQefghVjkYZ00NOEstHvwKyza

// Hard in an interesting way:
//    f0Dw0HaA00ctIpOvr00oqFL0UnhKgMNZ0QRfTXVW0lm00bd0SGB0jkY000CeEsPuiJxyz0
//    f0Dw0HaA00crIpOv000oqFLtUnhKgMNZ0QRfTXVW0lm00bd0SGB0jkY000CeEsPuiJxyz0
