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
import 'dart:typed_data';

import 'package:aisleriot/graphics.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'controller.dart';
import 'settings.dart';

abstract class Board<ST extends Slot, SD extends SlotData> {
  SD slotData;
  final List<ST> _activeSlots;
  final _slotGroupCounts = List<int>.empty(growable: true);

  Board(this.slotData) : _activeSlots = List<ST>.empty(growable: true);

  void debugPrintGoodness();

  void addActiveSlotGroup(Iterable<ST> slots) {
    _slotGroupCounts.add(slots.length);
    for (final slot in slots) {
      assert(disableDebug || slot.slotNumber == _activeSlots.length);
      _activeSlots.add(slot);
    }
  }

  ST slotFromNumber(int slotNumber) => _activeSlots[slotNumber];

  int get numSlots => _activeSlots.length;

  bool get gameWon;

  /// button-pressed
  bool canSelect(CardStack<ST> s);

  bool canDrop(FoundCard<ST> card, ST dest);

  List<Move<ST>> automaticMoves();

  void doAllAutomaticMoves() {
    for (;;) {
      final moves = automaticMoves();
      if (moves.isEmpty) {
        break;
      }
      for (final m in moves) {
        m.move();
      }
    }
  }

  Board<ST, SearchSlotData> makeSearchBoard();

  /// scratch should be identical to this, but it has a more specific type.
  void calculateChildren(covariant Board<ST, SearchSlotData> scratch,
      bool Function(SearchSlotData child) accepted);

  void canonicalize() {
    int start = 0;
    for (final c in _slotGroupCounts) {
      final end = start + c;
      slotData._sortSlots(start, end);
      start = end;
    }
  }

  String toExternal() {
    final sd = slotData;
    final SearchSlotData ssd = (sd is SearchSlotData) ? sd : slotData.copy(0);
    return ssd.toExternal(externalID);
  }

  String get externalID;

  void setFromExternal(String cd) {
    if (!cd.startsWith(externalID)) {
      throw ArgumentError('$externalID is not the start of buffer "$cd".');
    }
    slotData.setFromExternal(cd.substring(externalID.length));
  }
}

abstract class Game<ST extends Slot> {
  final List<SlotOrLayout> slots;
  final Settings settings;
  final _undoStack = List<UndoRecord<ST>>.empty(growable: true);
  int _undoPos = 0;
  bool lost = false;

  Game(List<SlotOrLayout> slots, this.settings)
      : slots = List.unmodifiable(slots) {
    assert(slots.last is CarriageReturnSlot);
    for (final s in slots) {
      assert((s is! Slot) || (s is ST));
    }
  }

  GameController<ST> makeController() => GameController<ST>(this);

  /// Unique ID, for use in table of scores
  String get id;

  Board<ST, ListSlotData> get board; // must be final in subclass

  List<Move<ST>> doubleClick(CardStack<ST> s);

  Game<ST> newGame();

  bool get gameWon => board.gameWon;
  bool get gameStarted => _undoStack.isNotEmpty || lost;

  void addUndo(UndoRecord<ST> u) {
    _undoStack.length = _undoPos++;
    _undoStack.add(u);
  }

  bool get canUndo => _undoPos > 0;
  bool get canRedo => _undoPos < _undoStack.length;
  UndoRecord<ST> takeUndo() => _undoStack[--_undoPos];
  UndoRecord<ST>? takeRedo({required bool onlyAutomatic}) {
    final u = _undoStack[_undoPos];
    if (onlyAutomatic && board.automaticMoves().isEmpty) {
      return null;
    } else {
      _undoPos++;
      return u;
    }
  }
}

class UndoRecord<ST extends Slot> {
  final ST src;
  final ST dest;
  final int numCards;
  bool automatic;
  final String? debugComment;

  UndoRecord(Move<ST> move)
      : src = move.src.slot,
        dest = move.dest,
        numCards = move.src.numCards,
        automatic = move.automatic,
        debugComment = move.debugComment;

  void printComment() {
    if (debugComment != null) {
      debugPrint(debugComment);
    }
  }
}

abstract class SlotOrLayout {
  void visit(
      {void Function(NormalSlot)? normal,
      void Function(ExtendedSlot)? extended,
      void Function(CarriageReturnSlot)? cr,
      void Function(HorizontalSpaceSlot)? horizontalSpace});
}

abstract class SlotData {
  final int numSlots;

  SlotData(this.numSlots);

  CardList operator [](int i);

  int get depth;

  SearchSlotData copy(int depth);

  void _sortSlots(int start, int end);

  void setFromExternal(String ext);
}

class ListSlotData extends SlotData {
  final List<BigCardList> _lists;

  ListSlotData(int numSlots)
      : _lists = List.generate(numSlots, (_) => BigCardList()),
        super(numSlots);

  @override
  CardList operator [](int i) => _lists[i];

  @override
  int get depth => 0;

  @override
  SearchSlotData copy(int depth) {
    final r = SearchSlotData(numSlots: _lists.length, depth: depth, from: null);
    for (int i = 0; i < _lists.length; i++) {
      CardList dest = r[i];
      for (final c in _lists[i].fromBottom) {
        dest.add(c);
      }
    }
    assert(disableDebug || r._assertListsOK());
    return r;
  }

  @override
  void _sortSlots(int start, int end) => throw 'unreachable';

  @override
  void setFromExternal(String ext) {
    final ssd = copy(0);
    ssd.setFromExternal(ext);
    for (int i = 0; i < _lists.length; i++) {
      final dest = _lists[i];
      dest._reset();
      final CardList src = ssd[i];
      for (final c in src.fromBottom) {
        dest.add(c);
      }
    }
  }
}

abstract class CardList {
  bool get isEmpty;
  bool get isNotEmpty;
  Card get top;
  Card? get belowTop;
  int get numCards;
  void moveStackTo(int numCards, covariant CardList dest);
  void add(Card c);

  Iterable<Card> get fromTop;

  Iterable<Card> get fromBottom;
}

class BigCardList extends CardList {
  final _cards = List<Card>.empty(growable: true);

  @override
  bool get isEmpty => _cards.isEmpty;
  @override
  bool get isNotEmpty => _cards.isNotEmpty;
  @override
  Card get top => _cards[_cards.length - 1];
  @override
  Card? get belowTop => _cards.length > 1 ? _cards[_cards.length - 1] : null;
  @override
  int get numCards => _cards.length;

  @override
  void moveStackTo(int numCards, BigCardList dest) {
    dest._cards
        .addAll(_cards.getRange(_cards.length - numCards, _cards.length));
    _cards.length -= numCards;
  }

  @override
  void add(Card c) => _cards.add(c);

  @override
  Iterable<Card> get fromTop =>
      Iterable.generate(_cards.length, (i) => _cards[_cards.length - 1 - i]);

  @override
  Iterable<Card> get fromBottom =>
      Iterable.generate(_cards.length, (i) => _cards[i]);

  void _reset() => _cards.length = 0;
}

class SearchSlotData extends SlotData {
  double goodness = -1;
  double timeUsed;
  final Uint8List _raw;

  @override
  final int depth;

  final SearchSlotData? from;
  int viaSlotFrom = 0;
  int viaSlotTo = 0;
  int viaNumCards = 0;

  SearchSlotData(
      {required int numSlots, required this.depth, required this.from})
      : _raw = _makeRaw(numSlots),
        timeUsed = 0,
        super(numSlots) {
    assert(disableDebug ||
        () {
          for (int i = 0; i < _numCards; i++) {
            _raw[i] = _uninitialized;
          }
          return true;
        }());
    for (int i = 0; i < numSlots; i++) {
      final SearchCardList s = this[i];
      s._numCards = 0;
      s._top = _endList;
    }
  }

  SearchSlotData._copy(this.depth, SearchSlotData other)
      : _raw = Uint8List.fromList(other._raw),
        from = other,
        timeUsed = other.timeUsed,
        super(other.numSlots);

  static const _numCards = 52;
  static const _endList = 0xff;
  static const _uninitialized = 0xfe;

  static Uint8List _makeRaw(int numSlots) {
    int bytes = _numCards + numSlots * 2;
    if (kIsWeb) {
      bytes = ((bytes + 3) ~/ 4) * 4;
    } else {
      bytes = ((bytes + 7) ~/ 8) * 8;
    }
    return Uint8List(bytes);
  }

  int _slotAddress(int i) => _numCards + 2 * i;

  @override
  SearchCardList operator [](int i) => SearchCardList(_raw, _slotAddress(i));

  @override
  SearchSlotData copy(int depth) => SearchSlotData._copy(depth, this);

  List<int> get raw {
    if (kIsWeb) {
      return Uint32List.sublistView(_raw);
    } else {
      return Uint64List.sublistView(_raw);
    }
  }

  bool _assertListsOK() {
    for (int i = 0; i < numSlots; i++) {
      assert(this[i]._listOK());
    }
    return true;
  }

  @override
  void _sortSlots(int start, int end) =>
      Uint16List.sublistView(_raw, _slotAddress(start), _slotAddress(end))
          .sort();

  String toExternal(String typeID) {
    final sb = StringBuffer();

    void writeCard(int card) {
      if (card == _endList) {
        sb.write('0');
      } else {
        assert(card < _numCards);
        sb.write('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
            .substring(card, card + 1));
      }
    }

    sb.write(typeID);
    for (int i = 0; i < numSlots; i++) {
      writeCard(_raw[_slotAddress(i) + 1]);
    }
    for (int i = 0; i < _numCards; i++) {
      writeCard(_raw[i]);
    }
    return sb.toString();
  }

  static final int _cu0 = '0'.codeUnitAt(0);
  static final int _cuA = 'A'.codeUnitAt(0);
  static final int _cuZ = 'Z'.codeUnitAt(0);
  static final int _cua = 'a'.codeUnitAt(0);
  static final int _cuz = 'z'.codeUnitAt(0);

  @override
  void setFromExternal(String ext) {
    int charToCard(int cu) {
      if (cu == _cu0) {
        return _endList;
      } else if (cu >= _cua && cu <= _cuz) {
        return cu - _cua;
      } else if (cu >= _cuA && cu <= _cuZ) {
        return cu - _cuA + 26;
      } else {
        throw ArgumentError();
      }
    }

    for (int i = 0; i < _numCards; i++) {
      _raw[i] = charToCard(ext.codeUnitAt(i + numSlots));
    }
    for (int i = 0; i < numSlots; i++) {
      final addr = _slotAddress(i);
      var curr = _raw[addr + 1] = charToCard(ext.codeUnitAt(i));
      _raw[addr] = 0;
      while (curr != _endList) {
        _raw[addr]++;
        curr = _raw[curr];
      }
    }
  }
}

class SearchCardList implements CardList {
  final Uint8List _raw;
  final int _offset;

  SearchCardList(this._raw, this._offset);

  @override
  int get numCards => _raw[_offset];

  set _numCards(int v) => _raw[_offset] = v;

  int get _top => _raw[_offset + 1];

  set _top(int v) => _raw[_offset + 1] = v;

  @override
  bool get isEmpty => numCards == 0;

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  Card get top => Deck.cards[_top];

  @override
  Card? get belowTop => (numCards > 1) ? Deck.cards[_raw[_top]] : null;

  @override
  void add(Card c) {
    assert(disableDebug || _raw[c.index] == SearchSlotData._uninitialized);
    _raw[c.index] = _top;
    _top = c.index;
    _raw[_offset]++;
  }

  @override
  Iterable<Card> get fromTop => _SearchCardListIterable(this);

  @override
  Iterable<Card> get fromBottom => List<Card>.from(fromTop).reversed;

  // It's OK that this is a little slow - it's only used for painting,
  // and we don't paint card dragging animations of this kind of deck.

  @override
  void moveStackTo(int numCards, covariant SearchCardList dest) {
    assert(disableDebug || dest != this);
    assert(disableDebug || numCards > 0);
    assert(disableDebug || numCards <= this.numCards,
        '$numCards > ${this.numCards}');
    int addr = _offset + 1; // Address of _top;
    int top = _raw[addr];
    for (int i = 0; i < numCards; i++) {
      addr = _raw[addr];
      assert(disableDebug || addr < SearchSlotData._numCards);
    }
    _raw[_offset] -= numCards;
    _raw[_offset + 1] = _raw[addr];
    _raw[dest._offset] += numCards;
    _raw[addr] = _raw[dest._offset + 1];
    _raw[dest._offset + 1] = top;
    assert(disableDebug || _listOK());
    assert(disableDebug || dest._listOK());
  }

  bool _listOK() {
    assert(disableDebug || numCards == fromTop.length,
        '$numCards, ${fromTop.length}');
    return true;
  }
}

class _SearchCardListIterable extends IterableBase<Card> {
  final SearchCardList _list;
  _SearchCardListIterable(this._list);

  @override
  Iterator<Card> get iterator => _SearchCardListIterator(_list);
}

class _SearchCardListIterator extends Iterator<Card> {
  final SearchCardList _list;
  int _current;

  _SearchCardListIterator(SearchCardList list)
      : _list = list,
        _current = list._offset + 1; // address of _top

  @override
  bool moveNext() {
    if (_current == SearchSlotData._endList) {
      return false;
    }
    _current = _list._raw[_current];
    assert(disableDebug ||
        _current < SearchSlotData._numCards ||
        _current == SearchSlotData._endList);
    return _current != SearchSlotData._endList;
  }

  @override
  Card get current => Deck.cards[_current];
}

/// A slot that is visible and holds cards
abstract class Slot extends SlotOrLayout {
  final Board board;
  final int slotNumber;

  Slot(this.board, this.slotNumber);

  CardList get _cards => board.slotData[slotNumber];

  bool get isEmpty => _cards.isEmpty;
  bool get isNotEmpty => _cards.isNotEmpty;
  Card get top => _cards.top;
  Card? get belowTop => _cards.belowTop;
  int get numCards => _cards.numCards;

  void moveStackTo(int numCards, Slot dest) =>
      _cards.moveStackTo(numCards, dest._cards);

  void addCard(Card dealt) => _cards.add(dealt);

  Iterable<Card> get fromTop => _cards.fromTop;

  Iterable<Card> get fromBottom => _cards.fromBottom;

  Card cardDownFromTop(int num) {
    if (num < 0 || num >= numCards) {
      throw ArgumentError.value(num, 'not between 0 and ${numCards - 1}');
    }
    for (final c in fromTop) {
      if (num == 0) {
        return c;
      }
      num--;
    }
    throw StateError('unreachable');
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write(runtimeType);
    sb.write(' - ');
    for (final c in fromTop) {
      sb.write(c);
      sb.write(' ');
    }
    return sb.toString();
  }
}

/// A slot in which the topmost card is visible.  To be extended or implemented
/// by a game.
abstract class NormalSlot extends Slot {
  NormalSlot(Board board, int slotNumber) : super(board, slotNumber);

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
  ExtendedSlot(Board board, int slotNumber) : super(board, slotNumber);

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
  static final cards = List<Card>.generate(52, _generator, growable: false);
  List<Card>? _undealt;
  List<Card> get undealt => _undealt ?? (_undealt = List.from(cards));

  Deck() {
    for (int i = 0; i < cards.length; i++) {
      assert(disableDebug || cards[i].index == i);
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

  int get cardNumber => slot.numCards - numCards;
}

///
/// Move the cards from [src] to [dest].
///
class Move<ST extends Slot> {
  final CardStack<ST> src;
  final ST dest;
  final bool animate;
  final bool automatic;
  String? debugComment;

  Move(
      {required this.src,
      required this.dest,
      required this.automatic,
      this.animate = true});

  ST get slot => src.slot;

  Card get bottom => src.bottom;

  int get numCards => src.numCards;

  void move() => src.slot.moveStackTo(src.numCards, dest);
}
