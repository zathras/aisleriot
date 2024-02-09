/*
 Copyright (C) 2021, William Foote
 Copyright (C) 1998, 2003 Changwoo Ryu

 Author: William Foote (Port from Scheme to Dart)
         Changwoo Ryu <cwryu@adam.kaist.ac.kr> (Original Scheme version)

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

library aisleriot;

import 'dart:math';

import 'package:aisleriot/graphics.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../game.dart';
import '../settings.dart';

abstract class ARGenericSlot implements Slot {
  /// Is moving movable to us?
  bool movableTo(SlotStack moving, FreecellBoard board);

  bool canSelect(SlotStack cards, FreecellBoard board);
}

typedef SlotStack = CardStack<ARGenericSlot>;
typedef ARMove = Move<ARGenericSlot>;
typedef ARFoundCard = FoundCard<ARGenericSlot>;

class _FreecellSlot extends NormalSlot implements ARGenericSlot {
  _FreecellSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(SlotStack cards, FreecellBoard board) => true;

  /// movable-to-freecell?
  @override
  bool movableTo(SlotStack moving, FreecellBoard board) =>
      isEmpty && moving.numCards == 1;
}

class _HomecellSlot extends NormalSlot implements ARGenericSlot {
  _HomecellSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(SlotStack cards, FreecellBoard board) => false;

  /// movable-to-homecell?
  @override
  bool movableTo(SlotStack moving, FreecellBoard board) {
    if (moving.slot == this || moving.numCards != 1) {
      return false;
    }
    final card = moving.slot.top;
    if (isEmpty) {
      return card.value == 1;
    } else {
      return top.suit == card.suit && top.value + 1 == card.value;
    }
  }

  ///
  /// Is this card eligible for a move to a homecell, based on the minimum
  /// card values tehre now?  This is a little tricky.  It's true if c
  /// couldn't possibly be needed in the field to put another card on.
  ///
  static bool cardAutoEligible(Card c, List<int> homecellMin) {
    final minThisColor = homecellMin[c.suit.color.index];
    final minOtherColor = homecellMin[1 - c.suit.color.index];
    if (c.value <= minOtherColor + 1) {
      return true;
    } else if (c.value == minOtherColor + 2) {
      return c.value <= minThisColor + 2;
    } else {
      return false;
    }
  }
}

class _FieldSlot extends ExtendedSlot implements ARGenericSlot {
  _FieldSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(SlotStack cards, FreecellBoard board) =>
      FreecellBoard.fieldSequenceQ(cards);

  /// Based on movable-to-field?, but we already know the cards being
  /// considered are a sequence.
  @override
  bool movableTo(SlotStack moving, FreecellBoard board) {
    if (moving.slot == this) {
      return false;
    }
    if (moving.numCards >
        (board.emptyFreecellCount() + 1) *
            _pow2(board.emptyFieldCount() - (isEmpty ? 1 : 0))) {
      // Note:  freecell.scm has a bit of code here that does nothing:
      //          (if (empty-slot? start-slot) 1 0)
      //        Start slot *can't* be empty, because card-list is there.
      //        And because of that, the max() does nothing.
      return false;
    }
    return isEmpty || FreecellBoard.fieldJoinQ(top, moving.bottom);
  }
}

class FreecellBoard<SD extends SlotData> extends Board<ARGenericSlot, SD> {
  late final List<_FreecellSlot> _freecell;
  late final List<_HomecellSlot> _homecell;
  late final List<_FieldSlot> _field;

  FreecellBoard(SD slotData) : super(slotData) {
    int slotNumber = 0;
    final freecell = List.generate(4, (i) => _FreecellSlot(this, slotNumber++),
        growable: false);
    final homecell = List.generate(4, (i) => _HomecellSlot(this, slotNumber++),
        growable: false);
    final field = List.generate(8, (_) => _FieldSlot(this, slotNumber++),
        growable: false);
    addActiveSlotGroup(freecell);
    this._freecell = List.unmodifiable(freecell);
    addActiveSlotGroup(homecell);
    this._homecell = List.unmodifiable(homecell);
    addActiveSlotGroup(field);
    this._field = List.unmodifiable(field);
  }

  @override
  bool get gameWon => _homecell.every((s) => s.isNotEmpty && s.top.value == 13);

  @override
  bool canSelect(SlotStack s) => s.slot.canSelect(s, this);

  @override
  bool canDrop(ARFoundCard card, ARGenericSlot dest) =>
      dest.movableTo(card, this);

  /// field-join?
  static bool fieldJoinQ(Card lower, Card upper) =>
      lower.suit.color != upper.suit.color && lower.value == upper.value + 1;

  /// field-sequence?
  static bool fieldSequenceQ(SlotStack cards) {
    Card? upper;
    int toGo = cards.numCards;
    assert(disableDebug || toGo > 0);
    for (final card in cards.slot.fromTop) {
      final u = upper;
      if (u != null && !fieldJoinQ(card, u)) {
        return false;
      }
      if (--toGo == 0) {
        break;
      }
      upper = card;
    }
    return true;
  }

  /// empty-field-number
  int emptyFieldCount() =>
      _field.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  /// empty-freecell-number
  int emptyFreecellCount() =>
      _freecell.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  /// Indexed by CardColor.index
  List<int> minimumHomecellValues() {
    final result = List.filled(2, 99);
    final count = List.filled(2, 0);
    for (final s in _homecell) {
      if (s.isNotEmpty) {
        final c = s.top;
        result[c.suit.color.index] = min(result[c.suit.color.index], c.value);
        count[c.suit.color.index]++;
      }
    }
    for (int i = 0; i < 2; i++) {
      if (count[i] < 2) {
        result[i] = 0;
      }
    }
    return result;
  }

  @override
  List<ARMove> automaticMoves() {
    final homecellMin = minimumHomecellValues();
    ARMove? check(ARGenericSlot slot) {
      if (slot.isNotEmpty) {
        if (_HomecellSlot.cardAutoEligible(slot.top, homecellMin)) {
          final stack = CardStack(slot, 1, slot.top);
          for (final dest in _homecell) {
            if (dest.movableTo(stack, this)) {
              return ARMove(src: stack, dest: dest, automatic: true);
            }
          }
        }
      }
      return null;
    }

    for (final slot in _freecell) {
      final m = check(slot);
      if (m != null) {
        return [m];
      }
    }
    for (final slot in _field) {
      final m = check(slot);
      if (m != null) {
        return [m];
      }
    }
    return const [];
  }

  @override
  void debugPrintGoodness() =>
      debugPrint('Goodness now ${_calculateGoodness()}');

  double _calculateGoodness() {
    double weight = 0;
    int emptyFreecells = 0;
    for (final s in _freecell) {
      if (s.isEmpty) {
        emptyFreecells++;
      } else {
        weight++;
      }
    }
    int emptyFields = 0;
    for (final s in _field) {
      Card? upper;
      if (s.isEmpty) {
        emptyFields++;
      }
      double stackWeight = 0;
      double stackWeightIncr = 0.25;
      for (final card in s.fromTop) {
        final u = upper;
        if (u == null) {
          weight += stackWeight + 1;
        } else if (!FreecellBoard.fieldJoinQ(card, u)) {
          weight += stackWeight + 1;
          stackWeight = 0;
          // Don't change stackWeightIncr - buried runs are still good,
          // but not as good as unburied ones.
        } else {
          stackWeight += stackWeightIncr;
          stackWeightIncr += 0.01; // slightly encourage balanced stacks
        }
        upper = card;
      }
      if (upper?.value == 13) {
        // encourage king on bottom
        weight -= 1;
      } else {
        weight += stackWeight;
      }
    }
    int homeMin = 99;
    int redMax = 0;
    int blackMax = 0;
    for (final s in _homecell) {
      homeMin = min(homeMin, s.numCards);
      if (s.isNotEmpty) {
        if (s.top.suit.color == CardColor.black) {
          blackMax = max(blackMax, s.top.value);
        } else {
          redMax = max(redMax, s.top.value);
        }
      }
    }
    final minMax = min(blackMax, redMax);
    double bonus = 20.0 * minMax + 100.0 * homeMin;
    int mobility = (emptyFreecells + 1) * _pow2(emptyFields);
    // print("  mobility $mobility weight $weight bonus $bonus");
    mobility = min(mobility, 6);
    mobility *= 10000;
    weight = max(99 - weight, 0);
    return bonus + mobility + weight * 100 + max(99 - slotData.depth, 0);
  }

  @override
  FreecellBoard<SearchSlotData> makeSearchBoard() =>
      FreecellBoard(slotData.copy(0));

  @override
  void calculateChildren(FreecellBoard<SearchSlotData> scratch,
          bool Function(SearchSlotData child) accepted) =>
      _ChildCalculator(scratch, accepted).run();

  @override
  String get externalID => 'f0'; // freecell version 0
}

class _ChildCalculator {
  final FreecellBoard<SearchSlotData> scratch;
  final bool Function(SearchSlotData child) accepted;

  _ChildCalculator(this.scratch, this.accepted);

  void run() {
    final SearchSlotData initial = scratch.slotData;
    for (final s in scratch._freecell) {
      if (s.isNotEmpty) {
        final src = SlotStack(s, 1, s.top);
        moveTo(src, scratch._homecell, justOne: true);
        moveTo(src, scratch._field);
      }
    }
    for (final s in scratch._field) {
      tryFromField(s);
    }
    assert(disableDebug || identical(scratch.slotData, initial));
  }

  void moveTo(SlotStack src, List<ARGenericSlot> slots,
      {bool justOne = false, int openedFieldMinValue = -1}) {
    final SearchSlotData initial = scratch.slotData;
    for (final dest in slots) {
      if (dest != src.slot && dest.movableTo(src, scratch)) {
        final child = initial.copy(initial.depth + 1);
        scratch.slotData = child;
        child.viaSlotFrom = src.slot.slotNumber;
        child.viaSlotTo = dest.slotNumber;
        child.viaNumCards = src.numCards;
        ARMove(src: src, dest: dest, automatic: false).move();
        scratch.doAllAutomaticMoves();
        final srcTop = src.slot.isEmpty ? null : src.slot.top;
        scratch.canonicalize();
        child.goodness = scratch._calculateGoodness();
        final more = accepted(child);
        if (more) {
          if (openedFieldMinValue > -1) {
            tryFromFreecells(openedFieldMinValue);
          } else if (srcTop != null) {
            // src must be a field slot, so we explore further up that slot.
            _FieldSlot? newSrc;
            for (final s in scratch._field) {
              if (s.top == srcTop) {
                newSrc = s;
                break;
              }
            }
            assert(newSrc != null);
            tryFromField(newSrc!);
            tryToField(newSrc, 0);
          } else if (src.slot is _FieldSlot) {
            // We just opened up a field slot
            _FieldSlot? newSrc;
            for (final s in scratch._field) {
              if (s.isEmpty) {
                newSrc = s;
                break;
              }
            }
            assert(newSrc != null);
            tryToField(newSrc!, src.bottom.value + 1);
          }
        }
        scratch.slotData = initial;
        if (justOne) {
          break;
        }
      }
    }
  }

  void tryFromFreecells(int openedFieldMinValue) {
    for (final s in scratch._freecell) {
      if (s.isNotEmpty && s.top.value >= openedFieldMinValue) {
        final src = SlotStack(s, 1, s.top);
        moveTo(src, scratch._field, openedFieldMinValue: 0);
      }
    }
  }

  void tryFromField(_FieldSlot s) {
    int numCards = 1;
    for (final bottom in s.fromTop) {
      final src = SlotStack(s, numCards, bottom);
      if (!s.canSelect(src, scratch)) {
        break;
      }
      moveTo(src, scratch._homecell, justOne: true);
      moveTo(src, scratch._freecell, justOne: true);
      moveTo(src, scratch._field);
      numCards++;
    }
  }

  /// Try moving cards to a (newly) open spot on slot dest
  void tryToField(_FieldSlot dest, int minValue) {
    final destList = [dest];
    for (final s in scratch._freecell) {
      if (s.isNotEmpty) {
        final src = SlotStack(s, 1, s.top);
        moveTo(src, destList, openedFieldMinValue: minValue);
      }
    }
    for (final s in scratch._field) {
      if (s != dest) {
        int numCards = 1;
        for (final bottom in s.fromTop) {
          final src = SlotStack(s, numCards, bottom);
          if (!s.canSelect(src, scratch)) {
            break;
          }
          moveTo(src, destList, openedFieldMinValue: minValue);
          numCards++;
        }
      }
    }
  }
}

class Freecell extends Game<ARGenericSlot> {
  @override
  final FreecellBoard<ListSlotData> board;

  Freecell._p(this.board, List<SlotOrLayout> slots, Settings settings)
      : super(slots, settings);

  factory Freecell(Settings settings) {
    Deck d = Deck();
    final board = FreecellBoard(ListSlotData(16));
    int f = 0;
    while (!d.isEmpty) {
      board._field[f].addCard(d.dealCard());
      f++;
      f %= board._field.length;
    }
    final allSlots = List<SlotOrLayout>.empty(growable: true);
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.4));
    for (final s in board._freecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.2));
    for (final s in board._homecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.4 - 1 / 24));
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.5));
    for (final s in board._field) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(CarriageReturnSlot(extraHeight: 0.2));
    return Freecell._p(board, allSlots, settings);
  }

  @override
  String get id => 'freecell';

  @override
  List<ARMove> doubleClick(SlotStack s) {
    if (board.canSelect(s)) {
      final homecellMin = board.minimumHomecellValues();
      final Card card = s.slot.top;
      if (_HomecellSlot.cardAutoEligible(card, homecellMin)) {
        for (final dest in board._homecell) {
          if (dest.movableTo(s, board)) {
            return [ARMove(src: s, dest: dest, automatic: false)];
          }
        }
      }
      for (final dest in board._freecell) {
        if (dest.movableTo(s, board)) {
          return [ARMove(src: s, dest: dest, automatic: false)];
        }
      }
    }
    return const [];
  }

  @override
  Freecell newGame() => Freecell(settings);
}

// 2^exp
int _pow2(int exp) => 1 << exp;
