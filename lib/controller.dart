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
class GameController extends ui.ChangeNotifier {
  final Game game;
  final List<bool> hasExtendedSlots;
  final List<double> rowHeight;
  // size in card widths/card heights, not accounting for extended slots
  final ui.Size size;
  final int extendedSlotRowCount;

  /// Set by GameState, and changed when the card sizes might change.
  late CardFinder finder;

  Drag? drag;

  GameController._p(
      this.game, this.size, List<bool> hasExtendedSlots, List<double> rowHeight)
      : hasExtendedSlots = List.unmodifiable(hasExtendedSlots),
        rowHeight = List.unmodifiable(rowHeight),
        extendedSlotRowCount =
            hasExtendedSlots.fold(0, (count, v) => v ? (count + 1) : count);

  factory GameController(Game game) {
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
    return GameController._p(
        game, ui.Size(width, height), hasExtendedSlots, rowHeight);
  }

  void doubleClickStart(ui.Size size, ui.Offset pos) {
    // final f = finder.find(pos, size, this);
  }

  void doubleClick() {}

  void clickStart(ui.Size size, ui.Offset pos) {
    // final f = finder.find(pos, size, this);
  }

  void click() {}

  void dragStart(ui.Size size, ui.Offset pos) {
    final f = finder.find(pos, size, this);
    if (f != null) {
      drag = Drag(f, pos, size);
      notifyListeners();
    }
  }

  void dragMove(ui.Size size, ui.Offset pos) {
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
      final dest = finder.findSlot(area, d.screenSize, this);
      if (dest != null && dest != d.card.slot) {
        final List<Card> from = d.card.slot.cards;
        dest.cards.addAll(from.getRange(d.card.cardNumber, from.length));
        from.length = d.card.cardNumber;
      }
    }
    drag = null;
    notifyListeners();
  }
}

class Drag {
  final ui.Offset start;
  final FoundCard card;
  final ui.Size screenSize;
  ui.Offset current;

  Drag(this.card, ui.Offset start, this.screenSize)
      : start = start,
        current = start;
}
