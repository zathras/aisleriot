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

import 'dart:collection';
import 'dart:math';

import 'package:aisleriot/graphics.dart';
import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;

import '../controller.dart';

abstract class Board<ST extends Slot> {
  final List<ST> _activeSlots;

  Board(List<ST> activeSlots) : _activeSlots = List.unmodifiable(activeSlots) {
    for (int i = 0; i < _activeSlots.length; i++) {
      assert(i == _activeSlots[i].slotNumber);
    }
  }

  bool get gameWon;

  ST slotFromNumber(int slotNumber) => _activeSlots[slotNumber];

  @override
  int get hashCode => quiver.hashObjects(Iterable<int>.generate(
      _activeSlots.length, (i) => _activeSlots[i].contentHash));

  @override
  bool operator ==(Object other) {
    if (!(other is SearchBoard<ST>)) {
      return false;
    }
    for (int i = 0; i < _activeSlots.length; i++) {
      if (!_activeSlots[i].contentEquals(other._activeSlots[i])) {
        return false;
      }
    }
    return true;
  }

  /// button-pressed
  bool canSelect(CardStack<ST> s);

  bool canDrop(FoundCard<ST> card, ST dest);

  List<Move<ST>> automaticMoves();

  SearchBoard<ST> toSearchBoard();
}

abstract class SearchBoard<ST extends Slot> extends Board<ST> {
  SearchBoard(List<ST> activeSlots) : super(activeSlots);

  /// Get a 32 bit signed integer saying how good this solution is.
  /// Bigger values are better.
  int get goodness;
  SearchBoard<ST>? get from;
  Move<ST>? get via;

  @override
  SearchBoard<ST> toSearchBoard() => this;

  void calculateChildren(covariant void Function(SearchBoard<ST> child) f);
}

abstract class Game<ST extends Slot> {
  final List<SlotOrLayout> slots;

  Game(List<SlotOrLayout> slots) : slots = List.unmodifiable(slots) {
    assert(slots.last is CarriageReturnSlot);
    for (final s in slots) {
      assert((!(s is Slot)) || (s is ST));
    }
  }

  GameController<ST> makeController() => GameController<ST>(this);

  Board<ST> get board;

  List<Move<ST>> doubleClick(CardStack<ST> s);
}

abstract class SlotOrLayout {
  void visit(
      {void Function(NormalSlot)? normal,
      void Function(ExtendedSlot)? extended,
      void Function(CarriageReturnSlot)? cr,
      void Function(HorizontalSpaceSlot)? horizontalSpace});
}

/// A slot that is visible and holds cards
abstract class Slot extends SlotOrLayout {
  final List<Card> _cards;

  final int slotNumber;

  Slot(this.slotNumber, {Slot? copyFrom})
      : _cards = copyFrom == null
            ? List<Card>.empty(growable: true)
            : List<Card>.from(copyFrom._cards, growable: true);

  bool get isEmpty => _cards.isEmpty;
  bool get isNotEmpty => _cards.isNotEmpty;

  Card get top => _cards[_cards.length - 1];

  Card? get belowTop => _cards.length > 1 ? _cards[_cards.length - 1] : null;

  int get numCards => _cards.length;

  void moveStackTo(CardStack stack, Slot dest) {
    dest._cards
        .addAll(_cards.getRange(_cards.length - stack.numCards, _cards.length));
    _cards.length -= stack.numCards;
  }

  void addCard(Card dealt) => _cards.add(dealt);

  Iterable<Card> get fromTop =>
      Iterable.generate(_cards.length, (i) => _cards[_cards.length - 1 - i]);

  Iterable<Card> get fromBottom =>
      Iterable.generate(_cards.length, (i) => _cards[i]);

  int get contentHash => quiver.hashObjects(_cards);

  bool contentEquals(Slot other) => quiver.listsEqual(_cards, other._cards);
}

/// A slot in which the topmost card is visible.  To be extended or implemented
/// by a game.
abstract class NormalSlot extends Slot {
  NormalSlot(int slotNumber, {NormalSlot? copyFrom})
      : super(slotNumber, copyFrom: copyFrom);

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
abstract class ExtendedSlot extends Slot {
  ExtendedSlot(int slotNumber,
      {ExtendedSlot? copyFrom, double horizPosOffset = 0})
      : super(slotNumber, copyFrom: copyFrom);

  @override
  void visit(
          {void Function(NormalSlot)? normal,
          void Function(ExtendedSlot)? extended,
          void Function(CarriageReturnSlot)? cr,
          void Function(HorizontalSpaceSlot)? horizontalSpace}) =>
      (extended == null) ? null : extended(this);
}

/// The carriage-return pseudo slot
class CarriageReturnSlot extends SlotOrLayout {
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

class HorizontalSpaceSlot extends SlotOrLayout {
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
  final cards = List<Card>.generate(52, _generator, growable: false);
  List<Card>? _undealt;
  List<Card> get undealt => _undealt ?? (_undealt = List.from(cards));

  Deck() {
    for (int i = 0; i < cards.length; i++) {
      assert(cards[i].index == i);
    }
  }

  static Card _generator(int index) {
    Suit s = Suit.values[index ~/ 13];
    int v = index % 13 + 1;
    return Card(v, s);
  }

  bool get isEmpty => undealt.isEmpty;

  Card dealCard() => undealt.removeAt(_random.nextInt(undealt.length));
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

  static List<Suit> values = [club, diamond, heart, spade];

  @override
  String toString() => 'Suit($name)';
}

enum CardColor { red, black }

/// A stack of one or more cards taken from the top of a slot.  The "top"
/// is painted lowest on the screen, over the lower cards.
class CardStack<ST extends Slot> {
  final ST slot;
  final int numCards;

  /// The bottom of the stack (painted highest on the screen, under the other
  /// cards).
  final Card bottom;

  CardStack(this.slot, this.numCards, this.bottom);
}

///
/// A stack of one or more cards pulled from a slot
///
class SlotStack<ST extends Slot> {
  final ST slot;
  final int numCards;

  SlotStack(this.slot, this.numCards);

  int get cardNumber => slot._cards.length - numCards;
}

///
/// Move the cards from [src] to [dest].
///
class Move<ST extends Slot> {
  final CardStack<ST> src;
  final ST dest;
  final bool animate;

  Move({required this.src, required this.dest, this.animate = true});

  ST get slot => src.slot;

  Card get bottom => src.bottom;

  int get numCards => src.numCards;

  void move() => src.slot.moveStackTo(src, dest);
}
