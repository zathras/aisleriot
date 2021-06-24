/*
 Copyright (C) 2021, William Foote
 Copyright (C) 1998, 2003 Jonathan Blandford <jrb@mit.edu>

 Author: William Foote (Port from Scheme to Dart)


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

import 'package:aisleriot/graphics.dart';

import '../controller.dart';

abstract class Game<CS extends SlotWithCards> {
  final List<Slot> slots;

  Game(List<Slot> slots) : slots = List.unmodifiable(slots) {
    assert(slots.last is CarriageReturnSlot);
    for (final s in slots) {
      assert((!(s is SlotWithCards)) || (s is CS));
    }
  }

  GameController<CS> makeController() => GameController<CS>(this);

  /// button-pressed
  bool canSelect(SlotStack<CS> s);

  List<Move<CS>> doubleClick(SlotStack<CS> s);

  bool canDrop(FoundCard<CS> card, CS dest);
}

abstract class Slot {
  void visit(
      {void Function(NormalSlot)? normal,
      void Function(ExtendedSlot)? extended,
      void Function(CarriageReturnSlot)? cr,
      void Function(HorizontalSpaceSlot)? horizontalSpace});
}

/// A slot that is visible and holds cards (and not a pseudo-slot)
abstract class SlotWithCards extends Slot {
  /// Horizontal position offset, in fraction of a card width.  I *think* that's
  /// the same units as Aisleriot's HORIZPOZ in the Scheme files.
  final cards = List<Card>.empty(growable: true);

  SlotWithCards();

  bool get isEmpty => cards.isEmpty;
  bool get isNotEmpty => cards.isNotEmpty;
}

/// A slot in which the topmost card is visible.  To be extended by
/// a game.
abstract class NormalSlot extends SlotWithCards {
  NormalSlot();

  @override
  void visit(
          {void Function(NormalSlot)? normal,
          void Function(ExtendedSlot)? extended,
          void Function(CarriageReturnSlot)? cr,
          void Function(HorizontalSpaceSlot)? horizontalSpace}) =>
      (normal == null) ? null : normal(this);
}

/// A slot in which all the cards are visible, arranged as an
/// overlapped pile, proceeding down.  To be extended by a game.
abstract class ExtendedSlot extends SlotWithCards {
  ExtendedSlot({double horizPosOffset = 0});

  @override
  void visit(
          {void Function(NormalSlot)? normal,
          void Function(ExtendedSlot)? extended,
          void Function(CarriageReturnSlot)? cr,
          void Function(HorizontalSpaceSlot)? horizontalSpace}) =>
      (extended == null) ? null : extended(this);
}

/// The carriage-return pseudo slot
class CarriageReturnSlot extends Slot {
  /// Height beyond the stacks in our row, in card-heights.
  final double extraHeight;

  CarriageReturnSlot({this.extraHeight = 0});

  @override
  void visit(
          {void Function(NormalSlot)? normal,
          void Function(ExtendedSlot)? extended,
          void Function(CarriageReturnSlot)? cr,
          void Function(HorizontalSpaceSlot)? horizontalSpace}) =>
      (cr == null) ? null : cr(this);
}

class HorizontalSpaceSlot extends Slot {
  final double width;

  HorizontalSpaceSlot(this.width);

  @override
  void visit(
          {void Function(NormalSlot)? normal,
          void Function(ExtendedSlot)? extended,
          void Function(CarriageReturnSlot)? cr,
          void Function(HorizontalSpaceSlot)? horizontalSpace}) =>
      (horizontalSpace == null) ? null : horizontalSpace(this);
}

class Deck {
  static final _random = Random();
  final _cards = List<Card>.generate(52, _generator, growable: true);

  static Card _generator(int index) {
    Suit s = Suit.values[index ~/ 13];
    int v = index % 13 + 1;
    return Card(v, s);
  }

  bool get isEmpty => _cards.isEmpty;

  Card dealCard() => _cards.removeAt(_random.nextInt(_cards.length));
}

class Card {
  int value; // Ace is 1, Jack is 11, Queen is 12, King is 13
  Suit suit;

  Card(this.value, this.suit);

  /// A zero-based index value that can be used for mappings.
  int get index => suit.row * 13 + value - 1;

  @override
  String toString() => 'Card($value ${suit.name})';
}

class Suit {
  final int row; // Row in the image file
  final CardColor color;
  final String name;

  const Suit._p(this.row, this.color, this.name);

  static const club = Suit._p(0, CardColor.black, 'Clubs');
  static const diamond = Suit._p(1, CardColor.red, 'Diamonds');
  static const heart = Suit._p(2, CardColor.red, 'Hearts');
  static const spade = Suit._p(3, CardColor.black, 'Spades');

  static List<Suit> values = [spade, diamond, heart, club];

  @override
  String toString() => 'Suit($name)';
}

enum CardColor { red, black }

///
/// A stack of one or more cards pulled from a slot
///
class SlotStack<CS extends SlotWithCards> {
  final CS slot;
  final int cardNumber;

  SlotStack(this.slot, this.cardNumber);

  @override
  String toString() => slot.cards[cardNumber].toString();

  int get length => slot.cards.length - cardNumber;

  /// Highest on the screen, which means the rest of the cards are,
  /// confusingly, partly covering this card.
  Card get highest => slot.cards[cardNumber];

  Card get lowest => slot.cards.last;

  CardList? toList() {
    CardList? node;
    for (int i = cardNumber; i < slot.cards.length; i++) {
      final n = CardList(slot.cards[i], node);
      node = n;
    }
    return node;
  }
}

///
/// A Scheme-like list for the list of cards.  Car is the lowest
/// card on the stack, and the end of the list is the highest (that is,
/// the one being moved in a supermove).
///
class CardList {
  Card car;
  CardList? cdr;

  CardList(this.car, this.cdr);

  Card get cadr => cdr!.car;
}

///
/// Move the cards from [src] to [dest].
///
class Move<CS extends SlotWithCards> {
  final CS src;
  final CS dest;
  final int numCards;
  final bool animate;

  Move(
      {required this.src,
      required this.dest,
      this.numCards = 1,
      this.animate = true});

  Card get topMovingCard => src.cards[src.cards.length - numCards];

  void move() {
    final sl = src.cards;
    for (int i = sl.length - numCards; i < sl.length; i++) {
      dest.cards.add(sl[i]);
    }
    sl.length -= numCards;
  }
}
