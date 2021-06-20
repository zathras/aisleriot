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

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' as ui;
import 'package:flutter/services.dart' as ui;
import 'package:jovial_svg/jovial_svg.dart';

import 'controller.dart';
import 'm/game.dart';

//TODO:  Move CircularBuffer to jovial_misc

///
/// A circular buffer, based on an underlying fixed-length list.
///
class CircularBuffer<T> extends ListMixin<T> {
  final List<T> _store;
  int _first = 0;
  int _last = -1;

  ///
  /// A circular buffer that uses the fixed-size list [store] to store
  /// the elements.  The initial elements of store are ignored.
  ///
  /// Example usages:
  /// ```
  /// final buf = CircularBuffer(Float64List(10));
  /// CircularBuffer<String> buf2 = CircularBuffer(List.filled(10, ''));
  /// ```
  CircularBuffer(List<T> store) : _store = store;

  ///
  /// Create a circular buffer with `capacity` slots, where `empty` is a
  /// default value that can fill unused slots in an underlying container.
  ///
  /// Example usage, nullable type:
  /// ```
  /// final buf = CircularBuffer<MyThing?>.create(10, null)
  /// ```
  ///
  /// Example usage, non-nullable type:
  /// ```
  /// final buf = CircularBuffer.create(10, '')
  /// ```
  ///
  CircularBuffer.create(int capacity, T empty)
      : _store = List.filled(capacity, empty);

  @override
  int get length => (_last == -1) ? 0 : ((_last - _first) % _store.length + 1);

  @override
  set length(int v) {
    if (v < 0 || v > length) {
      throw ArgumentError();
    } else if (v == 0) {
      reset();
    } else {
      _first = (_last + 1 - v);
    }
  }

  @override
  void add(T element) {
    if (_last == -1) {
      _store[_last = 0] = element;
    } else {
      _last = (_last + 1) % _store.length;
      _store[_last] = element;
      if (_last == _first) {
        _first = (_first + 1) % _store.length;
        assert(length == _store.length);
      }
    }
  }

  ///
  /// Reset the circular buffer to the empty state, without clearing the
  /// old elements from the underlying storage.  See [resetAndClear].
  ///
  void reset() {
    _first = 0;
    _last = -1;
  }

  ///
  /// Reset the circular buffer to the empty state, and clear out the
  /// old elements from the underlying storage by filling it with
  /// [empty].  Usually this isn't necessary, because those elements are
  /// inaccessible, but not clearing them makes the inelilgible for GC, until
  /// those positions are overwritten.
  ///
  void resetAndClear(T empty) {
    for (int i = 0; i < length; i++) {
      this[i] = empty;
    }
    reset();
  }

  @override
  T operator [](int index) {
    if (index >= length || index < 0) {
      throw ArgumentError('Illegal index');
    }
    index = (index + _first) % _store.length;
    return _store[index];
  }

  @override
  void operator []=(int index, T value) {
    if (index >= length || index < 0) {
      throw ArgumentError('Illegal index');
    }
    index = (index + _first) % _store.length;
    _store[index] = value;
  }
}

class GamePainter {
  final List<List<ScalableImage>> _cards;
  // _cards[card.suit.value][card.value-1]
  final _BoardLayout layout;

  static final loadMessages = CircularBuffer(List.filled(5, ''));

  /// Paint times, in seconds
  final paintTimes = CircularBuffer(Float64List(100));

  GamePainter._p(List<List<ScalableImage>> cards)
      : _cards = cards,
        layout = _BoardLayout(cards.first.first.viewport);

  ///
  /// Create a GamePainter that is prepared.  Callee is responsible for
  /// calling [dispose] when finished with this painter.
  ///
  static Future<GamePainter> create(ui.AssetBundle b, String assetKey) async {
    final data = await b.load(assetKey);
    final dataL =
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final sw = Stopwatch();
    sw.start();
    final allCards = ScalableImage.fromSIBytes(dataL);
    sw.stop();
    loadMessages.add('Decoded $assetKey in ${sw.elapsedMilliseconds} ms');
    final ch = allCards.viewport.height / 5;
    final cw = allCards.viewport.width / 13;
    final cards = List<List<ScalableImage>>.generate(
        4,
        (s) => List<ScalableImage>.generate(
            13,
            (v) => allCards.withNewViewport(
                ui.Rect.fromLTWH(v * cw, s * ch, cw, ch),
                prune: true,
                pruningTolerance: cw / 200),
            growable: false),
        growable: false);
    for (final row in cards) {
      for (final c in row) {
        await c.prepareImages();
      }
    }
    return GamePainter._p(cards);
  }

  void dispose() {
    for (final row in _cards) {
      for (final c in row) {
        c.unprepareImages();
      }
    }
  }

  static const ui.Color background = ui.Color(0xff004c0e);

  /// Aspect ratio of a card, taken from guyenne-classic.  It's close enough
  /// for the other decks.
  static const cardAspectRatio = 123 / 79;
  static final blankCardPaint = ui.Paint()..color = ui.Color(0x40ffffff);

  void paint(ui.Canvas c, ui.Size size, GameController controller) {
    Stopwatch sw = Stopwatch()..start();
    Drag? dragging;
    final afterCards = List<void Function()>.empty(growable: true);
    void paintCardSpace(SlotWithCards slot, int? cardNumber, ui.Rect space) {
      if (cardNumber == null || cardNumber == 0) {
        final double radius = space.width / 15;
        c.drawRRect(
            ui.RRect.fromRectXY(
                space.deflate(space.width / 50), radius, radius),
            blankCardPaint);
      }
      if (cardNumber != null) {
        final card = slot.cards[cardNumber];
        final ScalableImage im = _cards[card.suit.row][card.value - 1];
        final dragCard = controller.drag?.card;
        if (dragCard?.cardNumber == cardNumber && dragCard?.slot == slot) {
          dragging = controller.drag;
        }
        final d = dragging;
        if (d != null && d.card.slot == slot) {
          afterCards.add(() {
            c.save();
            c.translate(space.left + d.current.dx - d.start.dx,
                space.top + d.current.dy - d.start.dy);
            c.scale(space.width / im.viewport.width);
            im.paint(c);
            c.restore();
          });
        } else {
          dragging = null;
          c.save();
          c.translate(space.left, space.top);
          c.scale(space.width / im.viewport.width);
          im.paint(c);
          c.restore();
        }
      }
    }

    c.drawColor(background, ui.BlendMode.src);
    layout.visitCards(size, controller, paintCardSpace);
    for (final f in afterCards) {
      f();
    }
    sw.stop();
    paintTimes.add(sw.elapsedTicks / sw.frequency);
  }
}

class CardFinder {
  final _BoardLayout layout;

  CardFinder(GamePainter painter) : layout = painter.layout;

  FoundCard? find(ui.Offset pos, ui.Size size, GameController controller) {
    SlotWithCards? foundSlot;
    int? foundCardNumber;
    layout.visitCards(size, controller,
        (SlotWithCards slot, int? cardNumber, ui.Rect space) {
      if (space.contains(pos)) {
        foundSlot = slot;
        foundCardNumber = cardNumber;
      }
    });
    // Now we have the topmost card
    if (foundCardNumber != null) {
      return FoundCard(foundSlot!, foundCardNumber!);
    } else {
      return null;
    }
  }
}

class FoundCard {
  final SlotWithCards slot;
  final int cardNumber;

  FoundCard(this.slot, this.cardNumber);

  @override
  String toString() => slot.cards[cardNumber].toString();
}

typedef _SpaceF = void Function(
    SlotWithCards slot, int? cardNumber, ui.Rect space);

class _BoardLayout {
  final ui.Rect cardSize;

  _BoardLayout(this.cardSize);

  void visitCards(ui.Size sz, GameController controller, _SpaceF spaceF) {
    final game = controller.game;
    final double height = sz.height;
    final double width = sz.width;
    final cardWidth = width / controller.size.width;
    final cardHeight = cardWidth * cardSize.height / cardSize.width;
    final extendedAreaHeight = (height - cardHeight * controller.size.height) /
        max(1, controller.extendedSlotRowCount);
    double x = 0;
    double y = 0;

    bool extendedSeen = false;
    double rowH = 0;
    for (final s in game.slots) {
      s.visit(normal: (slot) {
        final space = ui.Rect.fromLTWH(x, y, cardWidth, cardHeight);
        if (slot.cards.isEmpty) {
          spaceF(slot, null, space);
        } else {
          spaceF(slot, slot.cards.length - 1, space);
        }
        rowH = max(rowH, cardHeight);
        x += cardWidth;
      }, extended: (slot) {
        double offset = 0;
        double delta = (slot.cards.length < 2)
            ? 0
            : extendedAreaHeight / (slot.cards.length - 1);
        delta = min(delta, cardHeight / 5);
        delta = max(delta, cardHeight / 20);
        if (slot.cards.isEmpty) {
          final space = ui.Rect.fromLTWH(x, y, cardWidth, cardHeight);
          spaceF(slot, null, space);
        }
        for (int i = 0; i < slot.cards.length; i++) {
          final space = ui.Rect.fromLTWH(x, y + offset, cardWidth, cardHeight);
          spaceF(slot, i, space);
          offset += delta;
        }
        extendedSeen = true;
        rowH = max(rowH, cardHeight);
        x += cardWidth;
      }, cr: (slot) {
        x = 0;
        if (extendedSeen) {
          y += extendedAreaHeight;
        }
        y += slot.extraHeight * cardHeight;
        y += rowH;
        extendedSeen = false;
        rowH = 0;
      }, horizontalSpace: (slot) {
        x += slot.width * cardWidth;
      });
    }
  }
}
