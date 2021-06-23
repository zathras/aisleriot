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
import 'package:flutter/foundation.dart';
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

class _GamePainterCards {
  int references = 1;
  final List<List<ScalableImage>> im;

  _GamePainterCards(this.im);
}

class GamePainter {
  final _GamePainterCards _cards;
  // _cards[card.suit.value][card.value-1]
  final _BoardLayout layout;
  final _CardPainter _cardPainter;

  static final loadMessages = CircularBuffer(List.filled(5, ''));

  /// Paint times, in seconds
  final paintTimes = CircularBuffer(Float64List(100));

  GamePainter._p(_GamePainterCards cards, {required bool cacheCards})
      : _cards = cards,
        layout = _BoardLayout(cards.im.first.first.viewport),
        _cardPainter = cacheCards ? _CachingCardPainter() : _CardPainter();

  ///
  /// Create a GamePainter that is prepared.  Callee is responsible for
  /// calling [dispose] when finished with this painter.
  ///
  static Future<GamePainter> create(ui.AssetBundle b, String assetKey,
      {required bool cacheCards}) async {
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
    return GamePainter._p(_GamePainterCards(cards), cacheCards: cacheCards);
  }

  ///
  /// Return a copy of this GamePainter with the cacheCards setting changed.
  /// The new GamePainter will be prepared.  The caller is responsible for
  /// calling `dispose` on this GamePainter and, eventually, the new one.
  ///
  GamePainter withNewCacheCards(bool v) {
    final r = GamePainter._p(_cards, cacheCards: v);
    _cards.references++;
    return r;
  }

  void dispose() {
    _cardPainter.dispose();
    _cards.references--;
    assert(_cards.references >= 0);
    if (_cards.references == 0) {
      for (final row in _cards.im) {
        for (final c in row) {
          c.unprepareImages();
        }
      }
    }
  }

  static const ui.Color background = ui.Color(0xff004c0e);
  static const maxAspectRatio = 1.5;

  /// Aspect ratio of a card, taken from guyenne-classic.  It's close enough
  /// for the other decks.
  static final blankCardPaint = ui.Paint()..color = ui.Color(0x40ffffff);

  void paint(ui.Canvas c, ui.Size size, GameController controller) {
    if (size.width / size.height > maxAspectRatio) {
      final s = ui.Size(size.height * maxAspectRatio, size.height);
      c.translate((size.width - s.width) / 2, 0);
      size = s;
    }
    Stopwatch sw = Stopwatch()..start();
    Drag? dragging;
    final afterCards = List<void Function()>.empty(growable: true);
    void paintCardSpace(SlotWithCards slot, int? cardNumber, ui.Rect space, bool showHidden) {
      if (cardNumber == null) {
        showHidden = true;
      } else {
        final card = slot.cards[cardNumber];
        final ScalableImage im = _cards.im[card.suit.row][card.value - 1];
        final dragCard = controller.drag?.card;
        if (dragCard?.cardNumber == cardNumber && dragCard?.slot == slot) {
          dragging = controller.drag;
        } else {
          showHidden = false;
        }
        final d = dragging;
        if (d != null && d.card.slot == slot) {
          afterCards.add(() {
            final dx = d.current.dx - d.start.dx;
            final dy = d.current.dy - d.start.dy;
            _cardPainter.paint(c, dx, dy, space, card, im);
          });
        } else {
          dragging = null;
          _cardPainter.paint(c, 0, 0, space, card, im);
        }
      }
      if (showHidden) {
        if (cardNumber == null || cardNumber == 0) {
          final double radius = space.width / 15;
          c.drawRRect(
              ui.RRect.fromRectXY(
                  space.deflate(space.width / 50), radius, radius),
              blankCardPaint);
        } else {
          final card = slot.cards[cardNumber - 1];
          final ScalableImage im = _cards.im[card.suit.row][card.value - 1];
          _cardPainter.paint(c, 0, 0, space, card, im);
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

class _CardPainter {
  @mustCallSuper
  void dispose() {}

  void paint(ui.Canvas c, double dx, double dy, ui.Rect space, Card card,
      ScalableImage im) {
    c.save();
    c.translate(space.left + dx, space.top + dy);
    c.scale(space.width / im.viewport.width);
    im.paint(c);
    c.restore();
  }
}

class _CachingCardPainter extends _CardPainter {
  final _cards = List<_CardCacheEntry>.generate(52, (_) => _CardCacheEntry());
  double _width = -1;
  double _height = -1;
  bool _first = true;

  @override
  void paint(ui.Canvas c, double dx, double dy, ui.Rect space, Card card,
      ScalableImage im) {
    const double epsilon = 1 / 10000000;
    // One millionth - makes up for rect roundoff error, since it
    // stores corners, and not the width directly.
    if (_width <= 0 ||
        _height <= 0 ||
        (space.width - _width).abs() > _width * epsilon ||
        (space.height - _height).abs() > _height * epsilon) {
      if (_first) {
        _first = false;
      } else {
        for (int i = 0; i < _cards.length; i++) {
          _cards[i].dispose();
          _cards[i] = _CardCacheEntry();
        }
      }
      _width = space.width;
      _height = space.height;
    }
    final entry = _cards[card.index];
    final cachedImage = entry.image;
    if (cachedImage != null) {
      final p = ui.Paint();
      c.drawImage(cachedImage, ui.Offset(space.left + dx, space.top + dy), p);
      entry.picture?.dispose();
      entry.picture = null;
      return;
    }
    final picture = entry.picture ?? entry.start(space, im);
    c.translate(space.left + dx, space.top + dy);
    c.drawPicture(picture);
    c.translate(-space.left - dx, -space.top - dy);
    return;
  }

  @override
  void dispose() {
    for (final c in _cards) {
      c.dispose();
    }
    super.dispose();
  }
}

class _CardCacheEntry {
  ui.Image? image;
  ui.Picture? picture;
  bool disposed = false;

  ui.Picture start(ui.Rect space, ScalableImage im) {
    final p = picture;
    if (p != null) {
      return p;
    }
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(space.width / im.viewport.width);
    im.paint(c);
    final fp = picture = rec.endRecording();
    () async {
      final im = await fp.toImage(space.width.ceil(), space.height.ceil());
      if (disposed) {
        im.dispose(); // Too late
      } else {
        image = im;
      }
    }();
    return fp;
  }

  void dispose() {
    disposed = true;
    image?.dispose();
    picture?.dispose();
  }
}

class CardFinder {
  final _BoardLayout layout;

  CardFinder(GamePainter painter) : layout = painter.layout;

  FoundCard? find(ui.Offset pos, ui.Size size, GameController controller) {
    SlotWithCards? foundSlot;
    int? foundCardNumber;
    ui.Rect? area;
    layout.visitCards(size, controller,
        (SlotWithCards slot, int? cardNumber, ui.Rect space, _) {
      if (space.contains(pos)) {
        foundSlot = slot;
        foundCardNumber = cardNumber;
        area = space;
      }
      if (foundSlot == slot) {
        final a = area;
        if (a != null) {
          area = a.expandToInclude(space);
        } else {
          area = space;
        }
      }
    });
    // Now we have the highest card in the stack, and area includes that
    // card and all the cards below (and therefore covering) that card.
    if (foundCardNumber != null) {
      return FoundCard(foundSlot!, foundCardNumber!, area!);
    } else {
      return null;
    }
  }

  SlotWithCards? findSlot(
      ui.Rect area, ui.Size size, GameController controller) {
    double overlapArea = 0;
    SlotWithCards? foundSlot;
    void checkSlot(SlotWithCards slot, ui.Rect slotArea) {
      final overlap = area.intersect(slotArea);
      if (overlap.width > 0 && overlap.height > 0) {
        final a = overlap.width * overlap.height;
        if (a > overlapArea) {
          overlapArea = a;
          foundSlot = slot;
        }
      }
    }

    layout.visitSlots(
        size,
        controller,
        (NormalSlot n, ui.Rect space) => checkSlot(n, space),
        (ExtendedSlot e, _, ui.Rect space) => checkSlot(e, space));
    return foundSlot;
  }
}

class FoundCard {
  final SlotWithCards slot;
  final int cardNumber;

  /// Area covered by the card, and any below it in the stack
  final ui.Rect area;

  FoundCard(this.slot, this.cardNumber, this.area);

  @override
  String toString() => slot.cards[cardNumber].toString();
}

typedef _ExtendedSlotF = void Function(
    ExtendedSlot slot, double cardHeight, ui.Rect maxSpace);

typedef _NormalSlotF = void Function(NormalSlot slot, ui.Rect space);

typedef _SpaceF = void Function(
    SlotWithCards slot, int? cardNumber, ui.Rect space, bool coversSomething);

class _BoardLayout {
  final ui.Rect cardSize;

  _BoardLayout(this.cardSize);

  void visitSlots(ui.Size sz, GameController controller, _NormalSlotF normal,
      _ExtendedSlotF extended) {
    final game = controller.game;
    final double height = sz.height;
    final double width = sz.width;
    final cardWidth = width / controller.size.width;
    final cardHeight = cardWidth * cardSize.height / cardSize.width;
    final heightExtension = (height - cardHeight * controller.size.height) /
        max(1, controller.extendedSlotRowCount);
    double x = 0;
    double y = 0;

    bool extendedSeen = false;
    double rowH = 0;
    for (final s in game.slots) {
      s.visit(normal: (slot) {
        final space = ui.Rect.fromLTWH(x, y, cardWidth, cardHeight);
        normal(slot, space);
        rowH = max(rowH, cardHeight);
        x += cardWidth;
      }, extended: (slot) {
        final space =
            ui.Rect.fromLTWH(x, y, cardWidth, cardHeight + heightExtension);
        extended(slot, cardHeight, space);
        extendedSeen = true;
        rowH = max(rowH, cardHeight);
        x += cardWidth;
      }, cr: (slot) {
        x = 0;
        if (extendedSeen) {
          y += heightExtension;
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

  void visitCards(ui.Size sz, GameController controller, _SpaceF spaceF) {
    visitSlots(sz, controller, (NormalSlot slot, ui.Rect space) {
      if (slot.cards.isEmpty) {
        spaceF(slot, null, space, false);
      } else {
        spaceF(slot, slot.cards.length - 1, space, true);
      }
    }, (ExtendedSlot slot, double cardHeight, ui.Rect slotArea) {
      final extraHeight = slotArea.height - cardHeight;
      double offset = 0;
      double delta = (slot.cards.length < 2)
          ? 0
          : extraHeight / (slot.cards.length - 1);
      delta = min(delta, cardHeight / 5);
      delta = max(delta, cardHeight / 24);
      if (slot.cards.isEmpty) {
        final space = ui.Rect.fromLTWH(
            slotArea.left, slotArea.top, slotArea.width, cardHeight);
        spaceF(slot, null, space, false);
      }
      for (int i = 0; i < slot.cards.length; i++) {
        final space = ui.Rect.fromLTWH(
            slotArea.left, slotArea.top + offset, slotArea.width, cardHeight);
        spaceF(slot, i, space, i == 0);
        offset += delta;
      }
    });
  }
}
