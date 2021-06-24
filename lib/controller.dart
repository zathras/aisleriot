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
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as ui;

import 'graphics.dart';
import 'm/game.dart';

///
/// Controller and view manager for Solitaire.  The GameController manages
/// the positions of the graphical assets.  The view should register as a
/// listener via the `ChangeNotifier` API.
///
class GameController<CS extends SlotWithCards> extends ui.ChangeNotifier {
  final Game<CS> game;
  final List<bool> hasExtendedSlots;
  final List<double> rowHeight;

  /// size in card widths/card heights, not accounting for extended slots
  final ui.Size sizeInCards;
  final int extendedSlotRowCount;

  /// Set by GameState, and changed when the card sizes might change.
  late CardFinder<CS> _finder;

  /// Set and updated by GameState.
  late GamePainter _painter;

  Drag<CS>? drag;
  FoundCard<CS>? doubleClickCard;
  _GameAnimation<CS>? _inFlight;
  MovingStack<CS>? get movement => drag ?? _inFlight;

  GameController._p(this.game, this.sizeInCards, List<bool> hasExtendedSlots,
      List<double> rowHeight)
      : hasExtendedSlots = List.unmodifiable(hasExtendedSlots),
        rowHeight = List.unmodifiable(rowHeight),
        extendedSlotRowCount =
            hasExtendedSlots.fold(0, (count, v) => v ? (count + 1) : count);

  factory GameController(Game<CS> game) {
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
    return GameController<CS>._p(
        game, ui.Size(width, height), hasExtendedSlots, rowHeight);
  }

  GamePainter get painter => _painter;
  set painter(GamePainter v) {
    _painter = v;
    _finder = CardFinder<CS>(_painter);
  }

  ui.Size get screenSize => painter.lastPaintSize;
  double get cardWidth => screenSize.width / sizeInCards.width;

  void doubleClickStart(ui.Offset pos) {
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
    final List<Move<CS>> todo = game.doubleClick(dc);
    if (todo.isEmpty) {
      return;
    }
    _inFlight = _GameAnimation(this, todo);
  }

  void clickStart(ui.Offset pos) {
    // final f = finder.find(pos, size, this);
  }

  void click() {}

  void dragStart(ui.Offset pos) {
    final f = _finder.find(pos, this);
    if (f != null && game.canSelect(f)) {
      _finishPending();
      drag = Drag(f, pos);
      notifyListeners();
    }
  }

  void dragMove(ui.Offset pos) {
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
      final CS? dest = _finder.findSlot(area, this);
      if (dest != null && dest != d.card.slot && game.canDrop(d.card, dest)) {
        final List<Card> from = d.card.slot.cards;
        dest.cards.addAll(from.getRange(d.card.cardNumber, from.length));
        from.length = d.card.cardNumber;
        doAutomaticMoves();
      }
    }
    drag = null;
    notifyListeners();
  }

  @override
  void notifyListeners() => super.notifyListeners();
  // Make it public

  void doAutomaticMoves() {
    assert(_inFlight == null);
    final newMoves = game.automaticMoves();
    if (newMoves.isNotEmpty) {
      _inFlight = _GameAnimation(this, newMoves);
    }
  }
}

abstract class MovingStack<CS extends SlotWithCards> {
  int get cardNumber;
  CS get slot;
  double get dx;
  double get dy;
}

class Drag<CS extends SlotWithCards> extends MovingStack<CS> {
  final FoundCard<CS> card;
  final ui.Offset start;
  ui.Offset current;

  Drag(this.card, ui.Offset start)
      : start = start,
        current = start;

  @override
  int get cardNumber => card.cardNumber;

  @override
  CS get slot => card.slot;

  @override
  double get dx => current.dx - start.dx;

  @override
  double get dy => current.dy - start.dy;
}

class _GameAnimation<CS extends SlotWithCards> implements MovingStack<CS> {
  final GameController<CS> controller;
  final List<Move<CS>> moves;
  int move = 0;
  final Stopwatch time = Stopwatch();
  int lastTicks = 0;
  late final Timer timer;
  ui.Offset movePos = ui.Offset.zero;
  ui.Offset moveDest = ui.Offset.zero;

  static const double speed = 75; // card widths/second

  _GameAnimation(this.controller, this.moves) {
    timer = Timer.periodic(Duration(microseconds: (1000000 / 300).ceil()), _timerTick);
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
      var startPos = controller._finder.cardPos(m.topMovingCard, controller);
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
    controller.doAutomaticMoves();
  }

  @override
  int get cardNumber => moves[move].src.cards.length - moves[move].numCards;

  @override
  CS get slot => moves[move].src;

  @override
  // TODO: implement dx
  double get dx => movePos.dx;

  @override
  // TODO: implement dy
  double get dy => movePos.dy;
}
