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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as ui;
import 'package:jovial_svg/jovial_svg.dart';
import 'package:jovial_misc/circular_buffer.dart';

import 'controller.dart';
import 'game.dart';

class _GamePainterCards {
  int references = 1;
  final List<List<ScalableImage>> im;

  _GamePainterCards(this.im);
}

class GamePainter {
  final double devicePixelRatio;
  final _GamePainterCards _cards;
  // _cards[card.suit.value][card.value-1]
  final BoardLayout layout;
  final _CardPainter _cardPainter;
  ui.Size lastPaintSize = ui.Size.zero;
  double lastPaintOffset = 0;

  static final loadMessages = CircularBuffer(List.filled(5, ''));

  /// Paint times, in seconds
  static final paintTimes = CircularBuffer(Float64List(100));

  Board? currentSearch;

  GamePainter._p(_GamePainterCards cards, this.devicePixelRatio,
      {required bool cacheCards})
      : _cards = cards,
        layout = BoardLayout(cards.im.first.first.viewport),
        _cardPainter =
            cacheCards ? _CachingCardPainter(devicePixelRatio) : _CardPainter();

  ///
  /// Create a GamePainter that is prepared.  Callee is responsible for
  /// calling [dispose] when finished with this painter.
  ///
  static Future<GamePainter> create(
      ui.AssetBundle b, String assetKey, double devicePixelRatio,
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
    return GamePainter._p(_GamePainterCards(cards), devicePixelRatio,
        cacheCards: cacheCards);
  }

  ///
  /// Return a copy of this GamePainter with the cacheCards setting changed.
  /// The new GamePainter will be prepared.  The caller is responsible for
  /// calling `dispose` on this GamePainter and, eventually, the new one.
  ///
  GamePainter withNewCacheCards(bool v) {
    final r = GamePainter._p(_cards, devicePixelRatio, cacheCards: v);
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
  static const searchBackground = ui.Color(0xff000070);
  static const unsolvableBackground = ui.Color(0xff600912);
  static const maxAspectRatio = 1.5;

  static final blankCardPaint = ui.Paint()..color = const ui.Color(0x40ffffff);

  void paint(ui.Canvas c, ui.Size size, GameController controller) {
    if (size.width / size.height > maxAspectRatio) {
      final s = ui.Size(size.height * maxAspectRatio, size.height);
      lastPaintOffset = (size.width - s.width) / 2;
      c.translate(lastPaintOffset, 0);
      size = s;
    } else {
      lastPaintOffset = 0;
    }
    lastPaintSize = size;
    Stopwatch sw = Stopwatch()..start();
    MovingStack? moving;
    final afterCards = List<void Function()>.empty(growable: true);
    void paintCardSpace(
        Slot slot, Card? card, ui.Rect space, bool showHidden, Card? hidden) {
      if (card != null) {
        final ScalableImage im = _cards.im[card.suit.row][card.value - 1];
        final move = controller.movement;
        if (move?.bottom == card) {
          moving = move;
        } else {
          showHidden = false; // Because we completely cover space
        }
        final d = moving;
        if (d != null && d.slot == slot) {
          afterCards.add(() {
            _cardPainter.paint(c, d.dx, d.dy, space, card, im);
          });
        } else {
          moving = null;
          _cardPainter.paint(c, 0, 0, space, card, im);
        }
      }
      if (showHidden) {
        if (hidden != null) {
          final ScalableImage im = _cards.im[hidden.suit.row][hidden.value - 1];
          _cardPainter.paint(c, 0, 0, space, hidden, im);
        } else {
          final double radius = space.width / 15;
          c.drawRRect(
              ui.RRect.fromRectXY(
                  space.deflate(space.width / 50), radius, radius),
              blankCardPaint);
        }
      }
    }

    if (currentSearch != null) {
      c.drawColor(searchBackground, ui.BlendMode.src);
    } else {
      c.drawColor(background, ui.BlendMode.src);
    }
    layout.visitCards(controller, paintCardSpace, currentSearch);
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
  final double devicePixelRatio;
  final _cards = List<_CardCacheEntry>.generate(52, (_) => _CardCacheEntry());
  double _width = -1;
  double _height = -1;
  bool _first = true;

  _CachingCardPainter(this.devicePixelRatio);

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
      c.save();
      c.scale(1 / devicePixelRatio);
      c.drawImage(
          cachedImage,
          ui.Offset(devicePixelRatio * (space.left + dx),
              devicePixelRatio * (space.top + dy)),
          p);
      c.restore();
      entry.picture?.dispose();
      entry.picture = null;
      return;
    }
    final picture = entry.picture ?? entry.start(space, im, devicePixelRatio);
    c.save();
    c.translate(space.left + dx, space.top + dy);
    c.scale(1 / devicePixelRatio);
    c.drawPicture(picture);
    c.restore();
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

  ui.Picture start(ui.Rect space, ScalableImage im, double devicePixelRatio) {
    final p = picture;
    if (p != null) {
      return p;
    }
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(devicePixelRatio * space.width / im.viewport.width);
    im.paint(c);
    final fp = picture = rec.endRecording();
    () async {
      final im = await fp.toImage((space.width * devicePixelRatio).ceil(),
          (space.height * devicePixelRatio).ceil());
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

class FoundCard<ST extends Slot> implements CardStack<ST> {
  /// Area of card cardNumber
  final ui.Rect area;
  @override
  final Card bottom;
  @override
  final ST slot;
  @override
  final int numCards;

  FoundCard(this.slot, this.numCards, this.bottom, this.area);
}

class CardFinder<ST extends Slot> {
  final BoardLayout layout;

  CardFinder(GamePainter painter) : layout = painter.layout;

  FoundCard<ST>? find(ui.Offset pos, GameController<ST> c) {
    ST? foundSlot;
    int numCards = 0;
    Card? bottom;
    ui.Rect? area;
    layout.visitCards(c, (Slot slot, Card? card, ui.Rect space, _, __) {
      if (space.contains(pos)) {
        foundSlot = slot as ST; // Game has an assert that makes this safe
        bottom = card;
        numCards = 1;
        area = space;
      } else if (slot == foundSlot) {
        numCards++;
      }
    });
    // Now we have the highest card in the stack, and area includes that
    // card and all the cards below (and therefore covering) that card.
    if (bottom != null) {
      return FoundCard<ST>(foundSlot!, numCards, bottom!, area!);
    } else {
      return null;
    }
  }

  ST? findSlot(ui.Rect area, GameController<ST> controller) {
    double overlapArea = 0;
    ST? foundSlot;
    void checkSlot(Slot slot, ui.Rect slotArea) {
      final overlap = area.intersect(slotArea);
      if (overlap.width > 0 && overlap.height > 0) {
        final a = overlap.width * overlap.height;
        if (a > overlapArea) {
          overlapArea = a;
          foundSlot = slot as ST; // Game has an assert that makes this safe
        }
      }
    }

    layout.visitSlots(
        controller,
        (NormalSlot n, ui.Rect space) => checkSlot(n, space),
        (ExtendedSlot e, _, ui.Rect space) => checkSlot(e, space));
    return foundSlot;
  }

  ui.Offset cardPos(Card card, GameController controller) {
    ui.Offset result = ui.Offset.zero;
    layout.visitCards(controller, (slot, vcard, space, _, __) {
      if (vcard == card) {
        result = ui.Offset(space.left, space.top);
      }
    });
    return result;
  }

  ui.Offset nextCardPos(Slot slot, GameController controller) {
    ui.Offset result = ui.Offset.zero;
    final numCards = slot.numCards;
    layout.visitSlots(controller, (NormalSlot s, space) {
      if (s == slot) {
        result = ui.Offset(space.left, space.top);
      }
    }, (ExtendedSlot s, double cardHeight, ui.Rect slotArea) {
      if (s == slot) {
        final delta = layout.extendedDelta(slotArea, cardHeight, numCards + 1);
        var x = slotArea.left;
        var y = slotArea.top + numCards * delta;
        y = min(y, slotArea.bottom - cardHeight);
        result = ui.Offset(x, y);
      }
    });
    return result;
  }
}

typedef ExtendedSlotF = void Function(
    ExtendedSlot slot, double cardHeight, ui.Rect maxSpace);

typedef NormalSlotF = void Function(NormalSlot slot, ui.Rect space);

typedef SpaceF = void Function(
    Slot slot, Card? card, ui.Rect space, bool showHidden, Card? hidden);

class BoardLayout {
  final ui.Rect cardViewport;

  BoardLayout(this.cardViewport);

  void visitSlots(
      GameController controller, NormalSlotF normal, ExtendedSlotF extended) {
    final game = controller.game;
    final double height = controller.screenSize.height;
    final cardWidth = controller.cardWidth;
    final cardHeight = cardWidth * cardViewport.height / cardViewport.width;
    final heightExtension =
        (height - cardHeight * controller.sizeInCards.height) /
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

  void visitCards(GameController controller, SpaceF spaceF, [Board? search]) {
    visitSlots(controller, (NormalSlot slot, ui.Rect space) {
      if (search != null) {
        slot = search.slotFromNumber(slot.slotNumber) as NormalSlot;
      }
      if (slot.isEmpty) {
        spaceF(slot, null, space, true, null);
      } else {
        spaceF(slot, slot.top, space, true, slot.belowTop);
      }
    }, (ExtendedSlot slot, double cardHeight, ui.Rect slotArea) {
      if (search != null) {
        slot = search.slotFromNumber(slot.slotNumber) as ExtendedSlot;
      }
      if (slot.isEmpty) {
        final space = ui.Rect.fromLTWH(
            slotArea.left, slotArea.top, slotArea.width, cardHeight);
        spaceF(slot, null, space, true, null);
      } else {
        double offset = 0;
        double delta = extendedDelta(slotArea, cardHeight, slot.numCards);
        Card? lastCard;
        int i = 0;
        for (final card in slot.fromBottom) {
          final space = ui.Rect.fromLTWH(
              slotArea.left, slotArea.top + offset, slotArea.width, cardHeight);
          spaceF(slot, card, space, i == 0, lastCard);
          lastCard = card;
          offset += delta;
          i++;
        }
      }
    });
  }

  double extendedDelta(ui.Rect slotArea, double cardHeight, int numCards) {
    final extraHeight = slotArea.height - cardHeight;
    double delta = (numCards < 0) ? 0 : extraHeight / (numCards - 1);
    delta = min(delta, cardHeight / 5);
    delta = max(delta, cardHeight / 24);
    return delta;
  }
}
